import 'dart:io';
import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/plugins/global.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pure_live/common/global/platform_utils.dart';
import 'package:flutter_single_instance/flutter_single_instance.dart';
import 'package:pure_live/common/global/platform/mobile_manager.dart';
import 'package:pure_live/common/global/platform/desktop_manager.dart';
import 'package:pure_live/common/services/bilibili_account_service.dart';

class AppInitializer {
  // 单例实例
  static final AppInitializer _instance = AppInitializer._internal();

  // 是否已经初始化
  bool _isInitialized = false;

  // 工厂构造函数，返回单例
  factory AppInitializer() {
    return _instance;
  }

  // 私有构造函数
  AppInitializer._internal();

  // 初始化方法
  Future<void> initialize() async {
    if (_isInitialized) {
      // 已经初始化过，直接返回
      return;
    }

    // 执行初始化操作
    WidgetsFlutterBinding.ensureInitialized();
    if (PlatformUtils.isDesktop) {
      await DesktopManager.initialize();
    } else if (PlatformUtils.isMobile) {
      await MobileManager.initialize();
    }

    PrefUtil.prefs = await SharedPreferences.getInstance();
    MediaKit.ensureInitialized();
    await SupaBaseManager.getInstance().initial();
    if (PlatformUtils.isDesktop) {
      await DesktopManager.postInitialize();
    }
    initRefresh();
    initService();

    bool isInstanceInstalled = await FlutterSingleInstance().isFirstInstance();
    if (isInstanceInstalled) {
      await FlutterSingleInstance().focus();
    }
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    launchAtStartup.setup(
      appName: packageInfo.appName,
      appPath: Platform.resolvedExecutable,
      // 设置 packageName 参数以支持 MSIX。
      packageName: 'dev.leanflutter.puretech.pure_live',
    );
    var settings = Get.find<SettingsService>();
    if (settings.enableStartUp.value) {
      await launchAtStartup.isEnabled().then((value) {
        if (value) {
          launchAtStartup.enable();
        } else {
          launchAtStartup.disable();
        }
      });
    }
    // 标记为已初始化
    _isInitialized = true;
  }

  void initService() {
    Get.put(SettingsService());
    Get.put(AuthController());
    Get.put(FavoriteController());
    Get.put(BiliBiliAccountService());
    Get.put(PopularController());
    Get.put(AreasController());
  }

  // 检查是否已初始化
  bool get isInitialized => _isInitialized;
}
