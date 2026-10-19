import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 斗鱼 FLV 本地中继：把两条「5 分钟有效期」的原画链接拼成播放器眼里的一个连续流。
///
/// 背景：斗鱼给匿名/短时会话的原画链接带 `expire=300`，服务端到点直接断 TCP。
/// 只做「断了再重连」永远会有 1～2 秒黑屏；上游 pure_live 3.2.11 的做法是本地中继：
///
/// 1. 播放器连的是 `http://127.0.0.1:<port>/live/<id>`，与 CDN 之间由这里代理；
/// 2. 旧链接到期前 45 秒用同一房间的取流接口预取新链接；
/// 3. 新连接先只读不转发，丢弃切换点之前的帧，等遇到「第一个关键帧且时间戳
///    大于旧连接已发出的最大时间戳」时，把该关键帧开始的字节转发给播放器；
/// 4. 两条链接来自同一直播时间线，播放器看到的是时间戳单调、无缝的一段流。
///
/// 任何一步失败都只是「退回原来的断流自愈」，不会比现状更差。
class DouyuFlvRelay {
  DouyuFlvRelay._();

  static final DouyuFlvRelay instance = DouyuFlvRelay._();

  /// 只对斗鱼 CDN 启用；其他平台的链接时效策略不同，先不动。
  static bool shouldRelay(String url) {
    if (!url.startsWith('http')) return false;
    final host = Uri.tryParse(url)?.host ?? '';
    return host.contains('douyucdn') || host.contains('douyu.com');
  }

  /// 预取余量：比链接到期提前这么多秒去拿新链接。
  static const Duration prefetchMargin = Duration(seconds: 45);

  /// 预取下限，避免链接只剩几秒时疯狂重试。
  static const Duration minimumPrefetchDelay = Duration(seconds: 5);

  static const int _maxSessions = 16;

  HttpServer? _server;
  final Map<String, _RelayConfig> _sessions = {};
  int _seq = 0;

  int? get port => _server?.port;

  Future<int?> ensureStarted() async {
    final existing = _server;
    if (existing != null) return existing.port;
    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _server = server;
      server.listen(_handle, onError: (_) {});
      return server.port;
    } catch (_) {
      return null;
    }
  }

  /// 注册一个中继会话，返回给播放器用的本地地址；失败返回 null（调用方直连）。
  ///
  /// [refresh] 用同房间的取流接口取新地址（player_manager 的 streamEndedRefresher）；
  /// [fallbackUrls] 是本次已经拿到的备用线路，refresh 失败时退而求其次。
  Future<String?> createSession({
    required String sourceUrl,
    required Map<String, String> headers,
    Future<List<String>?> Function()? refresh,
    List<String> fallbackUrls = const <String>[],
  }) async {
    final port = await ensureStarted();
    if (port == null) return null;
    if (_sessions.length >= _maxSessions) {
      // 先进先出，避免长时间使用后会话表无限增长
      _sessions.remove(_sessions.keys.first);
    }
    final id = '${_seq++}';
    _sessions[id] = _RelayConfig(
      sourceUrl: sourceUrl,
      headers: headers,
      refresh: refresh,
      fallbackUrls: fallbackUrls,
    );
    return 'http://127.0.0.1:$port/live/$id';
  }

  Future<void> _handle(HttpRequest request) async {
    final segments = request.uri.pathSegments;
    final config = segments.isEmpty ? null : _sessions[segments.last];
    final response = request.response;
    if (config == null) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    response.statusCode = HttpStatus.ok;
    response.headers.set(HttpHeaders.contentTypeHeader, 'video/x-flv');
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.headers.set(HttpHeaders.connectionHeader, 'keep-alive');
    final pump = _RelayPump(config);
    try {
      await pump.run(response);
    } catch (_) {
      // 任一步失败都交给播放器的既有断流自愈
    } finally {
      await pump.dispose();
      try {
        await response.close();
      } catch (_) {}
    }
  }
}

class _RelayConfig {
  _RelayConfig({
    required this.sourceUrl,
    required this.headers,
    required this.refresh,
    required this.fallbackUrls,
  });

  final String sourceUrl;
  final Map<String, String> headers;
  final Future<List<String>?> Function()? refresh;
  final List<String> fallbackUrls;

  /// 链接自带的有效期，读不到时按斗鱼默认 5 分钟算。
  Duration get ttl {
    final uri = Uri.tryParse(sourceUrl);
    final expire = int.tryParse(uri?.queryParameters['expire'] ?? '');
    if (expire == null || expire <= 0) return const Duration(minutes: 5);
    // 少数 CDN 给的是绝对时间戳
    if (expire > 100000) {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final left = expire - now;
      return left > 0 ? Duration(seconds: left) : const Duration(minutes: 5);
    }
    return Duration(seconds: expire);
  }
}

/// 一次客户端连接：负责拉上游、转发、到期前预取并续接。
class _RelayPump {
  _RelayPump(this.config);

  final _RelayConfig config;

  _FlvTagStream? _current;
  _FlvTagStream? _next;

  bool _closed = false;
  bool _switched = false;

  /// 冻结点：预取到新链接后，旧连接继续正常转发；等快要到期（剩 3 秒）时先
  /// 只读不转发，让新连接的关键帧时间戳能超过旧连接的最后时间戳——
  /// 两条连接是同一时间线，旧连接一直在前进，不冻结的话新连接永远追不上。
  bool _frozen = false;
  int lastTimestamp = -1;

  Timer? _prefetchTimer;
  Timer? _freezeTimer;

  Future<void> run(HttpResponse out) async {
    final done = Completer<void>();
    out.done.catchError((_) {}).whenComplete(() => _closed = true);

    final first = await _open(config.sourceUrl);
    if (first == null) return;
    _current = first;
    final header = await first.readFlvHeader();
    if (header == null) return;
    // FLV 文件头 = 9 字节签名 + 4 字节 PreviousTagSize0(0)，少这 4 字节播放器会错位
    out.add(header);
    out.add(const <int>[0, 0, 0, 0]);

    _schedulePrefetch(out, done);

    unawaited(_pumpCurrent(out, done));
    await done.future;
  }

  Future<void> dispose() async {
    _closed = true;
    _prefetchTimer?.cancel();
    _freezeTimer?.cancel();
    await _current?.cancel();
    await _next?.cancel();
    _current = null;
    _next = null;
  }

  void _schedulePrefetch(HttpResponse out, Completer<void> done) {
    final ttl = config.ttl;
    var delay = ttl - DouyuFlvRelay.prefetchMargin;
    if (delay < DouyuFlvRelay.minimumPrefetchDelay) {
      delay = DouyuFlvRelay.minimumPrefetchDelay;
    }
    _prefetchTimer?.cancel();
    _prefetchTimer = Timer(delay, () async {
      if (_closed || _switched) return;
      final stream = await _openNext();
      if (stream == null || _closed || _switched) return;
      // 新连接同样带 FLV 文件头：必须读掉，否则会被当成 tag 解析（dataSize 错乱后直接卡死）
      final nextHeader = await stream.readFlvHeader();
      if (nextHeader == null) {
        debugPrint('[douyu-relay] 预取到的新连接不是有效 FLV，放弃本次续接');
        await stream.cancel();
        return;
      }
      _next = stream;
      debugPrint('[douyu-relay] 已预取到期前的新链接，等待到期前 3 秒冻结旧连接');
      unawaited(_pumpNext(out, done));
      // 预取点在到期前 45 秒，再等 42 秒就是到期前 3 秒：冻结旧连接转发
      _freezeTimer = Timer(const Duration(seconds: 42), () {
        if (_closed || _switched) return;
        _frozen = true;
        debugPrint('[douyu-relay] 冻结旧连接（最后 ts=$lastTimestamp），等新连接关键帧');
        Timer(const Duration(seconds: 4), () {
          if (_switched || _closed || !_frozen) return;
          _frozen = false;
          debugPrint('[douyu-relay] 冻结超时未接上，恢复旧连接转发（走原有断流自愈）');
        });
      });
    });
  }

  Future<void> _pumpCurrent(HttpResponse out, Completer<void> done) async {
    try {
      while (!_closed) {
        final tag = await _current!.next();
        if (tag == null) break;
        if (_switched) break;
        // 冻结期只读不转发：把最近的时间戳定格在 lastTimestamp，等新连接越过它
        if (_frozen) continue;
        out.add(tag.bytes);
        if (tag.timestamp > lastTimestamp) lastTimestamp = tag.timestamp;
      }
    } catch (_) {
      // 上游断开：交给播放器既有自愈
    } finally {
      // 正常切换（_switched）不算结束，新连接还在给播放器供货
      if (!_switched && !done.isCompleted) done.complete();
    }
  }

  Future<void> _pumpNext(HttpResponse out, Completer<void> done) async {
    try {
      while (!_closed) {
        final tag = await _next!.next();
        if (tag == null) break;
        if (!_switched) {
          // 切换前丢弃新连接的帧，只在「关键帧 + 时间戳领先」处接上
          if (tag.keyFrame && tag.timestamp > lastTimestamp) {
            _switched = true;
            debugPrint('[douyu-relay] 续接成功 ts=${tag.timestamp} (旧连接最后 ${lastTimestamp}ms)');
            out.add(tag.bytes);
            if (tag.timestamp > lastTimestamp) lastTimestamp = tag.timestamp;
            await _current?.cancel();
            _current = null;
            _prefetchTimer?.cancel();
          }
          continue;
        }
        out.add(tag.bytes);
        if (tag.timestamp > lastTimestamp) lastTimestamp = tag.timestamp;
      }
    } catch (e) {
      debugPrint('[douyu-relay] 新连接读取失败: $e');
    } finally {
      if (!done.isCompleted) done.complete();
    }
  }

  Future<_FlvTagStream?> _openNext() async {
    final refresher = config.refresh;
    if (refresher != null) {
      try {
        final urls = await refresher();
        final fresh = urls?.firstWhere((u) => u.isNotEmpty, orElse: () => '');
        if (fresh != null && fresh.isNotEmpty) {
          final stream = await _open(fresh);
          if (stream != null) return stream;
        }
      } catch (_) {}
    }
    for (final url in config.fallbackUrls) {
      if (url.isEmpty || url == config.sourceUrl) continue;
      final stream = await _open(url);
      if (stream != null) return stream;
    }
    return null;
  }

  Future<_FlvTagStream?> _open(String url) async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final request = await client.getUrl(Uri.parse(url));
      config.headers.forEach((key, value) => request.headers.set(key, value));
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final response = await request.close();
      if (response.statusCode >= 400) {
        client.close(force: true);
        return null;
      }
      return _FlvTagStream(client, response);
    } catch (_) {
      return null;
    }
  }
}

class _FlvTag {
  _FlvTag({required this.type, required this.timestamp, required this.keyFrame, required this.bytes});

  final int type;
  final int timestamp;
  final bool keyFrame;
  final Uint8List bytes;
}

/// 从上游流里切出完整 FLV tag（含 11 字节头 + data + 4 字节 PreviousTagSize）。
class _FlvTagStream {
  _FlvTagStream(this._client, this._response) {
    _iterator = StreamIterator<List<int>>(_response);
  }

  final HttpClient _client;
  final HttpClientResponse _response;
  late final StreamIterator<List<int>> _iterator;

  final List<int> _buffer = <int>[];
  int _offset = 0;
  bool _eof = false;

  Future<void> _fill() async {
    if (_eof) return;
    if (!await _iterator.moveNext()) {
      _eof = true;
      return;
    }
    _buffer.addAll(_iterator.current);
  }

  Future<Uint8List?> _take(int count) async {
    while (_buffer.length - _offset < count) {
      await _fill();
      if (_eof) return null;
    }
    final out = Uint8List.fromList(_buffer.sublist(_offset, _offset + count));
    _offset += count;
    if (_offset > 64 * 1024) {
      _buffer.removeRange(0, _offset);
      _offset = 0;
    }
    return out;
  }

  /// 读掉 FLV 文件头（9 字节）+ 首个 PreviousTagSize（4 字节），返回头本身。
  Future<Uint8List?> readFlvHeader() async {
    final head = await _take(9);
    if (head == null) return null;
    if (head[0] != 0x46 || head[1] != 0x4C || head[2] != 0x56) return null;
    final prev = await _take(4);
    if (prev == null) return null;
    return head;
  }

  /// 读下一个完整 tag；流结束返回 null。
  Future<_FlvTag?> next() async {
    final header = await _take(11);
    if (header == null) return null;
    final type = header[0] & 0x1F;
    final dataSize = (header[1] << 16) | (header[2] << 8) | header[3];
    final timestamp =
        (header[7] << 24) | (header[4] << 16) | (header[5] << 8) | header[6];
    final body = await _take(dataSize + 4);
    if (body == null) return null;

    var keyFrame = false;
    if (type == 9 && dataSize > 1) {
      // 首字节高 4 位 = FrameType（1=关键帧），第二字节低 4 位 = AVCPacketType（1=NALU）
      final frameType = (body[0] >> 4) & 0x0F;
      final avcPacketType = body[1] & 0x0F;
      keyFrame = frameType == 1 && avcPacketType == 1;
    }

    final bytes = Uint8List(11 + dataSize + 4)
      ..setRange(0, 11, header)
      ..setRange(11, 11 + dataSize + 4, body);
    return _FlvTag(type: type, timestamp: timestamp, keyFrame: keyFrame, bytes: bytes);
  }

  Future<void> cancel() async {
    try {
      await _iterator.cancel();
    } catch (_) {}
    try {
      _client.close(force: true);
    } catch (_) {}
  }
}
