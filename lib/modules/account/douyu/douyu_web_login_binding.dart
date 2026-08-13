import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/account/douyu/douyu_web_login_controller.dart';

class DouyuWebLoginBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => DouyuWebLoginController());
  }
}
