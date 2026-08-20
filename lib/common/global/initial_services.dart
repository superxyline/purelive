import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/modules/live_play/controllers/player_state.dart';
import 'package:pure_live/modules/live_play/local_interaction_controller.dart';
import 'package:pure_live/routes/route_observer_controller.dart';

class InitialServices {
  static void initGlobalServices() {
    Get.put(SettingsService(), permanent: true);
    Get.put(LocalInteractionController(), permanent: true);
    Get.put(RouteObserverController(), permanent: true);
  }

  static void initLazyControllers() {
    Get.lazyPut(() => FavoriteController(), fenix: true);
    Get.lazyPut(() => PopularController(), fenix: true);
    Get.lazyPut(() => AreasController(), fenix: true);
    Get.lazyPut(() => GlobalPlayerState(), fenix: true);
  }

  static Future<void> init() async {
    initGlobalServices();
    // Load and register the persisted custom font before MyApp builds its
    // first ThemeData. This makes the selection survive a full process restart.
    await SettingsService.to.font.ensureInitialized();
    await _migrateRoomScopedAudioOnly();
    initLazyControllers();
  }

  /// Retire the legacy global default so an old backup or persisted value can
  /// no longer make new rooms audio-only after ASMR has been disabled.
  static Future<void> _migrateRoomScopedAudioOnly() async {
    const migrationKey = 'migration.room_scoped_audio_only.v231';
    if (HivePrefUtil.getBool(migrationKey) == true) return;
    await HivePrefUtil.remove('audioOnly');
    SettingsService.to.player.audioOnly.v = false;
    await HivePrefUtil.setBool(migrationKey, true);
  }
}
