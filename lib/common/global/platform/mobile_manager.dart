import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pure_live/common/global/platform_utils.dart';
import 'package:pure_live/tv/core/tv_device_service.dart';

class MobileManager {
  static Future<void> initialize() async {
    if (!PlatformUtils.isMobile) return;

    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
          // Android 10+ 默认 enforceNavigationBarContrast=true，会给透明导航栏强制垫一层
          // 半透明白 scrim（小米平板 HyperOS 上表现为小白条下方一条"大白条"），必须显式关闭。
          systemNavigationBarContrastEnforced: false,
        ),
      );

      if (PlatformUtils.isIOS) {
        await _initializeIOS();
      }

      if (PlatformUtils.isAndroid) {
        await _initializeAndroid();
      }
    } catch (e) {
      debugPrint('移动端初始化失败: $e');
    }
  }

  static Future<void> _initializeIOS() async {
    try {
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarBrightness: Brightness.light,
          statusBarIconBrightness: Brightness.dark,
          statusBarColor: Colors.transparent,
        ),
      );
    } catch (e) {
      debugPrint('iOS 初始化失败: $e');
    }
  }

  static Future<void> _initializeAndroid() async {
    try {
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.dark,
          systemNavigationBarContrastEnforced: false,
        ),
      );

      // TV 恒横屏：电视不做「平板/手机」尺寸判定，一开始就锁死横屏。
      // 1080p 电视在 Android TV 上常报 320dpi（逻辑 960x540dp），会被尺寸判定
      // 误当成手机而放开四方向——之后任何一次竖屏恢复调用都能把电视转成竖屏。
      if (TvDeviceService.isTv) {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        return;
      }

      // 物理尺寸判定平板（shortestSide/dpr >= 600）：平板启动即锁横屏，实现全程横屏；
      // 手机保持四方向自由（现状）。
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      final dpr = view.devicePixelRatio;
      final bool isTablet = dpr > 0 && (view.physicalSize.shortestSide / dpr).round() >= 600;
      if (isTablet) {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      }
    } catch (e) {
      debugPrint('Android 初始化失败: $e');
    }
  }

  /// 应用移动端系统栏样式：状态栏与导航栏（手势条区）均透明，图标亮度随明暗主题。
  ///
  /// 这是"恢复系统栏"的统一入口：退出全屏、回到首页、退出直播间兜底等所有
  /// 恢复系统 UI 的时机都应调用它。不能用只含状态栏字段的 [SystemUiOverlayStyle]
  /// 覆盖（Flutter 会把未提供的字段重置为默认值，其中导航栏默认为黑色——在
  /// 小米平板 HyperOS 横屏等手势导航不做强制半透明补偿的设备上，底部小横条
  /// 区域就会显示成一条黑条）。
  static void setStatusBarStyle({required bool isDarkTheme}) {
    if (!PlatformUtils.isMobile) return;

    try {
      if (PlatformUtils.isIOS) {
        SystemChrome.setSystemUIOverlayStyle(
          SystemUiOverlayStyle(
            statusBarBrightness: isDarkTheme ? Brightness.dark : Brightness.light,
            statusBarIconBrightness: isDarkTheme ? Brightness.light : Brightness.dark,
            statusBarColor: Colors.transparent,
          ),
        );
      } else if (PlatformUtils.isAndroid) {
        SystemChrome.setSystemUIOverlayStyle(
          SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarDividerColor: Colors.transparent,
            // 每次恢复系统栏都要带上 false：该调用未提供的字段会被引擎按默认值重置，
            // 漏掉它的话小白条区域会重新出现系统强制的大白条。
            systemNavigationBarContrastEnforced: false,
            statusBarIconBrightness: isDarkTheme ? Brightness.light : Brightness.dark,
            systemNavigationBarIconBrightness: isDarkTheme ? Brightness.light : Brightness.dark,
          ),
        );
      }
    } catch (e) {
      debugPrint('状态栏样式设置失败: $e');
    }
  }
}
