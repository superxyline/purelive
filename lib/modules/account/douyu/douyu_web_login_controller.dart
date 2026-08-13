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

  bool _isLogined(String cookieStr) {
    return cookieStr.contains('acf_uid') && cookieStr.contains('acf_stk');
  }

  void onLoadStop(InAppWebViewController controller, WebUri? uri) async {
    if (uri == null) return;
    final cookieStr = await collectCookies(uri);
    if (_isLogined(cookieStr)) {
      SettingsService.to.cookieManager.douyuCookie.v = cookieStr;
      ToastUtil.show(i18n('login_success'));
      Navigator.of(Get.context!).pop(true);
    }
  }

  /// 手动点击右上角完成，保存当前网页的 Cookie
  Future<void> saveAndClose() async {
    final uri = await webViewController?.getUrl();
    final cookieStr = await collectCookies(uri);
    if (cookieStr.isNotEmpty) {
      SettingsService.to.cookieManager.douyuCookie.v = cookieStr;
    }
    Navigator.of(Get.context!).pop(true);
  }
}
