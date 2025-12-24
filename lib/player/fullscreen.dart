import 'dart:io';
import 'package:flutter/material.dart';
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
      await doEnterWindowFullScreen();
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
    await doEnterWindowFullScreen();
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

Future<void> doEnterWindowFullScreen() async {
  // 1. 先彻底移除装饰和阴影
  await windowManager.setHasShadow(false);
  await windowManager.setAsFrameless();
  // 建议增加：隐藏标题栏，防止 Windows 11 顶部出现细线
  await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);

  Rect windowRect = await windowManager.getBounds();
  Offset center = windowRect.center;
  List<Display> displays = await screenRetriever.getAllDisplays();

  Display currentDisplay = displays.firstWhere((display) {
    final Offset origin = display.visiblePosition ?? Offset.zero;
    final Size size = display.size;
    return center.dx >= origin.dx &&
        center.dx <= origin.dx + size.width &&
        center.dy >= origin.dy &&
        center.dy <= origin.dy + size.height;
  }, orElse: () => displays.first);

  final double x = currentDisplay.visiblePosition!.dx.floorToDouble();
  final double y = currentDisplay.visiblePosition!.dy.floorToDouble();
  final double width = currentDisplay.size.width.ceilToDouble();
  final double height = currentDisplay.size.height.ceilToDouble();

  await windowManager.setBounds(Rect.fromLTWH(x, y, width, height));

  if (Platform.isWindows) {
    await windowManager.setBackgroundColor(Colors.black);
  }

  await windowManager.setFullScreen(true);
  await windowManager.setAlwaysOnTop(false);
}
