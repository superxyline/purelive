import 'dart:async';

import 'package:flutter/services.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/utils/live_url_tool.dart';
import 'package:pure_live/routes/app_navigation.dart';

/// 接收其他 App 分享进来的直播链接，直接打开对应直播间（对照上游 3.2.2）。
///
/// 原生侧 `MainActivity` 在 `ACTION_SEND` 到达时把文本存成 pending，并通过
/// `onShare` 推一次；冷启动时 Flutter 还没注册 handler，所以这里起来后再主动
/// `getPendingShare` 拉一次。两条路都走 [_accept]，用 [_lastText] 做短时间去重，
/// 避免同一条链接被打开两次。
class ShareIntentService extends GetxService {
  static const String _channelName = 'pure_live/share';

  static ShareIntentService? _instance;
  static ShareIntentService get instance => _instance!;

  MethodChannel? _channel;
  Timer? _navigationTimer;
  String? _pendingText;
  String? _lastText;
  DateTime? _lastHandledAt;
  bool _opening = false;

  @override
  void onInit() {
    super.onInit();
    _instance = this;
    _channel = const MethodChannel(_channelName);
    _channel?.setMethodCallHandler(_onNativeCall);
    unawaited(_pullPending());
  }

  @override
  void onClose() {
    _navigationTimer?.cancel();
    super.onClose();
  }

  Future<dynamic> _onNativeCall(MethodCall call) async {
    if (call.method == 'onShare' && call.arguments is String) {
      _accept(call.arguments as String);
    }
    return null;
  }

  /// 冷启动时通道未必立刻可用，稍作延迟重试几次。
  Future<void> _pullPending() async {
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        final pending = await _channel?.invokeMethod<String>('getPendingShare');
        if (pending != null && pending.isNotEmpty) _accept(pending);
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
  }

  void _accept(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _opening) return;
    final now = DateTime.now();
    final last = _lastHandledAt;
    // 同一条文本 5 秒内只处理一次：冷启动时"原生推一次 + 主动拉一次"会重复到达。
    if (_lastText == trimmed && last != null && now.difference(last) < const Duration(seconds: 5)) return;
    _pendingText = trimmed;
    _openWhenReady();
  }

  /// 冷启动时首页/路由可能尚未挂载，且启动页随后会 `offAllNamed(首页)`
  /// 把期间推入的路由冲掉，所以必须等启动页结束再导航。
  Future<void> _openWhenReady([int attempt = 0]) async {
    final text = _pendingText;
    if (text == null) return;
    final currentRoute = Get.currentRoute;
    if (currentRoute.isEmpty || currentRoute == RoutePath.kSplash) {
      if (attempt >= 20) {
        _pendingText = null;
        return;
      }
      _navigationTimer?.cancel();
      _navigationTimer = Timer(const Duration(milliseconds: 500), () => _openWhenReady(attempt + 1));
      return;
    }

    _pendingText = null;
    _opening = true;
    List<String> parsed;
    try {
      parsed = await LiveUrlTool.parseLiveUrl(text);
    } catch (_) {
      parsed = const <String>[];
    } finally {
      _opening = false;
    }

    if (parsed.length < 2 || parsed.first.isEmpty) {
      ToastUtil.show(i18n('share_link_parse_failed'));
      return;
    }

    _lastText = text;
    _lastHandledAt = DateTime.now();
    AppNavigator.toLiveRoomDetail(
      liveRoom: LiveRoom(
        roomId: parsed.first,
        platform: parsed[1],
        title: '',
        cover: '',
        nick: '',
        watching: '',
        avatar: '',
        area: '',
        liveStatus: LiveStatus.live,
        status: true,
        data: '',
        danmakuData: '',
      ),
    );
  }
}
