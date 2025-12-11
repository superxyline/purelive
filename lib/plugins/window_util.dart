import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';

class WindowUtil {
  static String title = '纯粹直播';
  static Future<void> init({required double width, required double height}) async {
    double? windowsWidth = HivePrefUtil.getDouble('windowsWidth') ?? width;
    double? windowsHeight = HivePrefUtil.getDouble('windowsHeight') ?? height;
    WindowOptions windowOptions = WindowOptions(
      size: Size(windowsWidth, windowsHeight),
      center: false,
      minimumSize: Size(400, 400),
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  static Future<void> setTitle() async {
    await windowManager.setTitle(title);
  }

  static Future<void> setWindowsPort() async {
    double? windowsXPosition = HivePrefUtil.getDouble('windowsXPosition') ?? 0.0;
    double? windowsYPosition = HivePrefUtil.getDouble('windowsYPosition') ?? 0.0;
    double? windowsWidth = HivePrefUtil.getDouble('windowsWidth') ?? 900;
    double? windowsHeight = HivePrefUtil.getDouble('windowsHeight') ?? 535;
    windowsWidth = windowsWidth > 400 ? windowsWidth : 400;
    windowsHeight = windowsHeight > 400 ? windowsHeight : 400;
    await windowManager.setBounds(Rect.fromLTWH(windowsXPosition, windowsYPosition, windowsWidth, windowsHeight));
  }

  static void setPosition() async {
    Offset offset = await windowManager.getPosition();
    Size size = await windowManager.getSize();
    bool isFocused = await windowManager.isFocused();
    if (isFocused) {
      HivePrefUtil.setDouble('windowsXPosition', offset.dx);
      HivePrefUtil.setDouble('windowsYPosition', offset.dy);
      HivePrefUtil.setDouble('windowsWidth', size.width);
      HivePrefUtil.setDouble('windowsHeight', size.height);
    }
  }
}
