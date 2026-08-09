import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/account/douyin/douyin_cookie_controller.dart';

class DouyinCookieBinding extends Bindings {
  @override
  void dependencies() {
Get.lazyPut(() => DouyinCookieController());
  }
}
