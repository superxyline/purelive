import 'dart:async';
import 'dart:convert';

import 'package:pure_live/common/models/live_message.dart';
import 'package:pure_live/core/interface/live_danmaku.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Web 端弹幕客户端：连接 NAS 后端的统一弹幕 WebSocket
/// （/api/danmaku/{platform}/{roomId}），后端负责与各平台 wss 建连、
/// 认证、心跳与协议解析，这里只消费统一 JSON 消息。
class WebDanmaku extends LiveDanmaku {
  final String platform;
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reloadTimer;

  WebDanmaku(this.platform);

  @override
  Future start(dynamic args) async {
    // args: danmakuData（后端 getRoomDetail 透传的握手凭据，web 端仅用于平台透传）
    final roomId = args?.toString() ?? '';
    if (roomId.isEmpty) return;

    // Web 部署在 NAS 同源下直接用相对路径；独立调试时页面 URL 带 ?api=http://nas:port
    final base = _apiBase;
    final path = '/api/danmaku/$platform/$roomId';
    final uri = Uri.parse(base.isEmpty ? path : base + path);
    try {
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;
      markConnected();
      onReady?.call();
      _subscription = _channel!.stream.listen(
        _onData,
        onError: (_) => markDisconnected(),
        onDone: () {
          markDisconnected();
          onClose?.call('danmaku connection closed');
        },
      );
    } catch (e) {
      markDisconnected();
      onClose?.call(e.toString());
    }
  }

  /// Web API 基址：同源部署为空串；独立调试时页面 URL 带 ?api=http://nas:port。
  static String get _apiBase {
    final apiParam = Uri.base.queryParameters['api'];
    return (apiParam != null && apiParam.isNotEmpty) ? apiParam : '';
  }

  void _onData(dynamic raw) {
    try {
      final json = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = json['type'] as String? ?? '';
      switch (type) {
        case 'msg':
          onMessage?.call(
            LiveMessage(
              type: LiveMessageType.chat,
              userName: json['userName']?.toString() ?? '',
              userId: json['userId']?.toString() ?? '',
              message: json['message']?.toString() ?? '',
              color: LiveMessageColor.white,
            ),
          );
          break;
        case 'gift':
          onMessage?.call(
            LiveMessage(
              type: LiveMessageType.gift,
              userName: json['userName']?.toString() ?? '',
              message: json['giftName']?.toString() ?? '',
              data: {
                'giftName': json['giftName'],
                'giftCount': json['giftCount'] ?? 1,
                'giftPrice': json['giftPrice'] ?? 0,
                'totalCoin': json['totalCoin'] ?? 0,
                'face': json['face'] ?? '',
              },
              color: LiveMessageColor.white,
            ),
          );
          break;
        case 'online':
          onMessage?.call(
            LiveMessage(
              type: LiveMessageType.online,
              userName: '',
              message: (json['onlineCount'] ?? 0).toString(),
              data: json['onlineCount'] is int ? json['onlineCount'] : int.tryParse('${json['onlineCount']}') ?? 0,
              color: LiveMessageColor.white,
            ),
          );
          break;
        case 'sc':
          onMessage?.call(
            LiveMessage(
              type: LiveMessageType.superChat,
              userName: json['userName']?.toString() ?? '',
              message: json['message']?.toString() ?? '',
              data: {
                'face': json['face'] ?? '',
                'messageFontColor': json['giftColor'] ?? '',
                'price': json['giftPrice'] ?? 0,
              },
              color: LiveMessageColor.white,
            ),
          );
          break;
        case 'reload':
          // 后端要求重连（上游凭据刷新等）
          stop();
          _reloadTimer = Timer(const Duration(seconds: 1), () => start(json['roomId'] ?? ''));
          break;
      }
    } catch (_) {
      // 忽略无法解析的帧
    }
  }

  @override
  void heartbeat() {
    // 心跳由后端与平台之间维持，前端无需动作。
  }

  @override
  Future stop() async {
    _reloadTimer?.cancel();
    await _subscription?.cancel();
    await _channel?.sink.close();
    _channel = null;
    markDisconnected();
  }
}
