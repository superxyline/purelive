import 'package:pure_live/common/index.dart';

class SettingsBinding extends Bindings {
  @override
  void dependencies() {
Get.lazyPut(() => SettingsService());
  }
}
