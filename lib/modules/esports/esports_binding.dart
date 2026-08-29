import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/esports/esports_controller.dart';
import 'package:pure_live/modules/esports/favorite_match_controller.dart';

/// 赛事页独立路由绑定（桌面快捷方式直达赛事中心使用）。
class EsportsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => EsportsController());
    Get.lazyPut(() => FavoriteMatchController());
  }
}
