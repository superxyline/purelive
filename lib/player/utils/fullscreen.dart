import 'dart:io';

import 'package:flutter/services.dart';

import 'package:pure_live/common/index.dart';

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

  // 手机：竖屏；平板：保持横屏。
  Future<void> setPortraitOrTabletLandscape() async {
    if (isTablet()) {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    } else {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
    }
  }
}
