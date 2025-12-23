import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:auto_orientation_v2/auto_orientation_v2.dart';

//横屏
Future<void> landScape() async {
  dynamic document;
  try {
    if (kIsWeb) {
      await document.documentElement?.requestFullscreen();
    } else if (Platform.isAndroid || Platform.isIOS) {
      await AutoOrientation.landscapeAutoMode(forceSensor: true);
    } else if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      await windowManager.setHasShadow(false); // 去掉阴影
      await windowManager.setAsFrameless(); // 设置为无边框模式
      await windowManager.setFullScreen(true);
      // 1. 獲取目前視窗的中心點
      Rect windowRect = await windowManager.getBounds();
      Offset center = windowRect.center;

      // 2. 獲取所有顯示器
      List<Display> displays = await screenRetriever.getAllDisplays();

      // 3. 尋找視窗中心點在哪個顯示器範圍內
      Display currentDisplay = displays.firstWhere((display) {
        // 注意：這裡使用 visiblePosition 或 bounds.topLeft
        final Offset origin = display.visiblePosition ?? Offset.zero;
        final Size size = display.size;

        return center.dx >= origin.dx &&
            center.dx <= origin.dx + size.width &&
            center.dy >= origin.dy &&
            center.dy <= origin.dy + size.height;
      }, orElse: () => displays.first);

      // 4. 根據找到的螢幕設定全螢幕範圍
      await windowManager.setBounds(
        Rect.fromLTWH(
          currentDisplay.visiblePosition!.dx,
          currentDisplay.visiblePosition!.dy,
          currentDisplay.size.width,
          currentDisplay.size.height,
        ),
      );

      await windowManager.setAlwaysOnTop(false);
    }
  } catch (exception, stacktrace) {
    debugPrint(exception.toString());
    debugPrint(stacktrace.toString());
  }
}

//竖屏
Future<void> verticalScreen() async {
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
}

Future<void> doEnterFullScreen() async {
  if (Platform.isAndroid || Platform.isIOS) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  } else {
    await windowManager.setHasShadow(false); // 去掉阴影
    await windowManager.setAsFrameless(); // 设置为无边框模式
    await windowManager.setFullScreen(true);
    // 1. 獲取目前視窗的中心點
    Rect windowRect = await windowManager.getBounds();
    Offset center = windowRect.center;

    // 2. 獲取所有顯示器
    List<Display> displays = await screenRetriever.getAllDisplays();

    // 3. 尋找視窗中心點在哪個顯示器範圍內
    Display currentDisplay = displays.firstWhere((display) {
      // 注意：這裡使用 visiblePosition 或 bounds.topLeft
      final Offset origin = display.visiblePosition ?? Offset.zero;
      final Size size = display.size;

      return center.dx >= origin.dx &&
          center.dx <= origin.dx + size.width &&
          center.dy >= origin.dy &&
          center.dy <= origin.dy + size.height;
    }, orElse: () => displays.first);

    // 4. 根據找到的螢幕設定全螢幕範圍
    await windowManager.setBounds(
      Rect.fromLTWH(
        currentDisplay.visiblePosition!.dx,
        currentDisplay.visiblePosition!.dy,
        currentDisplay.size.width,
        currentDisplay.size.height,
      ),
    );
    await windowManager.setAlwaysOnTop(false);
  }
}

//退出全屏显示
Future<void> doExitFullScreen() async {
  dynamic document;
  late SystemUiMode mode = SystemUiMode.edgeToEdge;
  try {
    if (kIsWeb) {
      document.exitFullscreen();
    } else if (Platform.isAndroid || Platform.isIOS) {
      if (Platform.isAndroid && (await DeviceInfoPlugin().androidInfo).version.sdkInt < 29) {
        mode = SystemUiMode.manual;
      }
      await SystemChrome.setEnabledSystemUIMode(mode, overlays: SystemUiOverlay.values);
      await SystemChrome.setPreferredOrientations([]);
    } else if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      await windowManager.setFullScreen(false);
      await windowManager.setHasShadow(true);
      await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    }
  } catch (exception, stacktrace) {
    debugPrint(exception.toString());
    debugPrint(stacktrace.toString());
  }
}
