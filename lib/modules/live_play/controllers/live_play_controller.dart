import 'dart:io';
import 'dart:async';
import 'dart:developer' as developer;

import 'package:pure_live/common/index.dart';
import 'package:flutter/services.dart';
import 'package:pure_live/common/global/platform/mobile_manager.dart';
import 'package:pure_live/common/global/platform_utils.dart';
import 'package:pure_live/plugins/event_bus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:pure_live/plugins/emoji_manager.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/core/danmaku/huya_danmaku.dart';
import 'package:pure_live/core/danmaku/douyin_danmaku.dart';
import 'package:pure_live/player/core/live_audio_service.dart';
import 'package:pure_live/player/core/secondary_player_service.dart';
import 'package:pure_live/modules/live_play/states/ui_state.dart';
import 'package:pure_live/modules/live_play/states/load_type.dart';
import 'package:pure_live/modules/live_play/states/room_state.dart';
import 'package:pure_live/modules/live_play/states/player_state.dart';
import 'package:pure_live/modules/live_play/states/live_play_state.dart';
import 'package:pure_live/modules/live_play/controllers/player_state.dart';
import 'package:pure_live/modules/live_play/widgets/danmaku_list_view.dart';
import 'package:pure_live/modules/live_play/local_interaction_controller.dart';
import 'package:pure_live/modules/live_play/local_message_delivery_queue.dart';
import 'package:pure_live/modules/live_play/controllers/timer_controller.dart';
import 'package:pure_live/modules/live_play/controllers/player_controller.dart';
import 'package:pure_live/modules/live_play/controllers/danmaku_controller.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller.dart';
import 'package:pure_live/player/utils/fullscreen.dart';

// live_play_controller.dart

class LivePlayController extends GetxController with GetSingleTickerProviderStateMixin {
  LivePlayController({required this.room, required this.site});

  final String site;
  final LiveRoom room;

  late final TimerController timerController;
  late final DanmakuController danmakuController;
  late final PlayerController playerController;

  final LocalInteractionController localInteractionController = Get.find<LocalInteractionController>();

  final Rx<LivePlayState> state = const LivePlayState().obs;
  final RxList<LiveMessage> danmakuMessages = <LiveMessage>[].obs;
  final Rxn<LiveMessage> localGiftEffect = Rxn<LiveMessage>();

  /// 醒目留言(SC)全屏弹出状态。UI 监听它做全屏左下角卡片展示，
  /// 非空时显示，null 时隐藏。参见 [showFullscreenSC] / [hideFullscreenSC]。
  final Rxn<LiveSuperChatMessage> fsSC = Rxn<LiveSuperChatMessage>();
  Timer? _fsSCTimer;

  late Site currentSite;
  late TabController tabController;

  final List<String> tabs = [i18n('danmaku_list'), i18n('danmaku_settings'), i18n('block_list')];

  bool _floatingResourcesReleased = false;
  bool _ownerClosed = false;
  bool _childControllersReleased = false;
  bool _reactiveStateClosed = false;
  int _roomLoadEpoch = 0;
  bool _asmrSessionActive = false;
  Timer? _localGiftEffectTimer;
  Timer? _danmakuFlushTimer;
  final List<LiveMessage> _pendingDanmakuMessages = <LiveMessage>[];
  late final LocalMessageDeliveryQueue _localMessageDeliveryQueue;
  late final String _controllerTag;

  /// 滑动返回在部分设备上会连报两次返回事件：第一次用于退出全屏，
  /// 第二次若未拦截会直接把直播间退出。记录上次退出全屏的时间，
  /// 短暂窗口内再次收到返回一律吞掉。
  static const Duration _fullscreenExitGrace = Duration(milliseconds: 600);
  DateTime? _lastFullscreenExitAt;

  static const int _maxDanmakuHistory = 500;
  static const int _maxPendingDanmakuBatch = 200;
  static const Duration _danmakuBatchWindow = Duration(milliseconds: 32);
  static const Duration localChatDeliveryDelay = Duration(seconds: 2);

  @override
  void onInit() {
    super.onInit();
    _controllerTag = '${identityHashCode(this)}';
    currentSite = Sites.of(site);
    _localMessageDeliveryQueue = LocalMessageDeliveryQueue(onDeliver: _deliverLocalMessage);

    final autoStartAsmr = Platform.isAndroid && SettingsService.to.app.enableAsmrSleepMode.v;
    _asmrSessionActive = autoStartAsmr;
    state.value = LivePlayState(
      room: RoomState(detail: room),
      // 纯音频：全局"纯音频模式"开关或 ASMR 自动开启时进入直播间即关闭画面仅播放声音；
      // 直播间内耳机按钮可单独切换当前房间，不影响全局开关。
      player: PlayerState(isCurrentRoomAudioOnly: autoStartAsmr || SettingsService.to.player.audioOnly.v),
      ui: UIState(closeTimes: 60, closeTimeFlag: false),
    );
    unawaited(
      LiveAudioService.configureSleepTimer(enabled: autoStartAsmr, minutes: SettingsService.to.app.asmrSleepMinutes.v),
    );

    _initControllers();
    _initTab();
    _updateWakelock();
    Future.microtask(_initCore);
  }

  void _updateWakelock() {
    final shouldKeepOn = SettingsService.to.app.enableScreenKeepOn.v;
    WakelockPlus.enabled.then((isEnabled) {
      if (isEnabled != shouldKeepOn) {
        WakelockPlus.toggle(enable: shouldKeepOn);
      }
    });
  }

  void _initControllers() {
    timerController = Get.put(TimerController(onEnded: _onRoomPlaybackTimerEnded), tag: 'timer-$_controllerTag');
    danmakuController = Get.put(DanmakuController(this), tag: 'danmaku-$_controllerTag');
    playerController = Get.put(PlayerController(this), tag: 'player-$_controllerTag');

    playerController.initSite(currentSite);

    danmakuController.initDanmaku(currentSite.liveSite.getDanmaku());
  }

  void _initTab() {
    tabController = TabController(length: tabs.length, vsync: this);
  }

  Future<void> _initCore() async {
    await _preloadEmoji();
    await onInitPlayerState();
  }

  Future<void> _preloadEmoji() async {
    emojiCache.clear();
    await EmojiManager().preload(site);
  }

  /// 当前是否处于全屏/半屏展示（供 PopScope 兜底判断；
  /// 被绕过 canPop 直接弹出时据此恢复直播间而不是停在首页）。
  bool get isFullscreenActive =>
      GlobalPlayerState.to.isFullscreen.value ||
      GlobalPlayerState.to.isWindowFullscreen.value ||
      state.value.ui.screenMode != VideoMode.normal;

  /// 返回键处理：返回 true 表示事件已消费，false 表示允许页面正常退出。
  /// 返回键优先级最高：先收起输入焦点，再依次处理菜单/全屏/半屏/PiP，最后才退出页面。
  bool handleBackPress() {
    // 先收起输入焦点，避免输入框或键盘拦截返回键。
    if (FocusManager.instance.primaryFocus?.hasFocus ?? false) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    if (state.value.ui.isMenuOpen) {
      Navigator.of(Get.context!).pop();
      updateUI(isMenuOpen: false);
      return true;
    }
    // 双重检测：Rx标志与UI实际模式任一为全屏，都先恢复全屏前的状态，
    // 避免状态不同步导致返回键直接退出直播间。
    final isFullscreenUi =
        GlobalPlayerState.to.isFullscreen.value || state.value.ui.screenMode == VideoMode.fullscreen;
    if (isFullscreenUi) {
      GlobalPlayerState.to.isFullscreen.value = false;
      setNormalScreen();
      state.value.player.videoController?.exitFullScreen();
      // 直接兜底恢复方向与系统栏，不依赖 videoController 是否已初始化。
      unawaited(_restoreMobileScreenUi());
      // 记录退出时刻，用于拦截滑动返回连发的第二次返回事件。
      _lastFullscreenExitAt = DateTime.now();
      return true;
    }
    if (GlobalPlayerState.to.isWindowFullscreen.value) {
      setNormalScreen();
      GlobalPlayerState.to.isWindowFullscreen.value = false;
      state.value.player.videoController?.enableController();
      _lastFullscreenExitAt = DateTime.now();
      return true;
    }
    if (GlobalPlayerState.to.isPipMode.value) {
      GlobalPlayerService.instance.playerManager.exitPip();
      return true;
    }
    // 全屏/半屏刚退出后的短暂窗口内再收到返回（滑动返回通常连发两次事件），
    // 直接吞掉，避免第二次返回把直播间整个退出。
    final lastExitAt = _lastFullscreenExitAt;
    if (lastExitAt != null && DateTime.now().difference(lastExitAt) < _fullscreenExitGrace) {
      return true;
    }
    return false;
  }

  /// 按钮路径退出全屏后同样纳入连发保护窗口：
  /// 否则点按钮退全屏后紧跟的滑动返回会因已非全屏而直接退出直播间。
  void markFullscreenExit() => _lastFullscreenExitAt = DateTime.now();

  /// 页面被系统原生返回弹出后的兜底清理（与返回键处理幂等，重复调用无副作用）。
  void onPagePopCleanup() {    state.value.player.videoController?.clearListener();
    // 注意：这里不要再改 state（如 updateRoom）——页面仍在退出动画中，它的 Obx 会因此
    // 重建，而此时 GetX 可能已注销本控制器，触发 "LivePlayController not found" 灰屏。
    // 房间信息刷新由 BackButtonObserver 兜底。
    // 兜底复位全局全屏标志，避免绕过返回键处理直接弹出页面时全屏状态残留
    // 到下一个直播间或首页。
    GlobalPlayerState.to.isFullscreen.value = false;
    GlobalPlayerState.to.isWindowFullscreen.value = false;
    // 无论以何种路径离开直播间，都兜底恢复手机竖屏与系统栏，
    // 防止横屏沉浸状态泄漏到首页（表现为横屏平板样式列表）。
    unawaited(_restoreMobileScreenUi());
  }

  /// 恢复移动端竖屏与系统栏（仅移动端生效，幂等可重复调用）。
  Future<void> _restoreMobileScreenUi() async {
    try {
      if (PlatformUtils.isDesktop) return;
      await WindowService().verticalScreen();
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      MobileManager.setStatusBarStyle(isDarkTheme: Get.isDarkMode);
    } catch (_) {
      // 恢复失败不应影响页面退出流程。
    }
  }

  void updateRoom({LiveRoom? detail, bool? isLiving, bool? success, bool? isLoading, String? loadError}) {
    state.value = state.value.copyWith(
      room: state.value.room.copyWith(
        detail: detail,
        isLiving: isLiving,
        success: success,
        isLoading: isLoading,
        loadError: loadError,
      ),
    );
  }

  void updatePlayer({
    VideoController? videoController,
    List<LivePlayQuality>? qualites,
    int? currentQuality,
    List<String>? playUrls,
    int? currentLineIndex,
    bool? isCurrentRoomAudioOnly,
    bool? hasUseDefaultResolution,
  }) {
    state.value = state.value.copyWith(
      player: state.value.player.copyWith(
        videoController: videoController,
        qualites: qualites,
        currentQuality: currentQuality,
        playUrls: playUrls,
        currentLineIndex: currentLineIndex,
        isCurrentRoomAudioOnly: isCurrentRoomAudioOnly,
        hasUseDefaultResolution: hasUseDefaultResolution,
      ),
    );
  }

  void updateUI({VideoMode? screenMode, int? refreshKey, bool? isMenuOpen, int? closeTimes, bool? closeTimeFlag}) {
    state.value = state.value.copyWith(
      ui: state.value.ui.copyWith(
        screenMode: screenMode,
        refreshKey: refreshKey,
        isMenuOpen: isMenuOpen,
        closeTimes: closeTimes,
        closeTimeFlag: closeTimeFlag,
      ),
    );
  }

  void updateDanmaku({List<LiveMessage>? messages}) {
    if (messages != null) {
      danmakuMessages.assignAll(messages);
    }
  }

  void addDanmakuMessage(LiveMessage msg, {bool immediate = false}) {
    if (isClosed) return;
    if (_pendingDanmakuMessages.length >= _maxPendingDanmakuBatch) {
      _pendingDanmakuMessages.removeAt(0);
    }
    _pendingDanmakuMessages.add(msg);
    if (immediate) {
      _danmakuFlushTimer?.cancel();
      _danmakuFlushTimer = null;
      _flushDanmakuMessages();
      return;
    }
    _danmakuFlushTimer ??= Timer(_danmakuBatchWindow, _flushDanmakuMessages);
  }

  void _flushDanmakuMessages() {
    _danmakuFlushTimer = null;
    debugPrint(
      'DBG flush total=${danmakuMessages.length} pending=${_pendingDanmakuMessages.length} isClosed=$isClosed',
    );
    if (_pendingDanmakuMessages.isEmpty || isClosed) return;
    final next = <LiveMessage>[...danmakuMessages, ..._pendingDanmakuMessages];
    _pendingDanmakuMessages.clear();
    if (next.length > _maxDanmakuHistory) {
      next.removeRange(0, next.length - _maxDanmakuHistory);
    }
    danmakuMessages.assignAll(next);
  }

  void removeDanmakuWhere(bool Function(LiveMessage message) predicate) {
    _pendingDanmakuMessages.removeWhere(predicate);
    final next = danmakuMessages.where((message) => !predicate(message)).toList(growable: false);
    if (next.length != danmakuMessages.length) danmakuMessages.assignAll(next);
  }

  Future<void> _onRoomPlaybackTimerEnded() async {
    updateUI(closeTimeFlag: false);
    await GlobalPlayerService.instance.playerManager.pause();
    await LiveAudioService.stop();
    ToastUtil.show(i18n('room_playback_timer_finished'));
  }

  void updateRuntimeAudience(dynamic value) {
    if (isClosed) return;
    final update = value is LiveAudienceUpdate ? value : null;
    final rawValue = (update?.value ?? value)?.toString().trim() ?? '';
    if (!RegExp(r'[0-9]').hasMatch(rawValue)) return;
    final count = LiveRoom.parseAudienceNumber(rawValue);
    final detail = state.value.room.detail;
    if (detail == null) return;
    if (count < 0) return;
    final text = count.toString();
    final inferredKind = detail.platform == Sites.bilibiliSite
        ? LiveAudienceMetricKind.popularity
        : LiveAudienceMetricKind.onlineViewers;
    final kind = update?.kind ?? inferredKind;
    final candidate = switch (kind) {
      LiveAudienceMetricKind.popularity => detail.copyWith(
        watching: text,
        popularity: text,
        audienceMetricType: AudienceMetricType.popularity,
      ),
      LiveAudienceMetricKind.onlineViewers => detail.copyWith(onlineViewers: text),
      LiveAudienceMetricKind.totalViewers => detail.copyWith(totalViewers: text),
    };
    updateRoom(detail: candidate.withAudienceFallbackFrom(detail));
  }

  void emitLocalMessage(LiveMessage msg, {required bool showAsDanmaku, Duration delay = Duration.zero}) {
    if (!localInteractionController.enabled.v) return;
    _localMessageDeliveryQueue.schedule(
      LocalMessageDelivery(message: msg, showAsDanmaku: showAsDanmaku, roomEpoch: _roomLoadEpoch),
      delay: delay,
    );
  }

  void _deliverLocalMessage(LocalMessageDelivery delivery) {
    if (isClosed || _ownerClosed || delivery.roomEpoch != _roomLoadEpoch) return;
    final msg = delivery.message;
    addDanmakuMessage(msg, immediate: true);
    if (delivery.showAsDanmaku) state.value.player.videoController?.sendDanmaku(msg);
    if (msg.type == LiveMessageType.gift && localInteractionController.enableGiftEffects.v) {
      localGiftEffect.v = msg;
      _localGiftEffectTimer?.cancel();
      _localGiftEffectTimer = Timer(const Duration(seconds: 3), () => localGiftEffect.v = null);
    }
  }

  /// Applies the headphone action to this room only. Restoring video also
  /// ends an automatically started ASMR timer, while manually entering audio
  /// mode does not implicitly create a sleep session.
  Future<void> setCurrentRoomAudioOnlyFromUser(bool value) async {
    if (!value && _asmrSessionActive) {
      _asmrSessionActive = false;
      await LiveAudioService.configureSleepTimer(enabled: false, minutes: SettingsService.to.app.asmrSleepMinutes.v);
    }
    await playerController.changeCurrentRoomAudioOnly(value);
  }

  void addSystemMessage(String text) {
    final msg = LiveMessage(
      type: LiveMessageType.chat,
      userName: i18n('system_message'),
      message: text,
      color: LiveMessageColor.white,
    );
    addDanmakuMessage(msg);
  }

  /// 发送弹幕（弹幕输入条调用）。
  ///
  /// 真正联网发送：调用 [currentSite.liveSite.sendDanmaku]（B站会真实发送并
  /// 返回 (是否成功, 提示)）。发送成功后由服务器弹幕回包自然显示，无需本地回显。
  Future<bool> sendLiveDanmaku(String text) async {
    final content = text.trim();
    if (content.isEmpty) return false;
    if (site != Sites.bilibiliSite) {
      ToastUtil.show(i18n('send_danmaku_unsupported'));
      return false;
    }
    if (SettingsService.to.cookieManager.bilibiliCookie.v.trim().isEmpty) {
      ToastUtil.show(i18n('send_danmaku_need_login'));
      return false;
    }
    final roomId = room.roomId ?? '';
    if (roomId.isEmpty) return false;

    final (ok, info) = await currentSite.liveSite.sendDanmaku(roomId: roomId, message: content);
    if (ok) {
      ToastUtil.show(i18n('send_success'));
      return true;
    }
    ToastUtil.show(info.isEmpty ? i18n('send_failed') : info);
    return false;
  }

  /// 往弹幕列表添加一条醒目留言(SC)并按需触发全屏弹出。
  ///
  /// 供 danmaku 收流端（[DanmakuController.engine.onMessage] 的 superChat 分支）
  /// 调用。当前分支收流点在 danmaku_controller，本类不持有该回调，因此暴露此
  /// 公开方法作为挂载约定，调用方式：
  /// ```dart
  /// } else if (msg.type == LiveMessageType.superChat) {
  ///   final sc = msg.data;
  ///   if (sc is LiveSuperChatMessage) _main.handleSuperChatMessage(sc);
  /// }
  /// ```
  /// 默认始终展示（当前分支尚无 showSuperChat 开关，直接显示）。
  void handleSuperChatMessage(LiveSuperChatMessage sc) {
    if (isClosed) return;
    addDanmakuMessage(
      LiveMessage(
        type: LiveMessageType.superChat,
        userName: sc.userName,
        message: sc.message,
        color: LiveMessageColor.white,
        data: sc,
      ),
    );
    if (GlobalPlayerState.to.fullscreenUI) {
      showFullscreenSC(sc);
    }
  }

  /// 全屏左下角弹出 SC 卡片，按 SC 有效时间（至少 3 秒）自动消失。
  void showFullscreenSC(LiveSuperChatMessage sc) {
    _fsSCTimer?.cancel();
    fsSC.value = sc;
    var duration = sc.endTime.difference(DateTime.now());
    if (duration < const Duration(seconds: 3)) {
      duration = const Duration(seconds: 3);
    }
    _fsSCTimer = Timer(duration, () {
      if (identical(fsSC.value, sc)) {
        fsSC.value = null;
      }
      _fsSCTimer = null;
    });
  }

  /// 隐藏全屏 SC 卡片并取消计时。
  void hideFullscreenSC() {
    _fsSCTimer?.cancel();
    _fsSCTimer = null;
    fsSC.value = null;
  }

  void clearDanmakuMessages() {
    _danmakuFlushTimer?.cancel();
    _danmakuFlushTimer = null;
    _pendingDanmakuMessages.clear();
    danmakuMessages.clear();
    clearRenderedDanmaku();
  }

  void updateDanmakuRoomId(String? roomId) {
    if (state.value.danmaku.currentDanmakuRoomId == roomId) return;
    state.value = state.value.copyWith(danmaku: state.value.danmaku.copyWith(currentDanmakuRoomId: roomId));
  }

  void clearRenderedDanmaku() {
    state.value.player.videoController?.clearDanmaku();
  }

  void updateTimerFlag(bool flag) {
    updateUI(closeTimeFlag: flag);
    timerController.toggleTimer(flag, state.value.ui.closeTimes);
  }

  void updateTimerTimes(int times) {
    updateUI(closeTimes: times);
    if (state.value.ui.closeTimeFlag) {
      timerController.toggleTimer(true, times);
    }
  }

  Future<LiveRoom> onInitPlayerState({
    ReloadDataType reloadDataType = ReloadDataType.refreash,
    int line = 0,
    bool isReCalculate = true,
  }) async {
    final roomId = state.value.room.detail?.roomId;
    if (roomId == null) return LiveRoom();
    final requestedPlatform = state.value.room.detail?.platform;
    final loadEpoch = ++_roomLoadEpoch;

    updateRoom(isLoading: true, loadError: null);

    try {
      final fetchedRoom = await currentSite.liveSite.getRoomDetail(
        roomId: roomId,
        platform: state.value.room.detail!.platform!,
      );
      final liveRoom = fetchedRoom.withAudienceFallbackFrom(state.value.room.detail!);
      if (!_isRoomLoadCurrent(loadEpoch, roomId, requestedPlatform)) return liveRoom;

      _handleCurrentLineAndQuality(reloadDataType, line, isReCalculate);

      updateRoom(detail: liveRoom);
      updateUI(refreshKey: state.value.ui.refreshKey + 1);

      if (liveRoom.liveStatus == LiveStatus.unknown) {
        _handleUnknownStatus();
        return liveRoom;
      }

      final liveStatus = liveRoom.status == true || liveRoom.isRecord == true;

      if (liveStatus) {
        await _handleLiveRoom(liveRoom, loadEpoch: loadEpoch);
      } else {
        _handleNotLiveRoom(liveRoom);
      }

      updateRoom(isLoading: false);
      return liveRoom;
    } catch (e) {
      if (!_isRoomLoadCurrent(loadEpoch, roomId, requestedPlatform)) return LiveRoom();
      updateRoom(isLoading: false, loadError: e.toString());
      ToastUtil.show(i18n('get_room_info_failed_retry'));
      return LiveRoom();
    }
  }

  bool _isRoomLoadCurrent(int epoch, String roomId, String? platform) {
    final current = state.value.room.detail;
    return epoch == _roomLoadEpoch && current?.roomId == roomId && current?.platform == platform;
  }

  void invalidateRoomLoad() => _roomLoadEpoch++;

  Future<void> _handleLiveRoom(LiveRoom liveRoom, {required int loadEpoch}) async {
    updateRoom(isLiving: true, success: false);

    try {
      await playerController.getPlayQualites();
      if (loadEpoch != _roomLoadEpoch) return;

      SettingsService.to.fav.updateRoom(liveRoom);
      EventBus.instance.emit('refresh_room_changed', true);

      final danmakuSettings = SettingsService.to.danmaku;
      final shouldConnectDanmaku = danmakuSettings.enableDanmakuDisplay.v || danmakuSettings.enablePipDanmaku.v;
      if (shouldConnectDanmaku) {
        await danmakuController.connectRoom(liveRoom);
      } else {
        await danmakuController.stopDanmaku();
      }
    } catch (error, stackTrace) {
      developer.log(
        'Live room initialization failed (${error.runtimeType})',
        name: 'LivePlayController',
        stackTrace: stackTrace,
      );
      updateRoom(success: false);
    }
  }

  void _handleNotLiveRoom(LiveRoom liveRoom) {
    unawaited(danmakuController.stopDanmaku());
    updateRoom(success: false, isLiving: false);
    setNormalScreen();
    GlobalPlayerState.to.isFullscreen.value = false;
    GlobalPlayerState.to.isWindowFullscreen.value = false;
    SettingsService.to.fav.updateRoom(liveRoom);
    EventBus.instance.emit('refresh_room_changed', true);
    ToastUtil.show(
      liveRoom.liveStatus == LiveStatus.banned ? i18n('server_error_retry_later') : i18n('stream_not_live'),
    );
    _restoreQualityAndLines();
  }

  void _handleUnknownStatus() {
    unawaited(danmakuController.stopDanmaku());
    if (Get.currentRoute == '/live_play') {
      ToastUtil.show(i18n('get_room_info_failed_retry'));
      setNormalScreen();
      GlobalPlayerState.to.isFullscreen.value = false;
      GlobalPlayerState.to.isWindowFullscreen.value = false;
    }
  }

  void _handleCurrentLineAndQuality(ReloadDataType reloadDataType, int line, bool isReCalculate) {
    if (reloadDataType == ReloadDataType.changeLine && isReCalculate && state.value.player.playUrls.isNotEmpty) {
      final newLineIndex = (state.value.player.currentLineIndex + 1) % state.value.player.playUrls.length;
      updatePlayer(currentLineIndex: newLineIndex);
    }
  }

  void _restoreQualityAndLines() {
    updatePlayer(playUrls: [], currentLineIndex: 0, qualites: [], currentQuality: 0);
  }

  Future<void> switchRoom(LiveRoom newRoom) async {
    // Fence any room-detail/play-quality request that was started before this
    // switch. Its late result must not restore the previous room or socket.
    invalidateRoomLoad();
    _localMessageDeliveryQueue.cancelAll();
    final sameRoom =
        state.value.room.detail?.roomId == newRoom.roomId && state.value.room.detail?.platform == newRoom.platform;

    final danmakuSettings = SettingsService.to.danmaku;
    final shouldConnectDanmaku = danmakuSettings.enableDanmakuDisplay.v || danmakuSettings.enablePipDanmaku.v;
    if (!sameRoom) {
      clearDanmakuMessages();
      if (shouldConnectDanmaku) {
        // 主副切换/换房：挂起旧弹幕连接并复用缓存连接。
        // 不销毁重建——斗鱼等平台对同房间快速二次登录会静默限流，
        // 导致切换后弹幕永远收不到消息。
        await danmakuController.switchRoomDanmaku(newRoom);
      } else {
        await danmakuController.stopDanmaku();
      }
    }

    final manager = GlobalPlayerService.instance.playerManager;
    await manager.close();

    updateRoom(success: false, isLiving: true);
    await playerController.destroyPlayer();

    updatePlayer(hasUseDefaultResolution: false);
    updateUI(refreshKey: 0);

    final autoStartAsmr = Platform.isAndroid && SettingsService.to.app.enableAsmrSleepMode.v;
    _asmrSessionActive = autoStartAsmr;
    await LiveAudioService.configureSleepTimer(
      enabled: autoStartAsmr,
      minutes: SettingsService.to.app.asmrSleepMinutes.v,
    );
    updatePlayer(isCurrentRoomAudioOnly: autoStartAsmr || SettingsService.to.player.audioOnly.v);

    updateRoom(detail: newRoom);
    currentSite = Sites.of(newRoom.platform!);
    playerController.initSite(currentSite);

    if (!sameRoom && !shouldConnectDanmaku) {
      await danmakuController.replaceDanmaku(currentSite.liveSite.getDanmaku());
    }

    await EmojiManager.instance.preload(newRoom.platform!);

    await onInitPlayerState(
      reloadDataType: newRoom.platform == Sites.bilibiliSite ? ReloadDataType.changeLine : ReloadDataType.refreash,
    );
  }

  Future<void> setResolution(ReloadDataType reloadDataType, int qualityIndex, int lineIndex) async {
    invalidateRoomLoad();
    await GlobalPlayerService.instance.playerManager.close();
    await playerController.destroyPlayer();

    updatePlayer(currentQuality: qualityIndex, currentLineIndex: lineIndex);

    await onInitPlayerState(reloadDataType: reloadDataType, line: lineIndex, isReCalculate: false);
  }

  Future<void> openNaviteAPP() async {
    var nativeUrl = "";
    var webUrl = "";
    final detail = state.value.room.detail;
    if (detail == null) return;

    switch (site) {
      case Sites.bilibiliSite:
        nativeUrl = "bilibili://live/${detail.roomId}";
        webUrl = "https://live.bilibili.com/${detail.roomId}";
        break;
      case Sites.douyinSite:
        final args = detail.danmakuData as DouyinDanmakuArgs;
        nativeUrl = "snssdk1128://webcast_room?room_id=${args.roomId}";
        webUrl = "https://live.douyin.com/${args.webRid}";
        break;
      case Sites.huyaSite:
        final args = detail.danmakuData as HuyaDanmakuArgs;
        nativeUrl =
            "yykiwi://homepage/index.html?banneraction=https%3A%2F%2Fdiy-front.cdn.huya.com%2Fzt%2Ffrontpage%2Fcc%2Fupdate.html%3Fhyaction%3Dlive%26channelid%3D${args.subSid}%26subid%3D${args.subSid}%26liveuid%3D${args.subSid}%26screentype%3D1%26sourcetype%3D0%26fromapp%3Dhuya_wap%252Fclick%252Fopen_app_guide%26&fromapp=huya_wap/click/open_app_guide";
        webUrl = "https://www.huya.com/${detail.roomId}";
        break;
      case Sites.douyuSite:
        nativeUrl = "douyulink://?type=90001&schemeUrl=douyuapp%3A%2F%2Froom%3FliveType%3D0%26rid%3D${detail.roomId}";
        webUrl = "https://www.douyu.com/${detail.roomId}";
        break;
    }

    try {
      if (Platform.isAndroid) {
        await launchUrlString(nativeUrl, mode: LaunchMode.externalApplication);
      } else {
        await launchUrlString(webUrl, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      ToastUtil.show(i18n('open_app_failed_fallback_browser'));
      await launchUrlString(webUrl, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> startCatchUp({required String catchUpUrl, int? startTime, int? endTime}) async {
    final currentRoom = state.value.room.detail;
    if (currentRoom == null) return;

    final updatedRoom = currentRoom.copyWith(
      catchUpUrl: catchUpUrl,
      isCatchUp: true,
      catchUpStart: startTime,
      catchUpEnd: endTime,
    );

    updateRoom(detail: updatedRoom);
    await _switchToUrl(catchUpUrl);
  }

  Future<void> _switchToUrl(String url) async {
    updateRoom(success: false);
    updatePlayer(playUrls: [url], currentLineIndex: 0);
    await playerController.setPlayer(roomId: state.value.room.detail!.roomId!);
    updateRoom(success: true);
  }

  void setNormalScreen() => updateUI(screenMode: VideoMode.normal);
  void setWidescreen() => updateUI(screenMode: VideoMode.widescreen);
  void setFullScreen() => updateUI(screenMode: VideoMode.fullscreen);

  void prepareAppFloating() {
    GlobalPlayerService.instance.playerManager.prepareAppFloating(onClose: disposeAppFloatingResources);
    _floatingResourcesReleased = false;
  }

  void disposeAppFloatingResources() {
    if (_floatingResourcesReleased) return;
    _floatingResourcesReleased = true;

    final videoController = state.value.player.videoController;
    unawaited(_disposeAppFloatingResourcesAsync(videoController));
  }

  Future<void> _disposeAppFloatingResourcesAsync(VideoController? videoController) async {
    await danmakuController.stopDanmaku();
    videoController?.dispose();
    if (_ownerClosed) {
      _releaseChildControllers();
      _closeReactiveState();
    }
  }

  void _releaseChildControllers() {
    if (_childControllersReleased) return;
    _childControllersReleased = true;
    Get.delete<TimerController>(tag: 'timer-$_controllerTag', force: true);
    Get.delete<DanmakuController>(tag: 'danmaku-$_controllerTag', force: true);
    Get.delete<PlayerController>(tag: 'player-$_controllerTag', force: true);
  }

  void _closeReactiveState() {
    if (_reactiveStateClosed) return;
    _reactiveStateClosed = true;
    state.close();
  }

  @override
  void onClose() {
    _ownerClosed = true;
    _roomLoadEpoch++;
    _localGiftEffectTimer?.cancel();
    _fsSCTimer?.cancel();
    _fsSCTimer = null;
    _localMessageDeliveryQueue.dispose();
    _danmakuFlushTimer?.cancel();
    _pendingDanmakuMessages.clear();
    tabController.dispose();

    // 兜底复位全局全屏标志（覆盖绕过返回键处理直接弹出页面的路径）。
    GlobalPlayerState.to.isFullscreen.value = false;
    GlobalPlayerState.to.isWindowFullscreen.value = false;
    // 兜底恢复竖屏与系统状态栏/导航栏，避免全屏残留
    // （edge-to-edge 下小米手势条正常显示，手机不再横屏挂着首页）。
    unawaited(_restoreMobileScreenUi());

    final keepForAppFloating = GlobalPlayerService.instance.playerManager.shouldKeepDanmakuForAppFloating;
    if (!keepForAppFloating) {
      disposeAppFloatingResources();
      _releaseChildControllers();
      _closeReactiveState();
    }
    // 退出直播间时结束双开副窗口，避免再次进入直播间时残留
    unawaited(SecondaryPlayerService.instance.close());
    super.onClose();
  }
}
