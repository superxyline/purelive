import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/player/utils/window_helper.dart';
import 'package:pure_live/common/global/platform/mobile_manager.dart';
import 'package:pure_live/modules/live_play/controllers/player_state.dart';
import 'package:pure_live/modules/live_play/controllers/live_play_controller.dart';

class WindowService {
  static final WindowService _instance = WindowService._internal();
  factory WindowService() => _instance;
  WindowService._internal();
  Future<void> enterWinPiP(double videoRatio) async {
    if (!Platform.isWindows) return;
    if (GlobalPlayerState.to.isFullscreen.value) {
      final livePlayController = Get.find<LivePlayController>();
      final videoController = livePlayController.state.value.player.videoController;
      videoController?.toggleFullScreen();
    }
    Future.microtask(() {
      WindowHelper.instance.enterPiP(videoRatio);
    });
  }

  Future<void> exitWinPiP() async {
    if (!Platform.isWindows) return;
    WindowHelper.instance.exitPiP();
  }

  //横屏
  Future<void> landScape() async {
    dynamic document;
    try {
      if (kIsWeb) {
        await document.documentElement?.requestFullscreen();
      } else if (Platform.isAndroid || Platform.isIOS) {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        await doEnterWindowFullScreen();
      }
    } catch (exception, stacktrace) {
      debugPrint(exception.toString());
      debugPrint(stacktrace.toString());
    }
  }

  //竖屏/恢复竖屏：手机恢复竖屏（portraitUp/portraitDown）；平板保持横屏（全程横屏）。
  Future<void> verticalScreen() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await setPortraitOrTabletLandscape();
  }

  // 平板判定：物理尺寸 shortestSide/dpr >= 600 视为平板（与 mobile_manager 一致）。
  static bool isTablet() {
    try {
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      final dpr = view.devicePixelRatio;
      if (dpr <= 0) return false;
      return (view.physicalSize.shortestSide / dpr).round() >= 600;
    } catch (_) {
      return false;
    }
  }

  // 手机：竖屏（portraitUp/portraitDown）；平板：保持横屏。
  Future<void> setPortraitOrTabletLandscape() async {
    if (isTablet()) {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    } else {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
    }
  }

  Future<void> doEnterFullScreen() async {
    if (Platform.isAndroid || Platform.isIOS) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await doEnterWindowFullScreen();
    }
  }

  //退出全屏显示
  Future<void> doExitFullScreen() async {
    dynamic document;
    try {
      if (kIsWeb) {
        document.exitFullscreen();
      } else if (Platform.isAndroid || Platform.isIOS) {
        // 退出全屏恢复系统状态栏/导航栏（edge-to-edge 下小米手势条半透明正常显示，不被强制实心条遮挡）。
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        await Future.microtask(() {});
        // 恢复完整系统栏样式：导航栏必须显式保持透明，否则 Flutter 会把未提供的
        // 字段重置为默认值（导航栏默认黑色，导致小米平板 HyperOS 横屏底部黑条）。
        MobileManager.setStatusBarStyle(isDarkTheme: Get.isDarkMode);
        // 退出全屏恢复竖屏；平板保持横屏（不再放开为四方向自由）。
        await setPortraitOrTabletLandscape();
      } else if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        await doExitWindowFullScreen();
      }
    } catch (exception, stacktrace) {
      debugPrint(exception.toString());
      debugPrint(stacktrace.toString());
    }
  }

  Future<void> doExitWindowFullScreen() async {
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      await windowManager.setFullScreen(false);
    }
  }

  Future<void> doEnterWindowFullScreen({bool enableEscListener = true, VoidCallback? onEsc}) async {
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      await windowManager.setFullScreen(true);
    }
  }
}
