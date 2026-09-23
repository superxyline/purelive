import 'dart:async';
import 'dart:io' as io;

import 'package:web_socket_channel/io.dart';
import 'package:pure_live/core/common/proxy_routing.dart';
import 'package:pure_live/common/services/settings_service.dart';

enum SocketStatus { connected, failed, closed }

/// 弹幕 WebSocket 与 API 共用同一套应用代理设置（上游 3.1.0：补上 WS 的代理缺口）。
/// DIRECT 时返回 null 让 SDK 用默认 client——为纯 DIRECT 造自定义 HttpClient
/// 会让可达主机的 HTTP upgrade 挂到 connectTimeout。
String _wsProxyDirective(Uri uri) {
  try {
    final p = SettingsService.to.proxy;
    return buildProxyDirective(
      enabled: p.enableAppProxy.value,
      host: p.appProxyHost.value,
      port: p.appProxyPort.value,
    );
  } catch (_) {
    return 'DIRECT';
  }
}

io.HttpClient? _wsHttpClient(Uri endpoint) {
  if (_wsProxyDirective(endpoint) == 'DIRECT') return null;
  final client = io.HttpClient()..idleTimeout = const Duration(seconds: 30);
  client.findProxy = _wsProxyDirective;
  return client;
}

/// WebSocket connection helper with endpoint failover and bounded reconnects.
///
/// The original implementation kept a periodic reconnect timer alive after a
/// successful connection. That could create parallel sockets every five
/// seconds and made danmaku delivery increasingly expensive. This helper uses
/// one-shot retries and rotates through all supplied endpoints instead.
class WebScoketUtils {
  SocketStatus status = SocketStatus.closed;

  /// Primary endpoint. Kept for source compatibility with existing sites.
  final String url;

  /// Legacy secondary endpoint.
  final String? backupUrl;

  /// Ordered endpoints used for connection and failover.
  final List<String> serverUrls;

  final int heartBeatTime;
  final Function(dynamic)? onMessage;
  final Function(String msg)? onClose;
  final Function()? onReconnect;
  final Function()? onReady;
  final Function()? onHeartBeat;
  final Map<String, dynamic>? headers;
  final Iterable<String>? protocols;

  WebScoketUtils({
    required this.url,
    required this.heartBeatTime,
    this.onMessage,
    this.onClose,
    this.onReconnect,
    this.onReady,
    this.onHeartBeat,
    this.headers,
    this.backupUrl,
    this.protocols,
    List<String>? serverUrls,
  }) : serverUrls = _uniqueEndpoints(url, backupUrl, serverUrls);

  IOWebSocketChannel? webSocket;
  Timer? heartBeatTimer;
  Timer? reconnectTimer;
  StreamSubscription<dynamic>? streamSubscription;

  int reconnectTime = 0;
  int maxReconnectTime = 8;
  int _endpointIndex = 0;
  int _generation = 0;
  bool _manualClose = false;
  bool _connecting = false;

  static List<String> _uniqueEndpoints(String primary, String? backup, List<String>? candidates) {
    final endpoints = <String>[];
    for (final endpoint in <String>[primary, ?backup, ...?candidates]) {
      final value = endpoint.trim();
      if (value.isNotEmpty && !endpoints.contains(value)) endpoints.add(value);
    }
    return endpoints;
  }

  Future<void> connect({bool retry = false}) async {
    if (_connecting || serverUrls.isEmpty) return;
    _manualClose = false;
    _connecting = true;
    final generation = ++_generation;

    reconnectTimer?.cancel();
    reconnectTimer = null;
    await _disposeSocket();

    if (retry && serverUrls.length > 1) {
      _endpointIndex = (_endpointIndex + 1) % serverUrls.length;
    }

    try {
      final endpoint = serverUrls[_endpointIndex % serverUrls.length];
      final channel = IOWebSocketChannel.connect(
        endpoint,
        connectTimeout: const Duration(seconds: 10),
        protocols: protocols,
        headers: headers,
        customClient: _wsHttpClient(Uri.parse(endpoint)),
      );
      webSocket = channel;
      await channel.ready;
      if (_manualClose || generation != _generation) {
        await channel.sink.close();
        return;
      }
      _ready(channel, generation);
    } catch (error) {
      if (!_manualClose && generation == _generation) {
        _scheduleReconnect(error.toString());
      }
    } finally {
      // A manual close increments the generation while channel.ready is still
      // pending. Leaving this flag set in that path permanently blocks a later
      // connection attempt on the same helper.
      _connecting = false;
    }
  }

  void _ready(IOWebSocketChannel channel, int generation) {
    status = SocketStatus.connected;
    reconnectTimer?.cancel();
    reconnectTimer = null;

    streamSubscription = channel.stream.listen(
      (data) {
        if (!_manualClose && generation == _generation) receiveMessage(data);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!_manualClose && generation == _generation) _scheduleReconnect(error.toString());
      },
      onDone: () {
        if (!_manualClose && generation == _generation) _scheduleReconnect('WebSocket closed');
      },
      cancelOnError: true,
    );

    onReady?.call();
    _initHeartBeat();
  }

  void _initHeartBeat() {
    heartBeatTimer?.cancel();
    if (heartBeatTime <= 0) return;
    heartBeatTimer = Timer.periodic(Duration(milliseconds: heartBeatTime), (_) {
      if (status == SocketStatus.connected) onHeartBeat?.call();
    });
  }

  void receiveMessage(dynamic data) {
    reconnectTime = 0;
    onMessage?.call(data);
  }

  void _scheduleReconnect(String message) {
    if (_manualClose || reconnectTimer?.isActive == true) return;

    status = SocketStatus.failed;
    heartBeatTimer?.cancel();
    heartBeatTimer = null;
    if (reconnectTime == 0) onReconnect?.call();

    if (reconnectTime >= maxReconnectTime) {
      onClose?.call('重连超过最大次数，与服务器断开连接：$message');
      unawaited(close());
      return;
    }

    reconnectTime++;
    _endpointIndex = (_endpointIndex + 1) % serverUrls.length;
    // Try the next server quickly; use a short backoff after every full round.
    final completedRounds = reconnectTime ~/ serverUrls.length;
    final delaySeconds = completedRounds.clamp(0, 5) + 1;
    reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      reconnectTimer = null;
      connect();
    });
  }

  void sendMessage(dynamic message) {
    if (status == SocketStatus.connected) webSocket?.sink.add(message);
  }

  Future<void> _disposeSocket() async {
    await streamSubscription?.cancel();
    streamSubscription = null;
    heartBeatTimer?.cancel();
    heartBeatTimer = null;
    final socket = webSocket;
    webSocket = null;
    try {
      await socket?.sink.close();
    } catch (_) {}
  }

  Future<void> close() async {
    _manualClose = true;
    _generation++;
    status = SocketStatus.closed;
    reconnectTimer?.cancel();
    reconnectTimer = null;
    await _disposeSocket();
  }

  void reconnect() {
    if (!_manualClose) _scheduleReconnect('Reconnect requested');
  }
}
