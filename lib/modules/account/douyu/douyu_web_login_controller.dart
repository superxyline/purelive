import 'package:pure_live/common/index.dart';
import 'package:pure_live/core/site/douyu/douyu_utils.dart';
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
      final cookies = SettingsService.to.cookieManager;
      cookies.douyuCookie.v = cookieStr;
      // 记录保存时间：网页版 dy_auth 读不出过期时间，靠它 + 7 天规则判断
      cookies.douyuCookieSavedAt.v = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      // 顺手抽出续期要用的两样东西（cookie 里通常都有）
      final ltp0 = DouyuUtils.cookieField(cookieStr, DouyuUtils.longTermTokenName);
      if (ltp0 != null && ltp0.isNotEmpty) cookies.douyuLtp0.v = ltp0;
      final did = DouyuUtils.cookieField(cookieStr, DouyuUtils.deviceIdName);
      if (did != null && did.isNotEmpty) cookies.douyuDid.v = did;
      // 通知 NAS 补推登录态（关注列表没变也要推，否则 NAS 端拿不到新 cookie）
      cookies.notifyLoginChanged();
    }
    Navigator.of(Get.context!).pop(true);
  }
}
