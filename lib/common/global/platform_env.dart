/// 平台环境契约：io/web 两套实现，由 [PlatformUtils] 通过条件导入选择。
abstract interface class PlatformEnv {
  bool get isWeb;
  bool get isDesktop;
  bool get isDesktopNotMac;
  bool get isMobile;
  bool get isWindows;
  bool get isMacOS;
  bool get isLinux;
  bool get isAndroid;
  bool get isIOS;
  String get pathSeparator;
}
