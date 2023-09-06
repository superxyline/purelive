import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';
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

class AppPages {
  AppPages._();

  static const initial = '/home';
  static const favorite = '/favorite';
  static const popular = '/popular';
  static const areas = '/areas';

  static const areaRooms = '/area_rooms';
  static const livePlay = '/live_play';

  static const search = '/search';
  static const settings = '/settings';
  static const contact = '/contact';
  static const backup = '/backup';
  static const about = '/about';
  static const history = '/history';
  static const donate = '/donate';

  static const signIn = '/sign_in';
  static const mine = '/mine';
  static toAreaRooms(LiveArea area) {
    Get.toNamed(areaRooms, arguments: area);
  }

  static toLivePlay(LiveRoom room) {
    Get.toNamed(livePlay, arguments: room);
  }

  static final routes = [
    GetPage(
      name: initial,
      page: HomePage.new,
      participatesInRootNavigator: true,
      preventDuplicates: true,
    ),
    GetPage(
      name: signIn,
      page: SignInPage.new,
    ),
    GetPage(
      name: mine,
      page: MinePage.new,
    ),
    GetPage(
      name: favorite,
      page: FavoritePage.new,
    ),
    GetPage(
      name: popular,
      page: PopularPage.new,
    ),
    GetPage(
      name: areas,
      page: AreasPage.new,
    ),
    GetPage(
      name: settings,
      page: SettingsPage.new,
      bindings: [SettingsBinding()],
    ),
    GetPage(
      name: history,
      page: HistoryPage.new,
    ),
    GetPage(
      name: search,
      page: SearchPage.new,
      bindings: [SearchBinding()],
    ),
    GetPage(
      name: contact,
      page: ContactPage.new,
    ),
    GetPage(
      name: backup,
      page: BackupPage.new,
    ),
    GetPage(
      name: about,
      page: AboutPage.new,
    ),
    GetPage(
      name: donate,
      page: DonatePage.new,
    ),
    GetPage(
      name: areaRooms,
      page: AreasRoomPage.new,
      bindings: [AreaRoomsBinding()],
    ),
    GetPage(
      name: livePlay,
      page: LivePlayPage.new,
      bindings: [LivePlayBinding()],
    ),
  ];
}
