import 'dart:async';

import 'package:pure_live/common/index.dart';
import 'package:pure_live/core/common/core_log.dart';
import 'package:pure_live/core/interface/live_danmaku.dart';
import 'package:pure_live/modules/live_play/controllers/danmaku_message_gate.dart';
import 'package:pure_live/modules/live_play/controllers/live_play_controller.dart';
import 'package:pure_live/modules/live_play/states/live_play_state.dart';

/// Owns exactly one room-bound danmaku session.
///
/// Room switches, setting changes, player reloads and floating-window teardown
/// can arrive in the same event-loop turn. Every transition is serialized and
/// every callback carries a session token, so an old socket can never append a
/// packet to the newly opened room.
class DanmakuController extends GetxController {
  DanmakuController(this._main);

  final LivePlayController _main;
  final DanmakuMessageGate _messageGate = DanmakuMessageGate();

  LiveDanmaku? _liveDanmaku;
  Future<void> _operationTail = Future<void>.value();
  Worker? _settingsWorker;
  Worker? _filterWorker;

  int _requestEpoch = 0;
  int _sessionToken = 0;
  String? _sessionKey;
  String? _connectingKey;
  String? _gateRoomKey;
  String? _lastStatusText;
  DateTime? _lastStatusAt;
  bool _maskedNameNoticeShown = false;
  Set<String> _blockedUsers = const <String>{};
  List<String> _blockedKeywords = const <String>[];
  List<RegExp> _blockedRegexps = const <RegExp>[];
  List<String> _blockedWildcards = const <String>[];

  /// 双开主副切换时挂起的存活连接（roomKey → 引擎）。
  /// 只摘回调不关 socket，心跳继续，切回时直接复用——
  /// 斗鱼等平台对同一房间几秒内的二次登录会静默限流
  /// （连接成功但永不下发消息），销毁重建会让切换后弹幕消失。
  final Map<String, LiveDanmaku> _idleEngines = {};

  LivePlayState get _state => _main.state.value;
  bool get _initialized => _liveDanmaku != null;
  LiveDanmaku get liveDanmaku => _liveDanmaku!;

  @override
  void onInit() {
    super.onInit();
    final settings = SettingsService.to;
    _settingsWorker = everAll([
      settings.danmaku.enableDanmakuDisplay,
      settings.danmaku.enablePipDanmaku,
    ], (_) => unawaited(_syncConnectionForSettings()));
    _filterWorker = everAll([settings.fav.blockedDanmakuUsers, settings.fav.shieldList], (_) => _refreshFilters());
    _refreshFilters();
  }

  /// Initial engine installation is synchronous so room initialization cannot
  /// race ahead of dependency setup.
  void initDanmaku(LiveDanmaku danmaku) {
    if (_liveDanmaku == null) {
      _liveDanmaku = danmaku;
      return;
    }
    unawaited(replaceDanmaku(danmaku));
  }

  Future<void> replaceDanmaku(LiveDanmaku danmaku) {
    final request = ++_requestEpoch;
    return _serialize(() async {
      if (request != _requestEpoch) return;
      await _disconnectInternal(clearRenderer: true);
      if (request != _requestEpoch) return;
      _liveDanmaku = danmaku;
      _messageGate.clear();
      _gateRoomKey = null;
    });
  }

  bool needReconnect(LiveRoom room) {
    if (!_initialized) return true;
    final key = _roomKey(room);
    return _sessionKey != key && _connectingKey != key;
  }

  Future<void> connectRoom(LiveRoom room) {
    final request = ++_requestEpoch;
    final key = _roomKey(room);
    return _serialize(() async {
      if (request != _requestEpoch || !_initialized) return;
      if (_sessionKey == key || _connectingKey == key) return;

      final previousKey = _sessionKey ?? _connectingKey;
      await _disconnectInternal(clearRenderer: previousKey != null && previousKey != key);
      if (request != _requestEpoch || !_initialized) return;

      if (_gateRoomKey != key) {
        _messageGate.clear();
        _gateRoomKey = key;
      }

      final engine = liveDanmaku;
      final token = ++_sessionToken;
      _maskedNameNoticeShown = false;
      _connectingKey = key;
      _installCallbacks(engine, room, key, token);

      if (room.isRecord == true) _addStatusMessage(i18n('recording_mode_notice'));
      _addStatusMessage(i18n('connect_danmaku_server'));

      try {
        await engine.start(room.danmakuData);
      } catch (error, stackTrace) {
        CoreLog.e(error.toString(), stackTrace);
        if (_acceptsCallback(engine, key, token)) {
          _connectingKey = null;
          _sessionKey = null;
          _main.updateDanmakuRoomId(null);
        }
      }

      if (request != _requestEpoch || !_acceptsCallback(engine, key, token)) {
        _detachCallbacks(engine);
        await engine.stop();
      }
    });
  }

  Future<void> stopDanmaku({bool clearRenderer = true}) {
    final request = ++_requestEpoch;
    return _serialize(() async {
      if (request != _requestEpoch) return;
      await _disconnectInternal(clearRenderer: clearRenderer);
      // 真正停止时清空挂起缓存，避免泄漏空闲连接。
      for (final engine in _idleEngines.values) {
        try {
          await engine.stop();
        } catch (error, stackTrace) {
          CoreLog.e(error.toString(), stackTrace);
        }
      }
      _idleEngines.clear();
    });
  }

  /// 主副切换/换房专用：挂起当前连接（保活），优先复用目标房间的缓存连接，
  /// 未命中才新建。避免同房间快速重连被平台静默限流。
  Future<void> switchRoomDanmaku(LiveRoom room) async {
    final request = ++_requestEpoch;
    final key = _roomKey(room);
    await _serialize(() async {
      if (request != _requestEpoch) return;

      // 1. 挂起当前连接：只摘回调，socket 与心跳保持存活。
      final current = _liveDanmaku;
      final currentKey = _sessionKey ?? _connectingKey;
      if (current != null && currentKey != null && currentKey != key) {
        _detachCallbacks(current);
        _idleEngines[currentKey] = current;
        _sessionKey = null;
        _connectingKey = null;
        _main.updateDanmakuRoomId(null);
      }
      if (request != _requestEpoch) return;

      if (_gateRoomKey != key) {
        _messageGate.clear();
        _gateRoomKey = key;
      }

      // 2. 命中缓存：直接复用存活连接，重挂回调即可。
      final cached = _idleEngines.remove(key);
      if (cached != null) {
        _liveDanmaku = cached;
        final token = ++_sessionToken;
        _installCallbacks(cached, room, key, token);
        _connectingKey = null;
        _sessionKey = key;
        _main.updateDanmakuRoomId(room.roomId?.toString());
        return;
      }

      // 3. 未命中：新建引擎连接。
      final engine = Sites.of(room.platform!).liveSite.getDanmaku();
      _liveDanmaku = engine;
      final token = ++_sessionToken;
      _maskedNameNoticeShown = false;
      _installCallbacks(engine, room, key, token);
      _addStatusMessage(i18n('connect_danmaku_server'));
      try {
        await engine.start(room.danmakuData);
      } catch (error, stackTrace) {
        CoreLog.e(error.toString(), stackTrace);
        if (_acceptsCallback(engine, key, token)) {
          _connectingKey = null;
          _sessionKey = null;
          _main.updateDanmakuRoomId(null);
        }
      }

      if (request != _requestEpoch || !_acceptsCallback(engine, key, token)) {
        _detachCallbacks(engine);
        await engine.stop();
      }

      // 4. 淘汰多余的挂起连接（保留最近 2 个：主房间 + 副房间）。
      while (_idleEngines.length > 2) {
        final oldestKey = _idleEngines.keys.first;
        final evicted = _idleEngines.remove(oldestKey);
        try {
          await evicted?.stop();
        } catch (error, stackTrace) {
          CoreLog.e(error.toString(), stackTrace);
        }
      }
    });
  }

  void _installCallbacks(LiveDanmaku engine, LiveRoom room, String key, int token) {
    engine.onMessage = (msg) {
      if (!_acceptsCallback(engine, key, token)) return;
      debugPrint('DBG onMessage type=${msg.type} user=${msg.userName} msg=${msg.message}');
      if (msg.type == LiveMessageType.chat) {
        if (!_messageGate.accepts(msg) || _isBlocked(msg)) return;
        // B站服务器会把自己发送的弹幕回显回来：按 uid 标记 isLocal，
        // 视频画面加框突出（发送端不再本地合成，避免重复显示）
        if (room.platform == Sites.bilibiliSite && _main.isOwnBilibiliMessage(msg.userId)) {
          msg = _main.rebuildMessageAsLocal(msg);
        }
        if (!_maskedNameNoticeShown &&
            room.platform == Sites.bilibiliSite &&
            RegExp(r'\*{2,}|＊{2,}').hasMatch(msg.userName)) {
          _maskedNameNoticeShown = true;
          _addStatusMessage(i18n('bilibili_guest_name_masked'));
        }
        _main.addDanmakuMessage(msg);
        _state.player.videoController?.sendDanmaku(msg);
      } else if (msg.type == LiveMessageType.online) {
        _main.updateRuntimeAudience(msg.data);
      } else if (msg.type == LiveMessageType.superChat) {
        final sc = msg.data;
        if (sc is LiveSuperChatMessage) _main.handleSuperChatMessage(sc);
      } else if (msg.type == LiveMessageType.gift) {
        // 礼物消息：添加到弹幕列表 + 全屏时显示礼物卡片（如果开关打开）
        _main.addDanmakuMessage(msg);
        _main.handleGiftCard(msg);
        // 观看统计：礼物数量/价值累计（不受礼物卡片显示开关影响）
        WatchStatsService.instance.recordGift(msg);
      }
    };

    engine.onClose = (msg) {
      if (!_acceptsCallback(engine, key, token)) return;
      _addStatusMessage(msg);
      // Transient reconnect notices retain ownership of this session. A final
      // failure releases the room key so a manual refresh creates a fresh
      // transport instead of remaining attached to a dead socket.
      if (!msg.contains('正在尝试重连')) {
        _sessionKey = null;
        _connectingKey = null;
        _main.updateDanmakuRoomId(null);
      }
    };

    engine.onReady = () {
      if (!_acceptsCallback(engine, key, token)) return;
      _connectingKey = null;
      _sessionKey = key;
      _main.updateDanmakuRoomId(room.roomId?.toString());
      _addStatusMessage(i18n('danmaku_connected'));
    };
  }

  bool _acceptsCallback(LiveDanmaku engine, String key, int token) {
    return token == _sessionToken && identical(_liveDanmaku, engine) && (_sessionKey == key || _connectingKey == key);
  }

  bool _isBlocked(LiveMessage message) {
    final user = message.userName.trim().toLowerCase();
    if (user.isNotEmpty && _blockedUsers.contains(user)) return true;
    final text = message.message.toLowerCase();

    // 普通关键词：字符串包含匹配
    if (_blockedKeywords.any(text.contains)) return true;

    // 正则表达式匹配
    if (_blockedRegexps.any((re) => re.hasMatch(message.message))) return true;

    // 通配符匹配（* 匹配任意字符，? 匹配单个字符）
    for (final pattern in _blockedWildcards) {
      if (_matchWildcard(text, pattern)) return true;
    }

    return false;
  }

  /// 通配符匹配：* 匹配任意字符序列，? 匹配单个字符
  bool _matchWildcard(String text, String pattern) {
    // 将通配符模式转换为正则表达式
    final regexStr = pattern
        .replaceAll(RegExp(r'([.+^${}()|[\]\\])'), r'\\$1') // 转义正则特殊字符
        .replaceAll('*', '.*')
        .replaceAll('?', '.');
    return RegExp('^$regexStr\$', caseSensitive: false).hasMatch(text);
  }

  void _refreshFilters() {
    final favorite = SettingsService.to.fav;
    _blockedUsers = favorite.blockedDanmakuUsers
        .map((user) => user.trim().toLowerCase())
        .where((user) => user.isNotEmpty)
        .toSet();

    final plainKeywords = <String>[];
    final regexps = <RegExp>[];
    final wildcards = <String>[];

    for (final raw in favorite.shieldList) {
      final keyword = raw.trim();
      if (keyword.isEmpty) continue;

      // 正则表达式：以 / 开头和结尾，如 /模式/flags
      if (keyword.length >= 2 && keyword.startsWith('/') && keyword.endsWith('/')) {
        try {
          final pattern = keyword.substring(1, keyword.length - 1);
          regexps.add(RegExp(pattern, caseSensitive: false));
        } catch (_) {
          // 无效正则，降级为普通关键词
          plainKeywords.add(keyword.toLowerCase());
        }
      }
      // 通配符：包含 * 或 ?
      else if (keyword.contains('*') || keyword.contains('?')) {
        wildcards.add(keyword.toLowerCase());
      }
      // 普通关键词
      else {
        plainKeywords.add(keyword.toLowerCase());
      }
    }

    _blockedKeywords = plainKeywords;
    _blockedRegexps = regexps;
    _blockedWildcards = wildcards;
  }

  void _addStatusMessage(String text) {
    final now = DateTime.now();
    if (_lastStatusText == text &&
        _lastStatusAt != null &&
        now.difference(_lastStatusAt!) < const Duration(seconds: 3)) {
      return;
    }
    _lastStatusText = text;
    _lastStatusAt = now;
    _main.addSystemMessage(text);
  }

  Future<void> _disconnectInternal({required bool clearRenderer}) async {
    final engine = _liveDanmaku;
    _sessionToken++;
    _sessionKey = null;
    _connectingKey = null;
    _main.updateDanmakuRoomId(null);
    if (clearRenderer) _main.clearRenderedDanmaku();
    if (engine == null) return;
    _detachCallbacks(engine);
    try {
      await engine.stop();
    } catch (error, stackTrace) {
      CoreLog.e(error.toString(), stackTrace);
    }
  }

  void _detachCallbacks(LiveDanmaku engine) {
    engine.onMessage = null;
    engine.onClose = null;
    engine.onReady = null;
  }

  Future<void> _syncConnectionForSettings() async {
    if (!_initialized) return;
    final room = _state.room.detail;
    if (room == null) return;
    final settings = SettingsService.to.danmaku;
    try {
      if (!settings.enableDanmakuDisplay.v && !settings.enablePipDanmaku.v) {
        await stopDanmaku();
      } else {
        await connectRoom(room);
      }
    } catch (error, stackTrace) {
      CoreLog.e(error.toString(), stackTrace);
    }
  }

  String _roomKey(LiveRoom room) => '${room.platform ?? ''}:${room.roomId ?? ''}';

  Future<void> _serialize(Future<void> Function() operation) {
    final next = _operationTail.then((_) => operation());
    _operationTail = next.catchError((Object error, StackTrace stackTrace) {
      CoreLog.e(error.toString(), stackTrace);
    });
    return next;
  }

  @override
  void onClose() {
    _settingsWorker?.dispose();
    _filterWorker?.dispose();
    _requestEpoch++;
    _sessionToken++;
    final engine = _liveDanmaku;
    if (engine != null) {
      _detachCallbacks(engine);
      unawaited(engine.stop());
    }
    _main.updateDanmakuRoomId(null);
    _main.clearRenderedDanmaku();
    super.onClose();
  }
}
