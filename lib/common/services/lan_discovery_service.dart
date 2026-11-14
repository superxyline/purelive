import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:io';
import 'dart:math';

import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/utils/local_network_permission.dart';
import 'package:pure_live/get/get.dart';



/// 局域网设备发现与互推同步（手机 / 平板 / 电视三端）。
///
/// 协议：
/// - 每台设备周期性向 UDP 47478 端口广播宣告：设备名、类型、HTTP 端口、
///   一次性 token；同时监听同端口的广播，维护 [peers] 在线设备列表。
/// - 推送：向目标设备的 `POST http://<ip>:<httpPort>/lan/<token>/sync`
///   发送 exportTransferData 载荷（关注 + 登录态 + 设置）。
/// - 接收：HTTP 收到推送后**挂起请求、弹出确认对话框**，用户确认后才
///   落盘合并（并集），取消则回复 409。
class LanDiscoveryService extends GetxService {
  static LanDiscoveryService get to => Get.find<LanDiscoveryService>();

  /// UDP 宣告端口（三端固定，广播发往 255.255.255.255:udpPort）。
  static const int udpPort = 47478;

  static const String _magic = 'purelive-lan-v1';
  static const Duration _announceInterval = Duration(seconds: 3);
  static const Duration _peerTimeout = Duration(seconds: 10);

  RawDatagramSocket? _udp;
  HttpServer? _http;
  Timer? _announceTimer;
  Timer? _sweepTimer;
  Timer? _cleanupTimer;
  String _token = '';
  int _httpPort = 0;
  bool _starting = false;

  /// 局域网在线设备（按 lastSeen 刷新，超时剔除）。
  final peers = <LanPeer>[].obs;

  /// 接收推送的确认回调（UI 层注册）：返回 true=接受合并，false=拒绝。
  /// 用 Completer 挂起 HTTP 响应直到用户选择。
  Future<bool> Function(LanPushRequest request)? confirmHandler;

  String _deviceName = 'PureLive';
  String _deviceType = 'phone';
  String _subnetBroadcast = '';
  int _announceCount = 0;

  /// 取本机私有 IPv4 并推导子网定向广播地址（如 192.168.31.255）。
  /// 255.255.255.255 全局广播在部分 ROM 上直接 EPERM，定向广播可用。
  /// 双卡设备会同时有 Wi-Fi（192.168.x）与蜂窝（10.x）接口——蜂窝网段的
  /// 广播永远到不了局域网，必须优先选 wlan 接口，其次 192.168 段。
  Future<void> _resolveSubnet() async {
    if (_subnetBroadcast.isNotEmpty) return;
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
      String? best;
      var bestScore = -1;
      for (final itf in interfaces) {
        final nameLower = itf.name.toLowerCase();
        for (final addr in itf.addresses) {
          final octets = addr.address.split('.');
          if (octets.length != 4) continue;
          final isPrivate = octets[0] == '192' && octets[1] == '168' ||
              octets[0] == '10' ||
              (octets[0] == '172' && int.parse(octets[1]) >= 16 && int.parse(octets[1]) <= 31);
          if (!isPrivate) continue;
          // 评分：wlan 接口 4，192.168 段 2，其余 1——取最高分
          var score = 1;
          if (nameLower.contains('wlan')) score = 4;
          if (octets[0] == '192' && octets[1] == '168' && score < 2) score = 2;
          if (score > bestScore) {
            bestScore = score;
            best = addr.address;
          }
        }
      }
      if (best != null) {
        final parts = best.split('.');
        _subnetBroadcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
        debugPrint('lan discovery: subnet=$_subnetBroadcast (if=$best)');
      }
    } catch (_) {}
  }

  bool get isRunning => _http != null;

  Future<void> start({String? deviceName, String? deviceType}) async {
    if (isRunning || _starting) return;
    _starting = true;
    _deviceType = deviceType ?? _detectDeviceType();
    _deviceName = deviceName ?? 'PureLive ' + (_deviceType == 'tablet' ? '平板' : _deviceType == 'tv' ? '电视' : '手机');
    // Android 16+ 局域网访问运行时权限：未授予时系统静默拒绝所有局域网
    // 连接（UDP/TCP 出入站全拦，ping 等 shell 流程不受限），必须在启动前
    // 申请一次；已授予则立即通过，未授予弹系统授权框。
    try {
      await LocalNetworkPermission.ensure();
    } catch (_) {}
    await _resolveSubnet();
    try {
      _token = _randomToken();
      // 固定端口：TCP 扫描发现需要已知端口（UDP 在 Android 16/17 上被
      // 系统）对应用进程静默拦截，TCP 是唯一可靠通道）。被占用则递增。
      for (var p = 47479; p <= 47489; p++) {
        try {
          _http = await HttpServer.bind(InternetAddress.anyIPv4, p);
          _httpPort = p;
          break;
        } catch (_) {
          continue;
        }
      }
      _http ??= await HttpServer.bind(InternetAddress.anyIPv4, 0);
      if (_httpPort == 0) _httpPort = _http!.port;
      unawaited(_serveHttp());

      try {
        _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, udpPort, reuseAddress: true, reusePort: true);
      } catch (_) {
        // 部分 ROM/内核拒绝 SO_REUSEPORT，退普通 bind 重试
        debugPrint('lan discovery: reusePort rejected, retrying plain bind');
        _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, udpPort, reuseAddress: true);
      }
      _udp!.broadcastEnabled = true;
      _udp!.listen(
        (event) {
          if (event != RawSocketEvent.read) debugPrint('lan discovery: udp event $event');
          if (event == RawSocketEvent.read) {
            final datagram = _udp!.receive();
            if (datagram != null) _handleAnnounce(datagram);
          }
        },
        onError: (Object error) {
          debugPrint('lan discovery: udp error $error');
          // 错误（如广播 EPERM）会关闭 socket：清引用让下轮 announce 重建
          _udp = null;
        },
        onDone: () {
          debugPrint('lan discovery: udp socket DONE (closed)');
          _udp = null;
        },
      );

      _announceTimer = Timer.periodic(_announceInterval, (_) => unawaited(_announce()));
        await _resolveOwnIp();
      _sweepTimer = Timer.periodic(const Duration(seconds: 15), (_) => unawaited(_unicastSweep()));
      unawaited(_unicastSweep());
      _cleanupTimer = Timer.periodic(_peerTimeout, (_) => _cleanupPeers());
      unawaited(_announce());
      debugPrint('lan discovery: started (http=$_httpPort udp=$udpPort)');
    } catch (e) {
      debugPrint('lan discovery: start failed: $e');
      await stop();
    } finally {
      _starting = false;
    }
  }

  Future<void> stop() async {
    _announceTimer?.cancel();
    _sweepTimer?.cancel();
    _cleanupTimer?.cancel();
    _udp?.close();
    _udp = null;
    await _http?.close(force: true);
    _http = null;
    peers.clear();
  }

  Future<void> _announce() async {
    if (_udp == null) {
      // socket 被系统错误关闭后自动重建（MulticastLock 缺失/权限瞬时失败可自愈）
      try {
        _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, udpPort, reuseAddress: true);
        _udp!.broadcastEnabled = true;
        _udp!.listen(
          (event) {
            if (event == RawSocketEvent.read) {
              final datagram = _udp!.receive();
              if (datagram != null) _handleAnnounce(datagram);
            }
          },
          onError: (Object error) => debugPrint('lan discovery: udp error $error'),
          onDone: () => debugPrint('lan discovery: udp socket DONE (closed)'),
        );
        debugPrint('lan discovery: udp socket rebuilt');
      } catch (e) {
        debugPrint('lan discovery: udp rebuild failed: $e');
        return;
      }
    }
    try {
      final payload = jsonEncode({
        'magic': _magic,
        'name': _deviceName,
        'type': _deviceType,
        'httpPort': _httpPort,
        'token': _token,
      });
      final bytes = utf8.encode(payload);

      // 广播：子网定向优先（兼容性最好），全局广播兜底。低频（3 秒 1 包）。
      var sent = 0;
      if (_subnetBroadcast.isNotEmpty) {
        sent = _udp!.send(bytes, InternetAddress(_subnetBroadcast), udpPort);
      }
      if (sent == 0) {
        sent = _udp!.send(bytes, InternetAddress('255.255.255.255'), udpPort);
      }
      _announceCount++;
      debugPrint('lan discovery: round=$_announceCount bc=$sent');
    } catch (e) {
      debugPrint('lan discovery: announce failed: $e');
      _udp = null; // send 异常同样可能伴随 socket 关闭，下轮重建
    }
  }

  /// 子网单播扫描（每 10 秒一轮、每包间隔 15ms ≈ 66pps）：部分路由器对
  /// 高频 UDP 突发（254 包/3 秒）触发 Flood 防护整体丢弃（实测），摊平后
  /// 单包可正常到达；对方 socket 收到即加 peer（来源 IP 从 datagram 取）。
  Future<void> _unicastSweep() async {
    if (_subnetBroadcast.isEmpty) return;
    final prefix = _subnetBroadcast.substring(0, _subnetBroadcast.lastIndexOf('.'));
    // TCP 并发扫描（UDP 被 Android 16/17 应用层拦截、TCP 双向畅通已实测）：
    // 每批 32 个并发连接 GET /lan/announce，拿到对方宣告即加 peer。
    const batchSize = 32;
    const perConnectTimeout = Duration(milliseconds: 1500);
    var found = 0;
    for (var base = 1; base <= 254; base += batchSize) {
      final futures = <Future<void>>[];
      for (var i = base; i < base + batchSize && i <= 254; i++) {
        final ip = '$prefix.$i';
        if (ip == _ownIp) continue;
        futures.add(_probePeer(ip, perConnectTimeout).then((peer) {
          if (peer != null) {
            found++;
            _upsertPeer(peer);
          }
        }));
      }
      await Future.wait(futures);
    }
    debugPrint('lan discovery: tcp sweep done found=$found');
  }

  String? _ownIp;

  Future<void> _resolveOwnIp() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
      for (final itf in interfaces) {
        for (final addr in itf.addresses) {
          final octets = addr.address.split('.');
          if (octets.length != 4) continue;
          final isPrivate = octets[0] == '192' && octets[1] == '168' ||
              octets[0] == '10' ||
              (octets[0] == '172' && int.parse(octets[1]) >= 16 && int.parse(octets[1]) <= 31);
          if (isPrivate) {
            _ownIp = addr.address;
            return;
          }
        }
      }
    } catch (_) {}
  }

  /// 连接 [ip] 的发现端点；非本协议服务/超时返回 null。
  Future<LanPeer?> _probePeer(String ip, Duration timeout) async {
    Socket? socket;
    try {
      socket = await Socket.connect(ip, 47479, timeout: timeout);
      debugPrint('lan probe: connected $ip');
      const crlf = '\r\n';
      // 头行不能带前导空格（会被 server 当折行解析，格式异常直接断连）
      socket.write('GET /lan/announce HTTP/1.1${crlf}Host: $ip${crlf}Connection: close$crlf$crlf');
      final body = await socket
          .map((chunk) => utf8.decode(chunk, allowMalformed: true))
          .fold(StringBuffer(), (buf, chunk) => buf..write(chunk))
          .then((buf) => buf.toString())
          .timeout(timeout);
      debugPrint('lan probe: $ip body=${body.length}');
      final jsonStart = body.indexOf('{');
      if (jsonStart < 0) return null;
      final data = jsonDecode(body.substring(jsonStart));
      if (data is! Map || data['magic'] != _magic) return null;
      final token = data['token']?.toString() ?? '';
      final httpPort = (data['httpPort'] as num?)?.toInt() ?? 0;
      if (token.isEmpty || httpPort == 0) return null;
      return LanPeer(
        ip: ip,
        httpPort: httpPort,
        token: token,
        name: data['name']?.toString() ?? 'Unknown',
        type: data['type']?.toString() ?? 'phone',
        lastSeen: DateTime.now(),
      );
    } catch (e) {
      debugPrint('lan probe: $ip fail $e');
      return null;
    } finally {
      socket?.destroy();
    }
  }

  void _upsertPeer(LanPeer peer) {
    final idx = peers.indexWhere((p) => p.ip == peer.ip && p.httpPort == peer.httpPort);
    if (idx == -1) {
      peers.add(peer);
      debugPrint('lan discovery: peer found ${peer.name}(${peer.type}) ${peer.ip}:${peer.httpPort}');
    } else {
      peers[idx] = peer;
    }
  }

  void _handleAnnounce(Datagram datagram) {
    try {
      final data = jsonDecode(utf8.decode(datagram.data));
      if (data is! Map || data['magic'] != _magic) return;
      final ip = datagram.address.address;
      final token = data['token']?.toString() ?? '';
      final httpPort = (data['httpPort'] as num?)?.toInt() ?? 0;
      if (token.isEmpty || httpPort == 0) return;
      // 自己的宣告（同 token 同端口）忽略
      if (token == _token && httpPort == _httpPort) return;

      final peer = LanPeer(
        ip: ip,
        httpPort: httpPort,
        token: token,
        name: data['name']?.toString() ?? 'Unknown',
        type: data['type']?.toString() ?? 'phone',
        lastSeen: DateTime.now(),
      );
      final idx = peers.indexWhere((p) => p.ip == ip && p.httpPort == httpPort);
      if (idx == -1) {
        peers.add(peer);
        debugPrint('lan discovery: peer found ${peer.name}(${peer.type}) $ip:$httpPort');
      } else {
        peers[idx] = peer;
      }
    } catch (_) {
      // 非本协议的 UDP 包直接忽略
    }
  }

  void _cleanupPeers() {
    final now = DateTime.now();
    peers.removeWhere((p) => now.difference(p.lastSeen) > _peerTimeout);
  }

  Future<void> _serveHttp() async {
    try {
      await for (final request in _http!) {
        unawaited(_handlePush(request));
      }
    } catch (e) {
      debugPrint('lan discovery: http server stopped: $e');
    }
  }

  Future<void> _handlePush(HttpRequest request) async {
    final segments = request.uri.pathSegments;
    // 无 token 的发现握手：TCP 扫描方 GET /lan/announce，返回本机宣告
    if (segments.length == 2 && segments[0] == 'lan' && segments.last == 'announce') {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'magic': _magic,
        'name': _deviceName,
        'type': _deviceType,
        'httpPort': _httpPort,
        'token': _token,
      }));
      await request.response.close();
      return;
    }
    final ok = segments.length >= 3 && segments[0] == 'lan' && segments[1] == _token && segments.last == 'sync';
    if (!ok) {
      request.response.statusCode = 404;
      await request.response.close();
      return;
    }
    if (confirmHandler == null) {
      request.response.statusCode = 503;
      await request.response.close();
      return;
    }
    try {
      final body = await utf8.decoder.bind(request).join();
      final sender = request.connectionInfo?.remoteAddress.address ?? '';
      debugPrint('lan discovery: sync received from $sender body=${body.length}');
      final req = LanPushRequest(payload: body, senderIp: sender);
      final accepted = await confirmHandler!(req);
      debugPrint('lan discovery: sync accepted=$accepted from $sender');
      request.response.headers.contentType = ContentType.json;
      request.response.statusCode = accepted ? 200 : 409;
      request.response.write(jsonEncode({'data': accepted}));
      await request.response.close();
    } catch (e) {
      try {
        request.response.statusCode = 400;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'data': false, 'error': e.toString()}));
        await request.response.close();
      } catch (_) {}
    }
  }

  /// 把本地数据推送到 [peer]（关注 + 登录态 + 设置，载荷同扫码推送）。
  Future<bool> pushTo(LanPeer peer, Map<String, dynamic> payload) async {
    debugPrint('lan push: -> ${peer.ip}:${peer.httpPort} token=${peer.token} payloadLen=${jsonEncode(payload).length}');
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final req = await client.postUrl(Uri.parse('http://${peer.ip}:${peer.httpPort}/lan/${peer.token}/sync'));
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode(payload)));
      final resp = await req.close().timeout(const Duration(seconds: 60));
      final body = await resp.transform(utf8.decoder).join();
      debugPrint('lan push: <- ${peer.ip} status=${resp.statusCode} body=$body');
      final ok = resp.statusCode == 200 && (jsonDecode(body)['data'] ?? false);
      client.close();
      return ok;
    } catch (e) {
      debugPrint('lan push: -> ${peer.ip} failed: $e');
      client?.close();
      return false;
    }
  }

  /// 处理收到的同步载荷：关注列表并集合并 + 登录态导入（与扫码同步同一语义）。
  /// 返回 (是否合并成功, 新增关注数)。
  static (bool, int) mergeTransferPayload(Map<String, dynamic> data) {
    try {
      final fav = SettingsService.to.fav;
      final current = fav.favoriteRooms.v;
      final existing = current.map((r) => r.identityKey).toSet();
      final merged = List<LiveRoom>.from(current);
      var added = 0;

      List<dynamic> roomsJson = const [];
      final roomsField = data['favoriteRooms'];
      if (roomsField is Map && roomsField['list'] is List) roomsJson = roomsField['list'] as List;
      if (roomsField is List) roomsJson = roomsField;
      final legacy = data['favorite'];
      if (roomsJson.isEmpty && legacy is Map) {
        final legacyRooms = legacy['favoriteRooms'];
        if (legacyRooms is List) roomsJson = legacyRooms;
        if (legacyRooms is Map && legacyRooms['list'] is List) roomsJson = legacyRooms['list'] as List;
      }

      for (final item in roomsJson) {
        if (item is! Map) continue;
        try {
          final room = LiveRoom.fromJson(Map<String, dynamic>.from(item));
          if ((room.platform?.isEmpty ?? true) || (room.roomId?.isEmpty ?? true)) continue;
          if (existing.contains(room.identityKey)) continue;
          existing.add(room.identityKey);
          merged.add(room);
          added++;
        } catch (_) {}
      }
      if (added > 0) fav.favoriteRooms.v = merged;

      try {
        final cookie = data['cookie'];
        if (cookie is Map && cookie.isNotEmpty) {
          SettingsService.to.cookieManager.fromJson(Map<String, dynamic>.from(cookie));
        }
      } catch (_) {}

      return (true, added);
    } catch (e) {
      debugPrint('lan discovery: merge payload failed: $e');
      return (false, 0);
    }
  }

  /// 设备类型自检：短边 ≥600dp 视为平板，TV 由调用方传 'tv'，桌面 'desktop'。
  static String _detectDeviceType() {
    try {
      final view = ui.PlatformDispatcher.instance.views.first;
      final shortSide = view.physicalSize.shortestSide / view.devicePixelRatio;
      return shortSide >= 600 ? 'tablet' : 'phone';
    } catch (_) {
      return 'phone';
    }
  }

  String _randomToken() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List.generate(12, (_) => chars[random.nextInt(chars.length)]).join();
  }
}

/// 局域网发现的一台设备。
class LanPeer {
  LanPeer({
    required this.ip,
    required this.httpPort,
    required this.token,
    required this.name,
    required this.type,
    required this.lastSeen,
  });

  final String ip;
  final int httpPort;
  final String token;
  final String name;
  final String type;
  DateTime lastSeen;
}

/// 收到的推送请求（确认对话框展示用）。
class LanPushRequest {
  LanPushRequest({required this.payload, required this.senderIp});

  final String payload;
  final String senderIp;

  /// 关注数量（解析失败返回 -1）。
  int get favoriteCount {
    try {
      final data = jsonDecode(payload);
      if (data is! Map) return -1;
      final fav = data['favoriteRooms'];
      if (fav is Map && fav['list'] is List) return (fav['list'] as List).length;
      if (fav is List) return fav.length;
      final legacy = data['favorite'];
      if (legacy is Map && legacy['favoriteRooms'] is List) return (legacy['favoriteRooms'] as List).length;
      return -1;
    } catch (_) {
      return -1;
    }
  }
}
