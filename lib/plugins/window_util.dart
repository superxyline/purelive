import 'dart:developer';

import 'package:pure_live/common/utils/index.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter/material.dart';

class WindowUtil {
  static String title = '纯粹直播';
  static void init({required double width, required double height}) async {
    WindowOptions windowOptions =
        WindowOptions(size: Size(width, height), center: true,
        minimumSize: const Size(800, 600)
        );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
      double? windowsXPosition = PrefUtil.getDouble('windowsXPosition');
      double? windowsYPosition = PrefUtil.getDouble('windowsYPosition');
      double? windowsWidth = PrefUtil.getDouble('windowsWidth');
      double? windowsHeight = PrefUtil.getDouble('windowsHeight');
       log(windowsHeight.toString(),name: 'windowsHeight');
        log(windowsWidth.toString(),name: 'windowsWidth');
      await windowManager
          .setPosition(Offset(windowsXPosition!, windowsYPosition!));
      await windowManager
          .setSize(Size(windowsWidth ?? width, windowsHeight ?? height));
    });
  }

  static void setTitle() {
    windowManager.setTitle(title);
  }

  static void setPosition() async {
    Offset offset = await windowManager.getPosition();
    Size size = await windowManager.getSize();
    if (offset.dx > 0.0 && offset.dy > 0.0) {
      await PrefUtil.setDouble('windowsXPosition', offset.dx);
      await PrefUtil.setDouble('windowsYPosition', offset.dy);
    }
    if (size.width > 0.0 && size.height > 0.0) {
      await PrefUtil.setDouble('windowsWidth', size.width);
      await PrefUtil.setDouble('windowsHeight', size.height);
    }
  }
}
