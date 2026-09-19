import 'dart:io' show Platform;

import 'platform_env.dart';

class PlatformEnvImpl implements PlatformEnv {
  const PlatformEnvImpl();

  @override
  bool get isWeb => false;

  @override
  bool get isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  bool get isDesktopNotMac => (Platform.isWindows || Platform.isLinux) && !Platform.isMacOS;

  @override
  bool get isMobile => Platform.isAndroid || Platform.isIOS;

  @override
  bool get isWindows => Platform.isWindows;

  @override
  bool get isMacOS => Platform.isMacOS;

  @override
  bool get isLinux => Platform.isLinux;

  @override
  bool get isAndroid => Platform.isAndroid;

  @override
  bool get isIOS => Platform.isIOS;

  @override
  String get pathSeparator => Platform.pathSeparator;
}
