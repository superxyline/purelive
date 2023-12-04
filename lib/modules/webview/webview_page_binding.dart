import 'package:get/get.dart';
import 'package:pure_live/modules/webview/webview_page_controller.dart';

class WebviewPageBinding extends Binding {
  @override
  List<Bind> dependencies() {
    return [Bind.lazyPut(() => WebviewPageController(site: Get.arguments[0]))];
  }
}
