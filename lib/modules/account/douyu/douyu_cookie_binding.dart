import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/account/douyu/douyu_cookie_controller.dart';

class DouyuCookieBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => DouyuCookieController());
  }
}
