import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/account/huya/huya_web_login_controller.dart';

class HuyaWebLoginBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => HuyaWebLoginController());
  }
}