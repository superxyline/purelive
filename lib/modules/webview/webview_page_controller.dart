import 'package:webview_flutter/webview_flutter.dart';
import 'package:pure_live/common/base/base_controller.dart';
import 'package:pure_live/custom/custom_site_providder.dart';

class WebviewPageController extends BaseController {
  final SiteInfoMation site;

  WebviewPageController({required this.site}) {
    initSite();
  }
  final controller = WebViewController();
  void initSite() {
    controller.clearLocalStorage();
    controller.clearCache();
    controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    controller.loadRequest(Uri.parse(site.siteUrl));
  }
}
