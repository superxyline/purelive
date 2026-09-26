import 'package:pure_live/common/index.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class DouyinWebLoginController extends GetxController {
  InAppWebViewController? webViewController;
  final CookieManager cookieManager = CookieManager.instance();

  void onWebViewCreated(InAppWebViewController controller) {
    webViewController = controller;
    // 注意：douyin.com/login 会 302 到带空 ticket 的 SSO 回调，返回
    // {"description":"缺少参数","error_code":3} 的 JSON 错误页，
    // 因此这里打开首页，由用户点击页面上的「登录」完成登录。
    webViewController!.loadUrl(urlRequest: URLRequest(url: WebUri('https://www.douyin.com/')));
  }

  Future<String> collectCookies(WebUri? uri) async {
    final Set<String> cookieSet = {};
    if (uri != null) {
      final cookies = await cookieManager.getCookies(url: uri);
      for (final c in cookies) {
        cookieSet.add('${c.name}=${c.value}');
      }
    }
    // 直播相关接口使用 live.douyin.com 域，ttwid 等 cookie 一并收集
    for (final domain in const ['https://www.douyin.com/', 'https://live.douyin.com/']) {
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
      SettingsService.to.cookieManager.douyinCookie.v = cookieStr;
    }
    Navigator.of(Get.context!).pop(true);
  }
}
