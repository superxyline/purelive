import 'web_search_controller.dart';
import 'package:pure_live/common/index.dart';

class WebSearchBinding extends Bindings {
  @override
  void dependencies() {
Get.lazyPut(() => WebSearchController());
  }
}
