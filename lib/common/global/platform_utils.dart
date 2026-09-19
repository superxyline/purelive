import 'package:flutter/material.dart';

import 'platform_env.dart';
import 'platform_env_io.dart' if (dart.library.js_interop) 'platform_env_web.dart' as env;

class PlatformUtils {
  PlatformUtils._();

  static const PlatformEnv _env = env.PlatformEnvImpl();

  /// 是否运行在浏览器（Flutter Web）端。
  static bool get isWeb => _env.isWeb;

  static bool get isDesktop => _env.isDesktop;

  static bool get isDesktopNotMac => _env.isDesktopNotMac;

  static bool get isMobile => _env.isMobile;

  static bool isMobileWidth(BuildContext context) {
    return MediaQuery.of(context).size.width < 760;
  }

  static bool get isWindows => _env.isWindows;
  static bool get isMacOS => _env.isMacOS;
  static bool get isLinux => _env.isLinux;
  static bool get isAndroid => _env.isAndroid;
  static bool get isIOS => _env.isIOS;

  /// 路径分隔符：io 平台取系统值，web 恒为 '/'。
  static String get pathSeparator => _env.pathSeparator;

  static T select<T>({required T desktop, required T mobile}) {
    return isDesktop ? desktop : mobile;
  }
}
