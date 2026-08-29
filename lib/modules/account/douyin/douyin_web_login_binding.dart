import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/account/douyin/douyin_web_login_controller.dart';

class DouyinWebLoginBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => DouyinWebLoginController());
  }
}
