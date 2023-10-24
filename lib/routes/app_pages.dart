import 'package:get/get.dart';
import 'package:pure_live/modules/about/about_page.dart';
import 'package:pure_live/modules/about/donate_page.dart';
import 'package:pure_live/modules/area_rooms/area_rooms_binding.dart';
import 'package:pure_live/modules/area_rooms/area_rooms_page.dart';
import 'package:pure_live/modules/areas/areas_page.dart';
import 'package:pure_live/modules/auth/mine_page.dart';
import 'package:pure_live/modules/contact/contact_page.dart';
import 'package:pure_live/modules/favorite/favorite_page.dart';
import 'package:pure_live/modules/home/home_page.dart';
import 'package:pure_live/modules/live_play/live_play_binding.dart';
import 'package:pure_live/modules/live_play/live_play_page.dart';
import 'package:pure_live/modules/popular/popular_page.dart';
import 'package:pure_live/modules/search/search_binding.dart';
import 'package:pure_live/modules/settings/settings_binding.dart';
import 'package:pure_live/modules/settings/settings_page.dart';
import 'package:pure_live/modules/search/search_page.dart';
import 'package:pure_live/modules/history/history_page.dart';
import 'package:pure_live/modules/backup/backup_page.dart';
// auth
import 'package:pure_live/modules/auth/sign_in_page.dart';
import 'route_path.dart';
class AppPages {
  AppPages._();

  static final routes = [
    GetPage(
      name: RoutePath.kInitial,
      page: HomePage.new,
      participatesInRootNavigator: true,
      preventDuplicates: true,
    ),
    GetPage(
      name: RoutePath.kSignIn,
      page: SignInPage.new,
    ),
    GetPage(
      name: RoutePath.kMine,
      page: MinePage.new,
    ),
    GetPage(
      name: RoutePath.kFavorite,
      page: FavoritePage.new,
    ),
    GetPage(
      name: RoutePath.kPopular,
      page: PopularPage.new,
    ),
    GetPage(
      name: RoutePath.kAreas,
      page: AreasPage.new,
    ),
    GetPage(
      name: RoutePath.kSettings,
      page: SettingsPage.new,
      bindings: [SettingsBinding()],
    ),
    GetPage(
      name: RoutePath.kHistory,
      page: HistoryPage.new,
    ),
    GetPage(
      name: RoutePath.kSearch,
      page: SearchPage.new,
      bindings: [SearchBinding()],
    ),
    GetPage(
      name: RoutePath.kContact,
      page: ContactPage.new,
    ),
    GetPage(
      name: RoutePath.kBackup,
      page: BackupPage.new,
    ),
    GetPage(
      name: RoutePath.kAbout,
      page: AboutPage.new,
    ),
    GetPage(
      name: RoutePath.kDonate,
      page: DonatePage.new,
    ),
    GetPage(
      name: RoutePath.kAreaRooms,
      page: AreasRoomPage.new,
      bindings: [AreaRoomsBinding()],
    ),
    GetPage(
      name: RoutePath.kLivePlay,
      page: () => LivePlayPage(),
      preventDuplicates: true,
      bindings: [LivePlayBinding()],
    ),
  ];
}
