import 'package:pure_live/common/index.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class HuyaWebLoginController extends GetxController {
  InAppWebViewController? webViewController;
  final CookieManager cookieManager = CookieManager.instance();

  void onWebViewCreated(InAppWebViewController controller) {
    webViewController = controller;
    // 虎牙登录是 SPA，无独立 passport 域名，直接打开登录页
    webViewController!.loadUrl(urlRequest: URLRequest(url: WebUri('https://www.huya.com/login')));
  }

  Future<String> collectCookies(WebUri? uri) async {
    final Set<String> cookieSet = {};
    if (uri != null) {
      final cookies = await cookieManager.getCookies(url: uri);
      for (final c in cookies) {
        cookieSet.add('${c.name}=${c.value}');
      }
    }
    // 虎牙登录 cookie 通常落在 www.huya.com 与 udblgn.huya.com
    for (final domain in const ['https://www.huya.com/', 'https://udblgn.huya.com/']) {
      final cookies = await cookieManager.getCookies(url: WebUri(domain));
      for (final c in cookies) {
        cookieSet.add('${c.name}=${c.value}');
      }
    }
    return cookieSet.join(';');
  }

  // 不做登录态自动检测：检测到 cookie 就保存退出会导致无法在网页里
  // 换登其他账号。统一由用户点右上角「完成」时抓取并保存。
  Future<void> saveAndClose() async {
    final uri = await webViewController?.getUrl();
    final cookieStr = await collectCookies(uri);
    if (cookieStr.isNotEmpty) {
      SettingsService.to.cookieManager.huyaCookie.v = cookieStr;
    }
    Navigator.of(Get.context!).pop(true);
  }
}
