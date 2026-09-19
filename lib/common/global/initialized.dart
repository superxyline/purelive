import 'dart:io';
import 'dart:developer';

import 'app_path_manager.dart';

import 'package:pure_live/common/index.dart';
import 'package:pure_live/plugins/global.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/common/global/platform_utils.dart';
import 'package:pure_live/common/global/initial_services.dart';
import 'package:pure_live/common/services/utils/settings_upgrade_migration.dart';
import 'package:pure_live/common/global/platform/mobile_manager.dart';

class AppInitializer {
  static final AppInitializer _instance = AppInitializer._internal();
  bool _isInitialized = false;

  factory AppInitializer() => _instance;
  AppInitializer._internal();

  bool get isInitialized => _isInitialized;

  Future<void> initialize(List<String> args) async {
    if (_isInitialized) return;

    WidgetsFlutterBinding.ensureInitialized();
    final String instanceId = _getInstanceIdFromArgs(args);

    await EasyLocalization.ensureInitialized();

    if (PlatformUtils.isWeb) {
      // Web 端：无文件系统，Hive 直接落 IndexedDB；跳过路径初始化与旧数据迁移。
      await Hive.initFlutter();
    } else {
      await AppPathManager().initialize(instanceId: instanceId);
      final Directory hiveDir = await AppPathManager().getDir(AppPathManager.dirHiveDB);

      await Hive.initFlutter(hiveDir.path);
      final migrationReport = await SettingsUpgradeMigration.migrate(
        target: Hive.box('app_settings'),
        legacyHiveFiles: AppPathManager().legacyHiveFiles,
        workingDirectory: await AppPathManager().migrationWorkingDir,
      );
      if (migrationReport.changed) {
        log(
          'Settings upgrade imported ${migrationReport.importedSources} source(s); '
          'favorites=${migrationReport.favoriteCount}, '
          'history=${migrationReport.historyCount}.',
        );
      }
    }
    await HivePrefUtil.init();

    // Settings and controller registration is a hard startup dependency for
    // MyApp.build.  Leaving this future detached created a first-launch race:
    // a freshly upgraded install could build the widget tree before
    // SettingsService was registered, then work on a later launch only because
    // the database/cache files had already been created.
    await InitialServices.init();
    _initSmartDialog();
    initRefresh();

    if (PlatformUtils.isDesktop) {
      if (Platform.isWindows) {
        _initWindowsScreenBrightness();
      }
    } else if (PlatformUtils.isMobile) {
      await MobileManager.initialize();
    }

    if (PlatformUtils.isDesktopNotMac && instanceId.isEmpty) {
      _setupLaunchAtStartupSafe();
    }

    _isInitialized = true;
  }

  String _getInstanceIdFromArgs(List<String> args) {
    for (final arg in args) {
      if (arg.startsWith('--instance=')) {
        final parts = arg.split('=');
        return parts.length > 1 ? parts[1] : '';
      }
    }
    return '';
  }

  void _initWindowsScreenBrightness() {
    ScreenBrightness().setAutoReset(false).catchError((e) {
      log('ScreenBrightness error: $e');
    });
  }

  Future<void> _setupLaunchAtStartupSafe() async {
    try {
      await SettingsService.to.startup.setupLaunchAtStartup();
    } catch (e) {
      log('Setup launch at startup failed: $e');
    }
  }

  void _initSmartDialog() {
    SmartDialog.config.toast = SmartConfigToast(
      displayTime: const Duration(milliseconds: 3000),
      intervalTime: const Duration(milliseconds: 100),
    );
  }
}
