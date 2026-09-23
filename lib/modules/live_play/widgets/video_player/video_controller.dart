import 'dart:async';
import 'dart:developer';

import 'video_controller_panel.dart';
import 'package:pure_live/player/utils/orientation_policy.dart';

import 'package:flutter/scheduler.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/player/core/secondary_player_service.dart';
import 'package:flutter/services.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flame_barrage/flame_barrage.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:pure_live/player/core/player_manager.dart';
import 'package:pure_live/player/utils/fullscreen.dart';
import 'package:pure_live/common/global/platform/mobile_manager.dart';
import 'package:pure_live/player/models/player_exception.dart';
import 'package:pure_live/player/models/player_error_type.dart';
import 'package:pure_live/modules/live_play/states/load_type.dart';
import 'package:pure_live/modules/live_play/controllers/player_state.dart';
import 'package:pure_live/modules/live_play/widgets/danmaku_message_actions.dart';
import 'package:pure_live/modules/live_play/controllers/live_play_controller.dart';
import 'package:pure_live/common/global/platform_utils.dart';

typedef AudioOnlyCallback = Future<void> Function(bool value);

enum PlayerStatus { idle, loading, playing, error, disposed }

// 平台工具类
class PlatformHelper {
  static bool get isMobile => PlatformUtils.isAndroid || PlatformUtils.isIOS;
  static bool get isDesktop => PlatformUtils.isWindows || PlatformUtils.isLinux || PlatformUtils.isMacOS;
  static bool get supportsBrightness => PlatformUtils.isAndroid || PlatformUtils.isIOS;
  static bool get supportsVolumeController => PlatformUtils.isAndroid || PlatformUtils.isIOS;
  static bool get supportsBatteryMonitoring => PlatformUtils.isAndroid || PlatformUtils.isIOS;
}

// 弹幕管理器
class DanmakuManager {
  final BarrageController controller;
  final BarrageController pipController;
  final List<Worker> workers = [];
  final SettingsService settingsService;
  final VideoController videoController;
  final RxInt _visualSettingsRevision = 0.obs;
  bool _configUpdateScheduled = false;
  bool _settingsDirty = false;
  bool _disposed = false;
  DateTime? _lastLongPressAction;

  DanmakuManager({
    required this.controller,
    required this.pipController,
    required this.settingsService,
    required this.videoController,
  });

  void setupWorkers() {
    final dm = settingsService.danmaku;

    // 设置初始值
    videoController.hideDanmaku.value = dm.hideDanmaku.v;
    videoController.noEmojiMode.value = dm.noEmojiMode.v;
    videoController.danmakuArea.value = dm.danmakuArea.v;
    videoController.danmakuTopArea.value = dm.danmakuTopArea.v;
    videoController.danmakuBottomArea.value = dm.danmakuBottomArea.v;
    final migratedSpeed = dm.danmakuSpeed.v.clamp(20.0, 400.0).toDouble();
    videoController.danmakuSpeed.value = migratedSpeed;
    if (migratedSpeed != dm.danmakuSpeed.v) {
      dm.danmakuSpeed.v = migratedSpeed;
    }
    videoController.danmakuFontSize.value = dm.danmakuFontSize.v;
    videoController.danmakuFontWeight.value = dm.danmakuFontWeight.v;
    videoController.danmakuFontBorder.value = dm.danmakuFontBorder.v;
    videoController.danmakuOpacity.value = dm.danmakuOpacity.v;
    videoController.enableDanmakuStroke.value = dm.enableDanmakuStroke.v;
    videoController.danmakuFps.value = dm.danmakuFps.v;
    videoController.danmakuFontFamilyName.value = dm.danmakuFontFamilyName.v;

    // 设置 workers
    workers.add(ever<bool>(videoController.hideDanmaku, (data) => dm.hideDanmaku.v = data));

    final List<Rx> visualProperties = [
      videoController.danmakuArea,
      videoController.danmakuTopArea,
      videoController.danmakuBottomArea,
      videoController.danmakuSpeed,
      videoController.danmakuFontSize,
      videoController.danmakuFontWeight,
      videoController.danmakuFontBorder,
      videoController.danmakuOpacity,
      videoController.enableDanmakuStroke,
      videoController.danmakuFps,
      videoController.danmakuFontFamilyName,
      videoController.noEmojiMode,
    ];

    workers.add(
      everAll(visualProperties, (_) {
        _settingsDirty = true;
        _visualSettingsRevision.value++;
        _scheduleConfigUpdate();
      }),
    );
    workers.add(
      debounce<int>(_visualSettingsRevision, (_) => _persistVisualSettings(), time: const Duration(milliseconds: 160)),
    );
    workers.add(everAll([dm.danmakuAutoFps, DisplayModeService.info], (_) => _scheduleConfigUpdate()));
  }

  void _openMessageActions(LiveMessage message, {required bool fromLongPress}) {
    final now = DateTime.now();
    if (fromLongPress) {
      _lastLongPressAction = now;
    } else if (_lastLongPressAction != null && now.difference(_lastLongPressAction!) < const Duration(seconds: 1)) {
      return;
    }
    final context = Get.context;
    if (context == null) return;
    controller.pause();
    unawaited(DanmakuMessageActions.show(context, message).whenComplete(controller.resume));
  }

  void _scheduleConfigUpdate() {
    if (_disposed || _configUpdateScheduled) return;
    _configUpdateScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _configUpdateScheduled = false;
      if (!_disposed) videoController.updateDanmaku();
    });
    SchedulerBinding.instance.scheduleFrame();
  }

  void _persistVisualSettings() {
    if (!_settingsDirty) return;
    final dm = settingsService.danmaku;
    dm.danmakuArea.v = videoController.danmakuArea.value;
    dm.danmakuTopArea.v = videoController.danmakuTopArea.value;
    dm.danmakuBottomArea.v = videoController.danmakuBottomArea.value;
    dm.danmakuSpeed.v = videoController.danmakuSpeed.value;
    dm.danmakuFontSize.v = videoController.danmakuFontSize.value;
    dm.danmakuFontWeight.v = videoController.danmakuFontWeight.value;
    dm.danmakuFontBorder.v = videoController.danmakuFontBorder.value.toDouble();
    dm.danmakuOpacity.v = videoController.danmakuOpacity.value;
    dm.enableDanmakuStroke.v = videoController.enableDanmakuStroke.value;
    dm.danmakuFps.v = videoController.danmakuFps.value;
    dm.danmakuFontFamilyName.v = videoController.danmakuFontFamilyName.value;
    dm.noEmojiMode.v = videoController.noEmojiMode.value;
    _settingsDirty = false;
  }

  void sendDanmaku(LiveMessage msg, bool isPlaying, bool isCompactMode) {
    // A locally composed message is a UI interaction rather than a packet from
    // the live transport. Do not silently discard it while playback is still
    // starting or briefly buffering.
    if (!isPlaying && !msg.isLocal) return;

    final originalColor = Color.fromARGB(255, msg.color.r, msg.color.g, msg.color.b);
    final settings = settingsService.danmaku;
    if (settings.enableDanmakuDisplay.v && !videoController.hideDanmaku.value) {
      controller.send(
        BarrageItem(
          content: msg.message,
          userId: msg.userId,
          userName: msg.userName,
          isOwn: msg.isLocal,
          textColor: originalColor,
          // A single px/s value keeps portrait, landscape and desktop motion
          // consistent. Lane collision avoidance is handled by the engine.
          baseSpeed: videoController.danmakuSpeed.value,
          onTapUp: settings.enableDanmakuTapInteraction.v ? () => _openMessageActions(msg, fromLongPress: false) : null,
          onLongTapDown: settings.enableDanmakuLongPressInteraction.v
              ? () => _openMessageActions(msg, fromLongPress: true)
              : null,
        ),
      );
    }

    if (settings.enablePipDanmaku.v && isCompactMode) {
      final compactColor = settings.pipDanmakuUseOriginalColor.v ? originalColor : Color(settings.pipDanmakuColor.v);
      pipController.send(BarrageItem(content: msg.message, isOwn: msg.isLocal, textColor: compactColor));
    }
  }

  bool handlePointer(Offset position, {required bool longPress}) {
    final settings = settingsService.danmaku;
    final enabled = longPress ? settings.enableDanmakuLongPressInteraction.v : settings.enableDanmakuTapInteraction.v;
    if (!enabled) return false;
    return controller.triggerItemAt(position.dx, position.dy, longPress: longPress);
  }

  void dispose() {
    _persistVisualSettings();
    _disposed = true;
    for (final worker in workers) {
      worker.dispose();
    }
    workers.clear();
    controller.clear();
    pipController.clear();
  }
}

class VideoController with ChangeNotifier {
  // 常量定义
  static const _controllerHideDelay = Duration(seconds: 4);
  static const _fullscreenDelay = Duration(milliseconds: 1000);
  static const _volumeHideDelay = Duration(seconds: 1);

  // 依赖注入
  final LiveRoom room;
  final String datasource;
  final List<String> playUrs;
  final bool allowScreenKeepOn;
  final bool allowFullScreen;
  final Map<String, String> headers;
  final String qualiteName;
  final int currentLineIndex;
  final int currentQuality;
  final bool isAudioOnly;
  final AudioOnlyCallback? onAudioOnlyChanged;

  final Battery _battery;
  final SettingsService _settingsService;
  final PlayerManager _playerManager;
  final LivePlayController _livePlayController;

  // 资源管理
  final List<StreamSubscription> _subscriptions = [];
  final List<Timer> _timers = [];

  // 状态
  PlayerStatus _status = PlayerStatus.idle;
  PlayerStatus get status => _status;
  // 全屏切换令牌：捕获进/退全屏异步方向切换，防止连续快速进/退造成竞态。
  int _fullscreenToken = 0;
  // 全屏进/退切换进行中标记：返回拦截在切换期间忽略快速连续返回，避免竞态。
  final isTransitioningFullScreen = false.obs;
  final isVertical = false.obs;
  final showController = true.obs;
  // 弹幕输入条在全屏控制条内输入时置为 true，避免控制条自动隐藏打断输入。
  final inputEditing = false.obs;
  final showLocked = false.obs;
  final isMenuOpen = false.obs;
  final showVolume = false.obs;
  final batteryLevel = 100.obs;

  /// 充电（或已充满仍插电）状态，供视频界面电池 UI 区分显示
  final batteryCharging = false.obs;
  final currentVolume = 1.0.obs;

  // 弹幕相关
  final hideDanmaku = false.obs;
  final noEmojiMode = false.obs;
  final danmakuArea = 1.0.obs;
  final danmakuTopArea = 0.0.obs;
  final danmakuBottomArea = 0.0.obs;
  final danmakuSpeed = 120.0.obs;
  final danmakuFontSize = 16.0.obs;
  final danmakuFontWeight = FontWeight.w500.value.obs;
  final danmakuFontBorder = 1.5.obs;
  final danmakuOpacity = 1.0.obs;
  final enableDanmakuStroke = true.obs;
  final danmakuFps = 60.obs;
  final danmakuFontFamilyName = ''.obs;

  // 控制器
  late final VolumeController _volumeController;
  late final BarrageController danmakuController;
  late final BarrageController pipDanmakuController;
  late final DanmakuManager _danmakuManager;

  // Keys
  GlobalKey<BrightnessVolumnDargAreaState> brightnessKey = GlobalKey<BrightnessVolumnDargAreaState>();
  final danmuKey = GlobalKey();
  GlobalKey playerKey = GlobalKey();

  // 屏幕亮度
  ScreenBrightness? _brightnessController;
  ScreenBrightness? get brightnessController {
    if (!PlatformHelper.supportsBrightness) return null;
    _brightnessController ??= ScreenBrightness();
    return _brightnessController;
  }

  bool get supportWindowFull => PlatformUtils.isWindows || PlatformUtils.isLinux;

  // 暴露 livePlayController 的 getter
  LivePlayController get livePlayController => _livePlayController;

  // 构造函数
  VideoController({
    required this.room,
    required this.datasource,
    required this.headers,
    required this.playUrs,
    required this.qualiteName,
    required this.currentLineIndex,
    required this.currentQuality,
    required this.isAudioOnly,
    this.allowScreenKeepOn = false,
    this.allowFullScreen = true,
    this.onAudioOnlyChanged,
    BoxFit fitMode = BoxFit.contain,
    Battery? battery,
    PlayerManager? playerManager,
    SettingsService? settingsService,
    LivePlayController? livePlayController,
  }) : _battery = battery ?? Battery(),
       _playerManager = playerManager ?? GlobalPlayerService.instance.playerManager,
       _settingsService = settingsService ?? SettingsService.to,
       _livePlayController = livePlayController ?? Get.find<LivePlayController>() {
    currentVolume.value = room.getSavedVolume();
    _initControllers();
    _initPagesConfig();
  }

  // 初始化方法
  void _initControllers() {
    danmakuController = BarrageController();
    pipDanmakuController = BarrageController();
    _danmakuManager = DanmakuManager(
      controller: danmakuController,
      pipController: pipDanmakuController,
      settingsService: _settingsService,
      videoController: this,
    );
  }

  void _initPagesConfig() {
    _danmakuManager.setupWorkers();

    if (allowScreenKeepOn) WakelockPlus.enable();

    _playerManager.attachVideoController(this);

    unawaited(initVideoController());
    initBattery();
  }

  // 播放器初始化
  Future<void> initVideoController() async {
    _setStatus(PlayerStatus.loading);

    await _initVolumeController();
    if (_isDisposed) return;

    await _playVideo();
    if (_isDisposed) return;

    initPlayerListener();
    _setupDefaultFullscreen();

    _setStatus(PlayerStatus.playing);
  }

  Future<void> _initVolumeController() async {
    if (!PlatformHelper.supportsVolumeController) return;

    _volumeController = VolumeController.instance;
    _volumeController.showSystemUI = false;
    registerVolumeListener();

    final currentVolume = await _volumeController.getVolume();
    if (currentVolume > 0.001) {
      final targetVolume = room.getSavedVolume();
      await _volumeController.setVolume(targetVolume);
    }
  }

  Future<void> _playVideo() async {
    await _playerManager.play(datasource, playUrs, headers, room: room, audioOnly: isAudioOnly);
  }

  void _setupDefaultFullscreen() {
    final timer = Timer(_fullscreenDelay, () {
      if (_isDisposed) return;
      // 双开副窗口激活期间不自动进全屏：切换主副会重建播放器并重新武装本定时器，
      // 若用户此时已手动退出全屏，1 秒后会被强制拉回全屏，表现为"退出全屏没生效"。
      if (SecondaryPlayerService.instance.isActive.value) {
        return;
      }
      // 路由"全屏播放"入口在 controller 初始化时即已全屏，不在此重复触发
      // （重复进入会弹出控制栏并打断用户操作）。
      if (_livePlayController.startInFullscreen || GlobalPlayerState.to.isFullscreen.value) {
        return;
      }
      if (_settingsService.app.enableFullScreenDefault.v) {
        _enterFullscreenMode();
      }
    });
    _addTimer(timer);
  }

  void _enterFullscreenMode() {
    _livePlayController.setFullScreen();
    enterFullScreen();
    GlobalPlayerState.to.isFullscreen.value = true;
    enableController();
  }

  // 资源管理方法
  void _addSubscription(StreamSubscription subscription) {
    _subscriptions.add(subscription);
  }

  void _addTimer(Timer timer) {
    _timers.add(timer);
  }

  Future<void> _cancelAllSubscriptions() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
  }

  void _cancelAllTimers() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
  }

  bool get _isDisposed => _status == PlayerStatus.disposed;

  void _setStatus(PlayerStatus newStatus) {
    _status = newStatus;
    notifyListeners();
  }

  // 播放器监听
  void initPlayerListener() {
    final errorSub = _playerManager.onError.listen((error) {
      log('error: ${error.toString()}', name: 'initPlayerListener');
      _handlePlayerError(error);
    });
    _addSubscription(errorSub);
  }

  void _handlePlayerError(PlayerException error) {
    _setStatus(PlayerStatus.error);

    final errorMessage = switch (error.type) {
      PlayerErrorType.network => i18n("error_network"),
      PlayerErrorType.source => i18n("error_source"),
      PlayerErrorType.codec => i18n("error_codec"),
      PlayerErrorType.native => i18n("error_native"),
      PlayerErrorType.initialization => i18n("error_initialization"),
      PlayerErrorType.texture => i18n("error_texture"),
      PlayerErrorType.lifecycle => i18n("error_lifecycle"),
      PlayerErrorType.unknown => i18n("error_unknown"),
    };

    ToastUtil.show(errorMessage);
  }

  // 电池管理
  void initBattery() {
    if (!PlatformHelper.supportsBatteryMonitoring) return;

    _battery.batteryLevel.then((value) {
      if (!_isDisposed) batteryLevel.value = value;
    });

    // 初始充电状态（full = 已充满仍插电，按充电显示）
    _battery.batteryState.then((state) {
      if (!_isDisposed) batteryCharging.value = _isPowered(state);
    }).catchError((_) {});

    final batterySub = _battery.onBatteryStateChanged.listen((BatteryState state) async {
      if (!_isDisposed) batteryCharging.value = _isPowered(state);
      final value = await _battery.batteryLevel;
      if (!_isDisposed) batteryLevel.value = value;
    });
    _addSubscription(batterySub);
  }

  static bool _isPowered(BatteryState state) =>
      state == BatteryState.charging || state == BatteryState.full;

  // 音量管理
  void registerVolumeListener() {
    final volumeSub = _volumeController.addListener((volume) async {
      // 音量键等系统音量变化：临时静音自动解除（用户主动调音量即视为取消静音）
      await _unmuteIfTempMuted();
      room.saveCurrentVolume(volume);
    }, fetchInitialVolume: true);
    _addSubscription(volumeSub);
  }

  /// 右上角一键静音：仅把播放器内核音量置 0（移动端内核音量恒为 1.0，
  /// 响度由系统媒体音量决定），不动系统音量、不写房间音量记忆。
  /// 任何音量调整（滑动手势/音量键）或再次点击都会恢复；切房即销毁复位。
  final RxBool tempMuted = false.obs;

  Future<void> toggleTempMute() async {
    if (tempMuted.value) {
      await _restoreTempMute();
      return;
    }
    tempMuted.value = true;
    await _playerManager.setVolume(0.0);
  }

  Future<void> _restoreTempMute() async {
    if (!tempMuted.value) return;
    tempMuted.value = false;
    // 移动端恢复内核 1.0（响度交回系统音量）；桌面端恢复房间保存音量
    await _playerManager.setVolume(
      PlatformHelper.isDesktop ? room.getSavedVolume().clamp(0.0, 1.0) : 1.0,
    );
  }

  Future<void> _unmuteIfTempMuted() async {
    if (tempMuted.value) await _restoreTempMute();
  }

  void updateVolumn(double volume) {
    _hideVolumeTimer?.cancel();
    showVolume.value = true;
    final timer = Timer(_volumeHideDelay, () {
      showVolume.value = false;
    });
    _addTimer(timer);
  }

  Future<double?> volume() async {
    if (PlatformHelper.isDesktop) {
      return room.getSavedVolume();
    }
    return await _volumeController.getVolume();
  }

  Future<void> setVolume(double value) async {
    // 用户主动调整音量（滑动手势等）：临时静音自动解除
    await _unmuteIfTempMuted();
    final resolved = value.clamp(0.0, 1.0).toDouble();
    if (PlatformHelper.isDesktop) {
      await _playerManager.setVolume(resolved);
    } else {
      await _volumeController.setVolume(resolved);
    }
    currentVolume.value = resolved;
    await room.saveCurrentVolume(resolved);
  }

  // 亮度管理
  Future<double> brightness() async {
    if (PlatformHelper.supportsBrightness) {
      return await brightnessController!.application;
    }
    throw Exception('Brightness not supported on this platform');
  }

  void setBrightness(double value) async {
    if (PlatformHelper.supportsBrightness) {
      await brightnessController!.setApplicationScreenBrightness(value);
    }
  }

  // 控制器显示管理
  void enableController() {
    showControllerTimer?.cancel();
    showController.value = true;

    if (inputEditing.value) return; // 弹幕输入期间保持控制条常显，不自动隐藏

    if (!_isMouseOverController && !_isMouseOverPlayer) {
      showControllerTimer = Timer(const Duration(seconds: 4), () {
        if (!_isMouseOverController && !_isMouseOverPlayer) {
          showController.value = false;
        }
      });
    }
  }

  void stopHideController() {
    showControllerTimer?.cancel();
    showControllerTimer = null;
  }

  // 鼠标进入控制器区域
  void onMouseEnterController() {
    _isMouseOverController = true;
    stopHideController();
    showController.value = true;
  }

  // 鼠标离开控制器区域
  void onMouseExitController() {
    _isMouseOverController = false;
    enableController(); // 重新开始计时
  }

  // 鼠标进入播放器区域
  void onMouseEnterPlayer() {
    _isMouseOverPlayer = true;
    showController.value = true;
    stopHideController();
  }

  void onMouseHoverPlayer() {
    _isMouseOverPlayer = false;
    _isMouseOverPlayer = false;
    enableController(); // 重新开始计时
  }

  // 鼠标离开播放器区域
  void onMouseExitPlayer() {
    _isMouseOverPlayer = false;
    enableController(); // 重新开始计时
  }

  // 手动切换控制器显示
  void toggleController() {
    if (showController.value) {
      showController.value = false;
      stopHideController();
    } else {
      enableController();
    }
  }

  // 弹幕管理
  void updateDanmaku() {
    danmakuController.updateConfig(
      BarrageConfig(
        emitInterval: 0.016,
        fontSize: danmakuFontSize.value,
        area: danmakuArea.value,
        topAreaDistance: danmakuTopArea.value,
        bottomAreaDistance: danmakuBottomArea.value,
        baseSpeed: danmakuSpeed.value,
        opacity: danmakuOpacity.value,
        fontWeight: FontWeight(danmakuFontWeight.value),
        strokeWidth: danmakuFontBorder.value,
        showStroke: enableDanmakuStroke.value,
        noEmojiMode: noEmojiMode.value,
        fps: SettingsService.to.danmaku.resolvedDanmakuFps(),
        maxPendingCount: 120,
        maxPendingAge: const Duration(seconds: 5),
        trackHeight: (danmakuFontSize.value * 1.55).clamp(24.0, 64.0).toDouble(),
        emojiSize: (danmakuFontSize.value * 1.3).clamp(16.0, 48.0).toDouble(),
      ),
    );
  }

  void sendDanmaku(LiveMessage msg) {
    _danmakuManager.sendDanmaku(msg, _playerManager.isPlayingNow, _playerManager.isCompactModeActive);
  }

  bool handleDanmakuPointer(Offset globalPosition, {required bool longPress}) {
    final renderObject = danmuKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return false;
    final localPosition = renderObject.globalToLocal(globalPosition);
    if (localPosition.dx < 0 ||
        localPosition.dy < 0 ||
        localPosition.dx > renderObject.size.width ||
        localPosition.dy > renderObject.size.height) {
      return false;
    }
    return _danmakuManager.handlePointer(localPosition, longPress: longPress);
  }

  void clearPipDanmaku() => pipDanmakuController.clear();

  void clearDanmaku() {
    danmakuController.resume();
    pipDanmakuController.resume();
    danmakuController.clear();
    pipDanmakuController.clear();
  }

  // 播放控制
  bool _audioModeSwitching = false;

  Future<void> toggleAudioOnly() async {
    if (_audioModeSwitching) return;
    _audioModeSwitching = true;
    clearListener();
    try {
      await onAudioOnlyChanged?.call(!isAudioOnly);
    } finally {
      _audioModeSwitching = false;
    }
  }

  void retryRoom() async {
    var liveRoom = await Sites.of(room.platform!).liveSite
        .getRoomDetail(roomId: room.roomId!, platform: room.platform!);

    if (liveRoom.liveStatus == LiveStatus.offline) {
      _livePlayController.setNormalScreen();
      ToastUtil.show(i18n("room_offline"));
    } else {
      changeLine();
    }
  }

  Future<void> refresh() async {
    _livePlayController.invalidateRoomLoad();
    clearListener();
    await _playerManager.close();
    await destory();
    await _livePlayController.onInitPlayerState(reloadDataType: ReloadDataType.refreash);
  }

  Future<void> changeLine() async {
    _livePlayController.invalidateRoomLoad();
    clearListener();
    await _playerManager.close();
    await destory();
    await _livePlayController.onInitPlayerState(reloadDataType: ReloadDataType.changeLine, line: currentLineIndex);
  }

  void clearListener() {
    final listenersToRemove = _subscriptions
        .where((s) => s is StreamSubscription<PlayerException> || s is StreamSubscription<bool>)
        .toList();

    for (final sub in listenersToRemove) {
      sub.cancel();
      _subscriptions.remove(sub);
    }
  }

  void debounceListen(Function? func, [int delay = 1000]) {
    _debounceTimer?.cancel();
    final timer = Timer(Duration(milliseconds: delay), () {
      func?.call();
    });
    _addTimer(timer);
  }

  // 全屏管理
  Future<void> exitFullScreen() async {
    // 捕获令牌：若切换期间又发生新的进/退全屏，本次异步恢复作废，交给最新操作处理。
    final token = ++_fullscreenToken;
    isTransitioningFullScreen.value = true;
    GlobalPlayerState.to.isFullscreen.value = false;
    try {
      // 退出全屏：手机恢复竖屏（portraitUp/portraitDown），平板保持横屏。
      // 加超时：MIUI 上键盘收起/系统栏动画期间该调用可能长时间不返回，
      // 一旦挂起 isTransitioningFullScreen 永不复位，后续返回事件全部失效。
      await WindowService().verticalScreen().timeout(const Duration(seconds: 3));
      // 期间若已有更新的全屏切换，放弃后续处理，避免覆盖。
      if (token != _fullscreenToken) return;
      // 退出全屏恢复系统状态栏/导航栏（edge-to-edge 下小米手势条恢复半透明正常显示）。
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge).timeout(const Duration(seconds: 3));
      // 恢复完整系统栏样式，导航栏显式透明，避免平板横屏底部手势条区域变黑。
      MobileManager.setStatusBarStyle(isDarkTheme: Get.isDarkMode);
    } catch (_) {
    } finally {
      if (token == _fullscreenToken) isTransitioningFullScreen.value = false;
    }
  }

  void toggleFullScreen() async {
    showLocked.value = false;
    stopHideController();

    final timer = Timer(_controllerHideDelay, () {
      enableController();
    });
    _addTimer(timer);

    GlobalPlayerState.to.isWindowFullscreen.value = false;

    if (GlobalPlayerState.to.isFullscreen.value) {
      // 退出全屏时还原双指缩放的画面（直接调用，不依赖状态监听时序）
      _playerManager.resetPinchZoom(animated: false);
      _livePlayController.setNormalScreen();
      _livePlayController.markFullscreenExit();
      await exitFullScreen();
    } else {
      _livePlayController.setFullScreen();
      await enterFullScreen();
    }
    enableController();
  }

  Future<void> enterFullScreen() async {
    // 捕获令牌：防止与随后立刻的退出全屏竞态，避免方向残留覆盖恢复逻辑。
    final token = ++_fullscreenToken;
    isTransitioningFullScreen.value = true;
    GlobalPlayerState.to.isFullscreen.value = true;
    try {
      // 进入全屏：按竖屏沉浸方向策略（每房间覆盖 > 全局策略，默认强制横屏保持旧行为）。
      final room = _livePlayController.state.value.room.detail;
      final target = OrientationPolicy.resolveFullscreenOrientation(
        platform: room?.platform ?? '',
        roomId: room?.roomId ?? '',
      );
      if (target == 'portrait') {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]).timeout(const Duration(seconds: 3));
      } else {
        await WindowService().landScape().timeout(const Duration(seconds: 3));
      }
      // 期间若已退出全屏，放弃本次设置，交还原来的方向。
      if (token != _fullscreenToken) return;
      // 全屏时隐藏系统状态栏/导航栏/手势条，沉浸式观看。
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky).timeout(const Duration(seconds: 3));
    } catch (_) {
    } finally {
      if (token == _fullscreenToken) isTransitioningFullScreen.value = false;
    }
  }

  void toggleWindowFullScreen() {
    showLocked.value = false;
    stopHideController();

    final timer = Timer(_controllerHideDelay, () {
      enableController();
    });
    _addTimer(timer);

    if (GlobalPlayerState.to.isWindowFullscreen.value) {
      // 退出窗口全屏时还原双指缩放的画面（直接调用，不依赖状态监听时序）
      _playerManager.resetPinchZoom(animated: false);
      _livePlayController.setNormalScreen();
      _livePlayController.markFullscreenExit();
      GlobalPlayerState.to.isWindowFullscreen.value = false;
    } else {
      _livePlayController.setWidescreen();
      GlobalPlayerState.to.isWindowFullscreen.value = true;
    }
    GlobalPlayerState.to.isFullscreen.value = false;
    enableController();
  }

  // 视频适配
  void setVideoFit(int index) {
    _playerManager.changeVideoFit(index);
  }

  // 资源销毁
  Future<void> destory() async {
    if (_resourcesDestroyed) return;
    _resourcesDestroyed = true;

    if (PlatformHelper.supportsVolumeController) {
      if (allowScreenKeepOn) await WakelockPlus.disable();
    }
  }

  bool _resourcesDestroyed = false;

  @override
  void dispose() {
    if (_isDisposed) return;
    _setStatus(PlayerStatus.disposed);

    // 清理资源
    _playerManager.detachVideoController(this);
    _danmakuManager.dispose();
    _cancelAllTimers();
    _isMouseOverController = false;
    _isMouseOverPlayer = false;
    // 异步清理
    unawaited(_disposeAsync());

    super.dispose();
  }

  Future<void> _disposeAsync() async {
    await _cancelAllSubscriptions();
    await destory();
  }

  // 兼容性属性
  Timer? showControllerTimer;
  // 添加鼠标状态跟踪
  bool _isMouseOverController = false;
  bool _isMouseOverPlayer = false;
  Timer? _debounceTimer;
  Timer? _hideVolumeTimer;
}
