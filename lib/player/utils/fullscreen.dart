
import 'package:flutter/services.dart';

import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/global/platform/mobile_manager.dart';
import 'package:pure_live/tv/core/tv_device_service.dart';

/// 直播间退出兜底：任何路径离开直播间后调用，恢复手机竖屏与系统栏，
/// 防止横屏沉浸状态泄漏到首页（表现为手机横屏显示直播间列表）。
/// 幂等，可重复调用，失败不影响页面退出流程。
Future<void> restoreMobileScreenAfterLeaveRoom() async {
  try {
    if (PlatformUtils.isDesktop) return;
    // TV 恒横屏：退出直播间不做竖屏恢复。电视上 Activity 未固定 screenOrientation，
    // 一旦下发竖屏锁定，界面会真的转成竖屏（手机布局）且没有路径恢复，只能杀进程。
    if (TvDeviceService.isTv) return;
    await WindowService().verticalScreen();
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    MobileManager.setStatusBarStyle(isDarkTheme: Get.isDarkMode);
  } catch (_) {
    // 恢复失败不应影响页面退出流程。
  }
}

class WindowService {
  static final WindowService _instance = WindowService._internal();
  factory WindowService() => _instance;
  WindowService._internal();

  //横屏：进入全屏时强制横屏（平板本就恒横屏）。
  Future<void> landScape() async {
    try {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } catch (exception, stacktrace) {
      debugPrint(exception.toString());
      debugPrint(stacktrace.toString());
    }
  }

  //竖屏/恢复竖屏：手机恢复竖屏；平板保持横屏。
  Future<void> verticalScreen() async {
    if (!PlatformUtils.isAndroid && !PlatformUtils.isIOS) return;
    await setPortraitOrTabletLandscape();
  }

  // 平板判定：物理尺寸 shortestSide/dpr >= 600 视为平板（与 mobile_manager 一致）。
  //
  // TV 必须先短路为 true（等价横屏）：1080p 电视在 Android TV 上普遍报 320dpi，
  // 逻辑尺寸 960x540dp，最短边 540 < 600 会被误判成「手机」，从而走进竖屏分支。
  // 电视的 Activity 没有固定 screenOrientation（configChanges 含 orientation），
  // 竖屏锁定会真实生效并停在竖屏，没有重建可自愈——必须靠这里拦住。
  static bool isTablet() {
    if (TvDeviceService.isTv) return true;
    try {
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      final dpr = view.devicePixelRatio;
      if (dpr <= 0) return false;
      return (view.physicalSize.shortestSide / dpr).round() >= 600;
    } catch (_) {
      return false;
    }
  }

  // 手机：竖屏；平板：保持横屏。
  Future<void> setPortraitOrTabletLandscape() async {
    if (isTablet()) {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    } else {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
    }
  }
}
