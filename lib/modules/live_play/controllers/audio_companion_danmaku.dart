import 'dart:async';

import 'package:pure_live/common/index.dart';
import 'package:pure_live/core/common/core_log.dart';
import 'package:pure_live/core/interface/live_danmaku.dart';
import 'package:pure_live/modules/live_play/controllers/live_play_controller.dart';

/// 副音轨房间的弹幕连接（独立于主弹幕会话 [DanmakuController]）。
///
/// 副音轨激活期间始终保活一路到副房间的弹幕 WebSocket，切换开关零延迟；
/// 是否上屏由 `showAudioCompanionDanmaku` 决定：
/// - 开：只显示副音轨房间弹幕（主房间聊天弹幕由 [DanmakuController] 屏蔽）；
/// - 关：主房间弹幕恢复，副房间消息静默丢弃（连接保持，不重复登录被限流）。
///
/// 只转发聊天弹幕：人数/SC/礼物等副房间事件不属于"看副音轨弹幕"的范畴，
/// 主房间的人数、SC 卡片、礼物卡片照常工作。
class AudioCompanionDanmaku {
  AudioCompanionDanmaku(this._main);

  final LivePlayController _main;
  LiveDanmaku? _engine;
  LiveRoom? _room;
  Worker? _toggleWorker;
  bool _showing = false;
  bool _connecting = false;

  /// 副音轨激活时接入副房间弹幕连接（幂等：同房间重复接入直接忽略）。
  void attach(LiveRoom detail) {
    final key = _roomKey(detail);
    if (_room != null && _roomKey(_room!) == key) return;
    unawaited(detach());
    _room = detail;
    _showing = SettingsService.to.danmaku.showAudioCompanionDanmaku.v;
    _toggleWorker?.dispose();
    _toggleWorker = ever(SettingsService.to.danmaku.showAudioCompanionDanmaku, _onToggleChanged);
    unawaited(_connect());
  }

  /// 释放连接与监听（关闭副音轨/退出直播间时调用）。
  Future<void> detach() async {
    _toggleWorker?.dispose();
    _toggleWorker = null;
    _room = null;
    _showing = false;
    final engine = _engine;
    _engine = null;
    if (engine == null) return;
    engine.onMessage = null;
    engine.onClose = null;
    engine.onReady = null;
    try {
      await engine.stop();
    } catch (error, stackTrace) {
      CoreLog.e('[AudioCompanionDanmaku] stop: $error', stackTrace);
    }
  }

  Future<void> _connect() async {
    final room = _room;
    if (room == null || room.platform == null || _connecting) return;
    _connecting = true;
    try {
      final engine = Sites.of(room.platform!).liveSite.getDanmaku();
      _engine = engine;
      _installCallbacks(engine);
      await engine.start(room.danmakuData);
    } catch (error, stackTrace) {
      CoreLog.e('[AudioCompanionDanmaku] start: $error', stackTrace);
    } finally {
      _connecting = false;
    }
  }

  void _installCallbacks(LiveDanmaku engine) {
    engine.onMessage = (msg) {
      if (_engine != engine || !_showing) return;
      if (msg.type != LiveMessageType.chat) return;
      _main.addDanmakuMessage(msg);
      _main.state.value.player.videoController?.sendDanmaku(msg);
    };
    // 副房间连接断开不上系统消息（避免和主房间状态混在一起），只记日志。
    engine.onClose = (msg) => debugPrint('[AudioCompanionDanmaku] onClose: $msg');
    engine.onReady = () => debugPrint('[AudioCompanionDanmaku] ready');
  }

  void _onToggleChanged(bool value) {
    if (_room == null) return;
    if (_showing == value) return;
    _showing = value;
    // 切换瞬间清掉画面上残留的另一路弹幕，视觉立即切换。
    _main.clearRenderedDanmaku();
    _main.addSystemMessage(
      value
          ? i18n('audio_companion_danmaku_on')
          : i18n('audio_companion_danmaku_off'),
    );
  }

  String _roomKey(LiveRoom room) => '${room.platform ?? ''}:${room.roomId ?? ''}';
}
