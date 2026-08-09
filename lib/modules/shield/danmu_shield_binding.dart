import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/shield/danmu_shield_controller.dart';

class DanmuShieldBinding extends Bindings {
  @override
  void dependencies() {
Get.lazyPut(() => DanmuShieldController());
  }
}
