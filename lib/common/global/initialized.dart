import 'dart:io';
import 'app_path_manager.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/utils/global.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/common/global/initial_services.dart';
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
    await EasyLocalization.ensureInitialized();

    final String instanceId = _getInstanceIdFromArgs(args);

    await AppPathManager().initialize(instanceId: instanceId);
    final Directory hiveDir = await AppPathManager().getDir(AppPathManager.dirHiveDB);

    await Future.wait([
      Hive.initFlutter(hiveDir.path).then((_) => HivePrefUtil.init()),
      CustomImageCacheManager.initialize(),
    ]);

    InitialServices.init();
    _initSmartDialog();
    initRefresh();

    await MobileManager.initialize();

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

  void _initSmartDialog() {
    SmartDialog.config.toast = SmartConfigToast(
      displayTime: const Duration(milliseconds: 3000),
      intervalTime: const Duration(milliseconds: 100),
    );
  }
}
