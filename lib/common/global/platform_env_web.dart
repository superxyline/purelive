import 'platform_env.dart';

class PlatformEnvImpl implements PlatformEnv {
  const PlatformEnvImpl();

  @override
  bool get isWeb => true;

  @override
  bool get isDesktop => false;

  @override
  bool get isDesktopNotMac => false;

  @override
  bool get isMobile => false;

  @override
  bool get isWindows => false;

  @override
  bool get isMacOS => false;

  @override
  bool get isLinux => false;

  @override
  bool get isAndroid => false;

  @override
  bool get isIOS => false;

  @override
  String get pathSeparator => '/';
}
