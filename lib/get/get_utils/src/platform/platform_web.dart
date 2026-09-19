// vendored GetX 补充的 web 实现（原仓库仅携带了 io 版本）
// ignore: avoid_classes_with_only_static_members
class GeneralPlatform {
  static bool get isWeb => true;

  static bool get isMacOS => false;

  static bool get isWindows => false;

  static bool get isLinux => false;

  static bool get isAndroid => false;

  static bool get isIOS => false;

  static bool get isFuchsia => false;

  static bool get isDesktop => false;
}
