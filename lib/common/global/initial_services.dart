import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/live_play/player_state.dart';
import 'package:pure_live/modules/esports/esports_controller.dart';
import 'package:pure_live/routes/route_observer_controller.dart';
import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';

class InitialServices {
  static void initGlobalServices() {
    Get.put(SettingsService(), permanent: true);
    Get.put(RouteObserverController(), permanent: true);
  }

  static void initLazyControllers() {
    // 关注
    Get.lazyPut(() => FavoriteController(), fenix: true);
    // 热门
    Get.lazyPut(() => PopularController(), fenix: true);
    // 分区
    Get.lazyPut(() => AreasController(), fenix: true);
    // 赛事
    Get.lazyPut(() => EsportsController(), fenix: true);
    // 播放器状态
    Get.lazyPut(() => GlobalPlayerState(), fenix: true);
  }

  static Future<void> init() async {
    initGlobalServices();
    initLazyControllers();
    _initHeavyServicesInBackground();
  }

  static void _initHeavyServicesInBackground() {
    Future.delayed(const Duration(seconds: 3), () {
      try {
        FFmpegKitExtended.initialize();
      } catch (_) {}
    });
  }
}
