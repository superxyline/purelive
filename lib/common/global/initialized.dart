import 'dart:io';
import 'dart:developer';
import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/plugins/global.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
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
  Future<void> initialize(List<String> args) async {
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
    final appDir = await getApplicationDocumentsDirectory();
    String path = '${appDir.path}${Platform.pathSeparator}pure_live';
    await Hive.initFlutter(path);
    await HivePrefUtil.init();
    MediaKit.ensureInitialized();
    await SupaBaseManager.getInstance().initial();
    if (PlatformUtils.isDesktop) {
      await DesktopManager.postInitialize();
    }
    initRefresh();
    initService();

    if (PlatformUtils.isDesktopNotMac) {
      // FlutterSingleInstance may have issues in Release mode for macOS build，but it works fine in debug mode.
      if (!await FlutterSingleInstance().isFirstInstance()) {
        log("App is already running");
        final err = await FlutterSingleInstance().focus();
        if (err != null) {
          log("Error focusing running instance: $err");
        }
        exit(0);
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
