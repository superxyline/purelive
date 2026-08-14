import 'dart:io';
import 'dart:async';
import 'dart:developer';
import 'video_controller_panel.dart';
import 'package:pure_live/common/index.dart';
import 'package:flutter/services.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flame_barrage/flame_barrage.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:pure_live/modules/live_play/load_type.dart';
import 'package:pure_live/common/global/platform_utils.dart';
import 'package:pure_live/player/models/player_exception.dart';
import 'package:pure_live/modules/live_play/player_state.dart';
import 'package:pure_live/player/models/player_error_type.dart';
import 'package:pure_live/modules/live_play/live_play_controller.dart';

typedef AudioOnlyCallback = void Function(bool value);

class VideoController with ChangeNotifier {
  final LiveRoom room;
  String datasource;
  List<String> playUrs;
  final bool allowScreenKeepOn;
  final bool allowFullScreen;
  final Map<String, String> headers;
  final isVertical = false.obs;

  ScreenBrightness? _brightnessController;
  ScreenBrightness? get brightnessController {
    if (!Platform.isAndroid && !Platform.isIOS) return null;
    _brightnessController ??= ScreenBrightness();
    return _brightnessController;
  }

  double initBrightness = 0.0;

  final String qualiteName;

  final int currentLineIndex;

  final int currentQuality;

  final bool isAudioOnly;

  final AudioOnlyCallback? onAudioOnlyChanged;

  bool get supportWindowFull => Platform.isWindows || Platform.isLinux;

  late final VolumeController _volumeController;

  late final StreamSubscription<double> _subscription;

  GlobalKey<BrightnessVolumnDargAreaState> brightnessKey = GlobalKey<BrightnessVolumnDargAreaState>();

  LivePlayController livePlayController = Get.find<LivePlayController>();

  StreamSubscription<PlayerException>? _errorSub;
  StreamSubscription<bool>? _pipSub;
  Timer? showControllerTimer;
  final showController = true.obs;
  /// 弹幕输入框是否正在编辑（全屏控制条内输入时保持控制条可见）。
  final inputEditing = false.obs;
  final showLocked = false.obs;
  final danmuKey = GlobalKey();
  final isMenuOpen = false.obs;
  GlobalKey playerKey = GlobalKey();

  Timer? _debounceTimer;
  Timer? _hideVolumeTimer;
  var showVolume = false.obs;

  void updateVolumn(double volume) {
    _hideVolumeTimer?.cancel();
    showVolume = true.obs;
    _hideVolumeTimer = Timer(const Duration(seconds: 1), () {
      showVolume.value = false;
    });
  }

  void enableController() {
    showControllerTimer?.cancel();
    showControllerTimer = Timer(const Duration(seconds: 2), () {
      if (!inputEditing.value) {
        showController.value = false;
      }
    });
    showController.value = true;
  }

  void stopHideController() {
    showControllerTimer?.cancel();
  }

  final hideDanmaku = false.obs;
  final danmakuArea = 0.7.obs;
  final danmakuTopArea = 0.0.obs;
  final danmakuBottomArea = 0.0.obs;
  final danmakuSpeed = 100.0.obs;
  final danmakuFontSize = 16.0.obs;
  final danmakuFontBorder = 4.obs;
  final danmakuOpacity = 0.7.obs;
  final enableDanmakuStroke = true.obs;
  final danmakuFps = 60.obs;
  final danmakuFontFamilyName = ''.obs;
  VideoController({
    required this.room,
    required this.datasource,
    required this.headers,
    required this.playUrs,
    this.allowScreenKeepOn = false,
    this.allowFullScreen = true,
    BoxFit fitMode = BoxFit.contain,
    required this.qualiteName,
    required this.currentLineIndex,
    required this.currentQuality,
    required this.isAudioOnly,
    this.onAudioOnlyChanged,
  }) {
    danmakuController = BarrageController();

    hideDanmaku.value = SettingsService.to.danmaku.hideDanmaku.v;
    danmakuTopArea.value = SettingsService.to.danmaku.danmakuTopArea.v;
    danmakuBottomArea.value = SettingsService.to.danmaku.danmakuBottomArea.v;
    danmakuSpeed.value = SettingsService.to.danmaku.danmakuSpeed.v;
    danmakuFontSize.value = SettingsService.to.danmaku.danmakuFontSize.v;
    danmakuFontBorder.value = SettingsService.to.danmaku.danmakuFontBorder.v.toInt();
    danmakuOpacity.value = SettingsService.to.danmaku.danmakuOpacity.v;
    enableDanmakuStroke.value = SettingsService.to.danmaku.enableDanmakuStroke.v;
    danmakuFontFamilyName.value = SettingsService.to.danmaku.danmakuFontFamilyName.v;
    initPagesConfig();
  }

  void initPagesConfig() {
    if (allowScreenKeepOn) WakelockPlus.enable();
    initVideoController();
    initDanmaku();
    initBattery();
  }

  void toggleAudioOnly() async {
    _errorSub?.cancel();
    _errorSub = null;
    _pipSub?.cancel();
    _pipSub = null;
    GlobalPlayerService.instance.playerManager.hardDispose();
    await destory();
    onAudioOnlyChanged?.call(!isAudioOnly);
  }

  // Battery level control
  final Battery _battery = Battery();
  final batteryLevel = 100.obs;

  late BarrageController danmakuController;

  void initBattery() {
    if (Platform.isAndroid || Platform.isIOS) {
      _battery.batteryLevel.then((value) => batteryLevel.value = value);
      _battery.onBatteryStateChanged.listen((BatteryState state) async {
        batteryLevel.value = await _battery.batteryLevel;
      });
    }
  }

  void initPlayerListener() {
    final manager = GlobalPlayerService.instance.playerManager;
    _errorSub?.cancel();
    _errorSub = manager.onError.listen((error) {
      log('error: ${error.toString()}', name: 'initPlayerListener');
      _handlePlayerError(error);
    });
  }

  void _handlePlayerError(PlayerException error) {
    switch (error.type) {
      case PlayerErrorType.network:
        ToastUtil.show(i18n("error_network"));
        break;
      case PlayerErrorType.source:
        ToastUtil.show(i18n("error_source"));
        break;
      case PlayerErrorType.codec:
        ToastUtil.show(i18n("error_codec"));
        break;
      case PlayerErrorType.native:
        ToastUtil.show(i18n("error_native"));
        break;
      case PlayerErrorType.initialization:
        ToastUtil.show(i18n("error_initialization"));
        break;
      case PlayerErrorType.texture:
        ToastUtil.show(i18n("error_texture"));
        break;
      case PlayerErrorType.lifecycle:
        ToastUtil.show(i18n("error_lifecycle"));
        break;
      case PlayerErrorType.unknown:
        ToastUtil.show(i18n("error_unknown"));
        break;
    }
  }



  void initVideoController() async {
    final playerManager = GlobalPlayerService.instance.playerManager;
    if (PlatformUtils.isMobile) {
      _volumeController = VolumeController.instance;
      _volumeController.showSystemUI = false;
      registerVolumeListener();
      final currentVolume = await _volumeController.getVolume();
      if (currentVolume > 0.001) {
        final targetVolume = room.getSavedVolume();
        _volumeController.setVolume(targetVolume);
      }
    }
    playerManager.play(datasource, playUrs, headers, room: room, audioOnly: isAudioOnly);
    initPlayerListener();
    // 处理默认全屏

    Future.delayed(Duration(milliseconds: 1000), () {
      if (SettingsService.to.app.enableFullScreenDefault.v) {
        livePlayController.setFullScreen();
        enterFullScreen();
        GlobalPlayerState.to.isFullscreen.value = true;
        enableController();
      }
    });

  }

  void retryRoom() async {
    var liveRoom = await Sites.of(
      room.platform!,
    ).liveSite.getRoomDetail(roomId: room.roomId!, platform: room.platform!);
    if (liveRoom.liveStatus == LiveStatus.offline) {
      livePlayController.setNormalScreen();
      ToastUtil.show(i18n("room_offline"));
    } else {
      changeLine();
    }
  }

  void debounceListen(Function? func, [int delay = 1000]) {
    if (_debounceTimer != null) {
      _debounceTimer?.cancel();
    }
    _debounceTimer = Timer(Duration(milliseconds: delay), () {
      func?.call();
      _debounceTimer = null;
    });
  }

  void initDanmaku() {
    final dm = SettingsService.to.danmaku;

    hideDanmaku.value = dm.hideDanmaku.v;
    ever<bool>(hideDanmaku, (data) {
      dm.hideDanmaku.v = data;
    });

    danmakuArea.value = dm.danmakuArea.v;
    danmakuTopArea.value = dm.danmakuTopArea.v;
    danmakuBottomArea.value = dm.danmakuBottomArea.v;
    danmakuSpeed.value = dm.danmakuSpeed.v;
    danmakuFontSize.value = dm.danmakuFontSize.v;
    danmakuFontBorder.value = dm.danmakuFontBorder.v.toInt();
    danmakuOpacity.value = dm.danmakuOpacity.v;
    enableDanmakuStroke.value = dm.enableDanmakuStroke.v;
    danmakuFps.value = dm.danmakuFps.v;
    final List<Rx> visualProperties = [
      danmakuArea,
      danmakuTopArea,
      danmakuBottomArea,
      danmakuSpeed,
      danmakuFontSize,
      danmakuFontBorder,
      danmakuOpacity,
      enableDanmakuStroke,
      danmakuFps,
    ];

    for (final rxProperty in visualProperties) {
      ever(rxProperty, (_) => updateDanmaku());
    }

    ever<double>(danmakuArea, (v) => dm.danmakuArea.v = v);
    ever<double>(danmakuTopArea, (v) => dm.danmakuTopArea.v = v);
    ever<double>(danmakuBottomArea, (v) => dm.danmakuBottomArea.v = v);
    ever<double>(danmakuSpeed, (v) => dm.danmakuSpeed.v = v);
    ever<double>(danmakuFontSize, (v) => dm.danmakuFontSize.v = v);
    ever<int>(danmakuFontBorder, (v) => dm.danmakuFontBorder.v = v.toDouble());
    ever<double>(danmakuOpacity, (v) => dm.danmakuOpacity.v = v);
    ever<bool>(enableDanmakuStroke, (v) => dm.enableDanmakuStroke.v = v);
    ever<int>(danmakuFps, (v) => dm.danmakuFps.v = v);
  }

  void updateDanmaku() {
    danmakuController.updateConfig(
      BarrageConfig(
        fontSize: danmakuFontSize.value,
        area: danmakuArea.value,
        topAreaDistance: danmakuTopArea.value,
        bottomAreaDistance: danmakuBottomArea.value,
        baseSpeed: danmakuSpeed.value,
        opacity: danmakuOpacity.value,
        fontWeight: FontWeight.values[danmakuFontBorder.value],
        showStroke: enableDanmakuStroke.value,
        fps: danmakuFps.value,
      ),
    );
  }

  void sendDanmaku(LiveMessage msg) {
    if (hideDanmaku.value) return;
    if (GlobalPlayerService.instance.playerManager.isPlayingNow) {
      danmakuController.send(
        BarrageItem(content: msg.message, textColor: Color.fromARGB(255, msg.color.r, msg.color.g, msg.color.b)),
      );
    }
  }


  @override
  void dispose() async {
    _errorSub?.cancel();
    _errorSub = null;
    _pipSub?.cancel();
    _pipSub = null;
    showControllerTimer?.cancel();
    _debounceTimer?.cancel();
    _hideVolumeTimer?.cancel();
    await destory();
    super.dispose();
  }

  void refresh() async {
    _errorSub?.cancel();
    _errorSub = null;
    _pipSub?.cancel();
    _pipSub = null;
    GlobalPlayerService.instance.playerManager.close();
    await destory();
    livePlayController.onInitPlayerState(reloadDataType: ReloadDataType.refreash);
  }

  void clearListener() {
    _errorSub?.cancel();
    _errorSub = null;
    _pipSub?.cancel();
    _pipSub = null;
  }

  void changeLine() async {
    _errorSub?.cancel();
    _errorSub = null;
    _pipSub?.cancel();
    _pipSub = null;

    GlobalPlayerService.instance.playerManager.close();
    await destory();
    livePlayController.onInitPlayerState(reloadDataType: ReloadDataType.changeLine, line: currentLineIndex);
  }

  Future<void> destory() async {
    if (Platform.isAndroid || Platform.isIOS) {
      if (allowScreenKeepOn) WakelockPlus.disable();
      unawaited(_subscription.cancel());
      _volumeController.removeListener();
    }
  }

  void setVideoFit(int index) {
    GlobalPlayerService.instance.playerManager.changeVideoFit(index);
  }

  /// 手机进入全屏强制横屏、退出恢复竖屏；平板始终横屏。
  Future<void> _updateOrientationForFullscreen(bool entering) async {
    try {
      final size = MediaQuery.of(Get.context!).size;
      final bool isTablet = size.shortestSide >= 600;
      if (isTablet) {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else if (entering) {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      }
    } catch (_) {}
  }

  Future<void> exitFullScreen() async {
    // 立即同步复位全屏状态，避免异步切换方向/系统UI期间返回键被反复拦截
    GlobalPlayerState.to.isFullscreen.value = false;
    await _updateOrientationForFullscreen(false);
    // 退出全屏时恢复系统状态栏/导航栏显示。
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void toggleFullScreen() async {
    showLocked.value = false;
    showControllerTimer?.cancel();
    GlobalPlayerState.to.isWindowFullscreen.value = false;
    Timer(const Duration(seconds: 2), () {
      enableController();
    });
    if (GlobalPlayerState.to.isFullscreen.value) {
      livePlayController.setNormalScreen();
      await exitFullScreen();
    } else {
      livePlayController.setFullScreen();
      await enterFullScreen();
    }
    enableController();
  }

  Future<void> enterFullScreen() async {
    GlobalPlayerState.to.isFullscreen.value = true;
    await _updateOrientationForFullscreen(true);
    // 全屏时隐藏系统状态栏/导航栏，沉浸式观看。
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  // 半屏显示
  void toggleWindowFullScreen() {
    showLocked.value = false;
    showControllerTimer?.cancel();
    Timer(const Duration(seconds: 2), () {
      enableController();
    });
    if (GlobalPlayerState.to.isWindowFullscreen.value) {
      livePlayController.setNormalScreen();
      GlobalPlayerState.to.isWindowFullscreen.value = false;
    } else {
      livePlayController.setWidescreen();
      GlobalPlayerState.to.isWindowFullscreen.value = true;
    }
    GlobalPlayerState.to.isFullscreen.value = false;
    enableController();
  }

  // 注册音量变化监听器
  void registerVolumeListener() {
    _subscription = _volumeController.addListener((volume) {
      room.saveCurrentVolume(volume);
    }, fetchInitialVolume: true);
  }

  // volume & brightness
  Future<double?> volume() async {
    if (Platform.isWindows) {
      return room.getSavedVolume();
    }
    return await _volumeController.getVolume();
  }

  Future<double> brightness() async {
    if (Platform.isAndroid || Platform.isIOS) {
      return await brightnessController!.application;
    }
    throw Exception('Brightness not supported on this platform');
  }

  void setVolume(double value) async {
    if (Platform.isWindows) {
      GlobalPlayerService.instance.playerManager.setVolume(value);
    } else {
      await _volumeController.setVolume(value);
    }
    room.saveCurrentVolume(value);
  }

  void setBrightness(double value) async {
    if (Platform.isAndroid || Platform.isIOS) {
      await brightnessController!.setApplicationScreenBrightness(value);
    }
  }
}
