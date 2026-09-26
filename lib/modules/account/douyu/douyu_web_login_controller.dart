import 'package:pure_live/common/index.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class DouyuWebLoginController extends GetxController {
  InAppWebViewController? webViewController;
  final CookieManager cookieManager = CookieManager.instance();

  void onWebViewCreated(InAppWebViewController controller) {
    webViewController = controller;
    webViewController!.loadUrl(urlRequest: URLRequest(url: WebUri("https://www.douyu.com/")));
  }

  Future<String> collectCookies(WebUri? uri) async {
    if (uri == null) return '';
    final cookies = await cookieManager.getCookies(url: uri);
    return cookies.map((e) => "${e.name}=${e.value}").join(";");
  }

  // 不做登录态自动检测：检测到 cookie 就保存退出会导致无法在网页里
  // 换登其他账号。统一由用户点右上角「完成」时抓取并保存。
  Future<void> saveAndClose() async {
    final uri = await webViewController?.getUrl();
    final cookieStr = await collectCookies(uri);
    if (cookieStr.isNotEmpty) {
      SettingsService.to.cookieManager.douyuCookie.v = cookieStr;
    }
    Navigator.of(Get.context!).pop(true);
  }
}
