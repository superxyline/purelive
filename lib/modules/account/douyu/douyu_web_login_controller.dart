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
    // LTP0（续期密钥）只种在 passport.douyu.com 域（扫码登录页），主站域
    // 的 CookieManager 拿不到——只抓主站时 LTP0 永远为空，自动续期从未
    // 生效，登录态 7 天到期后只能重新扫码。
    final passportCookie = await collectCookies(WebUri("https://passport.douyu.com/"));
    if (cookieStr.isNotEmpty) {
      final cookies = SettingsService.to.cookieManager;
      cookies.douyuCookie.v = cookieStr;
      // 记录保存时间：网页版 dy_auth 读不出过期时间，靠它 + 7 天规则判断
      cookies.douyuCookieSavedAt.v = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      // 续期要用的两样东西：LTP0 只在 passport 域，dy_did 两域都有。
      // 合并后提取（重名时 passport 域在前会被主站覆盖，无碍——两域同值）。
      final combined = passportCookie.isNotEmpty ? '$cookieStr;$passportCookie' : cookieStr;
      final ltp0 = DouyuUtils.cookieField(combined, DouyuUtils.longTermTokenName);
      if (ltp0 != null && ltp0.isNotEmpty) {
        cookies.douyuLtp0.v = ltp0;
      } else {
        // 没有续期密钥，到期后无法自动续：明确告知而不是让用户 7 天后一头雾水
        SmartDialog.showToast('未取到续期密钥(LTP0)：本次登录到期后仍需重新扫码');
      }
      final did = DouyuUtils.cookieField(combined, DouyuUtils.deviceIdName);
      if (did != null && did.isNotEmpty) cookies.douyuDid.v = did;
      // 通知 NAS 补推登录态（关注列表没变也要推，否则 NAS 端拿不到新 cookie）
      cookies.notifyLoginChanged();
    }
    Navigator.of(Get.context!).pop(true);
  }
}
