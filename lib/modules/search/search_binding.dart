import 'search_controller.dart';
import 'package:pure_live/common/index.dart' hide SearchController;

class SearchBinding extends Bindings {
  @override
  void dependencies() {
Get.lazyPut(() => SearchController());
  }
}
