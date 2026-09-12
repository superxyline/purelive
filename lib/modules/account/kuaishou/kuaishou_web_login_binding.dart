import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/account/kuaishou/kuaishou_web_login_controller.dart';

class KuaishouWebLoginBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => KuaishouWebLoginController());
  }
}
