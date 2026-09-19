import 'dart:async';

import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/consts/app_consts.dart';
import 'package:pure_live/common/global/platform_utils.dart';

class AppSettingsController extends GetxController {
  static const int maxSleepMinutes = 525600;
  static const List<String> defaultRealOnlinePlatforms = ['douyin'];

  /// 定制版保留的平台（真实在线人数开关只对这些平台生效）
  static const List<String> supportedRealOnlinePlatforms = ['bilibili', 'douyu', 'huya', 'douyin'];

  Worker? _highRefreshRateWorker;

  final RxBool enableDenseFavorites = hiveBool('enableDenseFavorites', true);
  final RxBool showLiveDurationBadge = hiveBool('showLiveDurationBadge', true);
  final RxBool showRoomInfoOsd = hiveBool('showRoomInfoOsd', false);
  final RxBool enableBackgroundPlay = hiveBool('enableBackgroundPlay', false);
  final RxBool enableAsmrSleepMode = hiveBool('enableAsmrSleepMode', false);
  final RxInt asmrSleepMinutes = hiveInt('asmrSleepMinutes', 60);
  final RxBool enableScreenKeepOn = hiveBool('enableScreenKeepOn', true);

  final RxBool enableAutoCheckUpdate = hiveBool('enableAutoCheckUpdate', true);
  /// 更新提醒里用户选择"忽略此版本"时记录的构建号：不再对该构建号弹提醒
  final RxInt updateIgnoredBuild = hiveInt('updateIgnoredBuild', 0);
  /// 赛事提醒提前分钟数（关注的赛事开始前提前多久通知）
  final RxInt esportsReminderLeadMinutes = hiveInt('esportsReminderLeadMinutes', 10);
  static const int maxEsportsReminderLeadMinutes = 120;
  final RxBool enableFullScreenDefault = hiveBool('enableFullScreenDefault', false);
  final RxBool showSplashPage = hiveBool('showSplashPage', true);
  final RxBool enableHighRefreshRate = hiveBool('enableHighRefreshRate', true);
  final RxBool preferRealOnlineCounts = hiveBool('preferRealOnlineCounts', false);
  late final RxList<String> realOnlinePlatforms = hiveStringList('realOnlinePlatforms', defaultRealOnlinePlatforms);

  late final RxList<String> savedMenuIds = hiveStringList('savedMenuIds', HomeMenu.values.map((e) => e.id).toList());

  @override
  void onInit() {
    super.onInit();
    _removeUnsupportedOnlinePlatforms();
    if (PlatformUtils.isAndroid) {
      unawaited(DisplayModeService.setHighRefreshRate(enableHighRefreshRate.v));
      _highRefreshRateWorker = ever<bool>(
        enableHighRefreshRate,
        (enabled) => unawaited(DisplayModeService.setHighRefreshRate(enabled)),
      );
    } else if (PlatformUtils.isWindows) {
      // Flutter follows the active Windows monitor's vsync. The native runner
      // reports that monitor's current/supported modes and pushes updates when
      // the window moves between displays or Windows changes display mode.
      unawaited(DisplayModeService.refreshInfo());
    }
  }

  void _removeUnsupportedOnlinePlatforms() {
    final supported = normalizeRealOnlinePlatforms(realOnlinePlatforms);
    if (supported.length != realOnlinePlatforms.length) {
      realOnlinePlatforms.v = supported;
    }
  }

  static List<String> normalizeRealOnlinePlatforms(Iterable<String> platforms) {
    return platforms
        .where((platform) =>
            LiveRoom.audienceCapabilityFor(platform).supportsConcurrentOnline &&
            supportedRealOnlinePlatforms.contains(platform))
        .toSet()
        .toList();
  }

  @override
  void onClose() {
    _highRefreshRateWorker?.dispose();
    _highRefreshRateWorker = null;
    super.onClose();
  }

  void toggleMenuVisibility(HomeMenu menu, bool visible) {
    final ids = List<String>.from(savedMenuIds.v);
    if (visible) {
      if (!ids.contains(menu.id)) ids.add(menu.id);
    } else {
      ids.removeWhere((id) => id == menu.id);
    }
    savedMenuIds.v = ids;
  }

  bool isRealOnlineEnabledFor(String? platform) => realOnlinePlatforms.contains(platform);

  void setRealOnlineEnabledFor(String platform, bool enabled) {
    if (!LiveRoom.audienceCapabilityFor(platform).supportsConcurrentOnline) return;
    final next = List<String>.from(realOnlinePlatforms);
    if (enabled) {
      if (!next.contains(platform)) next.add(platform);
    } else {
      next.remove(platform);
    }
    realOnlinePlatforms.v = next;
  }

  // ======================
  // 备份/恢复
  // ======================
  Map<String, dynamic> toJson() {
    return {
      'enableDenseFavorites': enableDenseFavorites.v,
      'showLiveDurationBadge': showLiveDurationBadge.v,
      'showRoomInfoOsd': showRoomInfoOsd.v,
      'enableBackgroundPlay': enableBackgroundPlay.v,
      'enableAsmrSleepMode': enableAsmrSleepMode.v,
      'asmrSleepMinutes': asmrSleepMinutes.v,
      'enableScreenKeepOn': enableScreenKeepOn.v,
      'enableAutoCheckUpdate': enableAutoCheckUpdate.v,
      'updateIgnoredBuild': updateIgnoredBuild.v,
      'esportsReminderLeadMinutes': esportsReminderLeadMinutes.v,
      'enableFullScreenDefault': enableFullScreenDefault.v,
      'showSplashPage': showSplashPage.v,
      'enableHighRefreshRate': enableHighRefreshRate.v,
      'preferRealOnlineCounts': preferRealOnlineCounts.v,
      'realOnlinePlatforms': realOnlinePlatforms.v,
      'savedMenuIds': savedMenuIds.v,
    };
  }

  void fromJson(Map<String, dynamic> json) {
    enableDenseFavorites.v = json['enableDenseFavorites'] ?? true;
    showLiveDurationBadge.v = json['showLiveDurationBadge'] ?? true;
    showRoomInfoOsd.v = json['showRoomInfoOsd'] ?? false;
    enableBackgroundPlay.v = json['enableBackgroundPlay'] ?? false;
    enableAsmrSleepMode.v = json['enableAsmrSleepMode'] ?? false;
    asmrSleepMinutes.v = (((json['asmrSleepMinutes'] as num?)?.toInt() ?? 60).clamp(1, maxSleepMinutes)).toInt();
    enableScreenKeepOn.v = json['enableScreenKeepOn'] ?? true;
    enableAutoCheckUpdate.v = json['enableAutoCheckUpdate'] ?? true;
    updateIgnoredBuild.v = ((json['updateIgnoredBuild'] as num?)?.toInt() ?? 0).clamp(0, 1 << 30);
    esportsReminderLeadMinutes.v = (((json['esportsReminderLeadMinutes'] as num?)?.toInt() ?? 10)
        .clamp(1, maxEsportsReminderLeadMinutes))
        .toInt();
    enableFullScreenDefault.v = json['enableFullScreenDefault'] ?? false;
    showSplashPage.v = json['showSplashPage'] ?? true;
    enableHighRefreshRate.v = json['enableHighRefreshRate'] ?? true;
    preferRealOnlineCounts.v = json['preferRealOnlineCounts'] ?? false;
    realOnlinePlatforms.v = List<String>.from(json['realOnlinePlatforms'] ?? defaultRealOnlinePlatforms);
    _removeUnsupportedOnlinePlatforms();
    savedMenuIds.v = List<String>.from(json['savedMenuIds'] ?? HomeMenu.values.map((e) => e.id).toList());
  }

  static Map<String, dynamic> extractConfig(Map<String, dynamic>? rootConfig) {
    final app = rootConfig?['app'] as Map<String, dynamic>? ?? {};
    return {
      'enableDenseFavorites': app['enableDenseFavorites'] ?? true,
      'showLiveDurationBadge': app['showLiveDurationBadge'] ?? true,
      'enableBackgroundPlay': app['enableBackgroundPlay'] ?? false,
      'enableAsmrSleepMode': app['enableAsmrSleepMode'] ?? false,
      'asmrSleepMinutes': (((app['asmrSleepMinutes'] as num?)?.toInt() ?? 60).clamp(1, maxSleepMinutes)).toInt(),
      'enableScreenKeepOn': app['enableScreenKeepOn'] ?? true,
      'enableAutoCheckUpdate': app['enableAutoCheckUpdate'] ?? true,
      'esportsReminderLeadMinutes': (((app['esportsReminderLeadMinutes'] as num?)?.toInt() ?? 10)
          .clamp(1, maxEsportsReminderLeadMinutes))
          .toInt(),
      'enableFullScreenDefault': app['enableFullScreenDefault'] ?? false,
      'showSplashPage': app['showSplashPage'] ?? true,
      'enableHighRefreshRate': app['enableHighRefreshRate'] ?? true,
      'preferRealOnlineCounts': app['preferRealOnlineCounts'] ?? false,
      'realOnlinePlatforms': normalizeRealOnlinePlatforms(
        List<String>.from(app['realOnlinePlatforms'] ?? defaultRealOnlinePlatforms),
      ),
      'savedMenuIds': List<String>.from(app['savedMenuIds'] ?? []),
    };
  }

  static Map<String, dynamic> mergeConfig(Map<String, dynamic> rootConfig, Map<String, dynamic> updateFields) {
    final app = Map<String, dynamic>.from(rootConfig['app'] ?? {});
    updateFields.forEach((k, v) => app[k] = v);
    rootConfig['app'] = app;
    return rootConfig;
  }
}
