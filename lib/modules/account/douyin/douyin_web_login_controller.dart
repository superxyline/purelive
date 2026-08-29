import 'dart:async';
import 'package:pure_live/common/index.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class DouyinWebLoginController extends GetxController {
  InAppWebViewController? webViewController;
  final CookieManager cookieManager = CookieManager.instance();
  Timer? _pollTimer;
  bool _saved = false;

  @override
  void onClose() {
    _pollTimer?.cancel();
    super.onClose();
  }

  void onWebViewCreated(InAppWebViewController controller) {
    webViewController = controller;
    // 注意：douyin.com/login 会 302 到带空 ticket 的 SSO 回调，返回
    // {"description":"缺少参数","error_code":3} 的 JSON 错误页，
    // 因此这里打开首页，由用户点击页面上的「登录」完成登录。
    webViewController!.loadUrl(urlRequest: URLRequest(url: WebUri('https://www.douyin.com/')));
    _startPolling();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _checkLogin());
  }

  Future<void> _checkLogin() async {
    if (_saved) return;
    final uri = await webViewController?.getUrl();
    final cookieStr = await collectCookies(uri);
    if (_isLogined(cookieStr)) {
      _saved = true;
      _pollTimer?.cancel();
      SettingsService.to.cookieManager.douyinCookie.v = cookieStr;
      ToastUtil.show(i18n('login_success'));
      Navigator.of(Get.context!).pop(true);
    }
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

  bool _isLogined(String cookieStr) {
    return cookieStr.contains('sessionid');
  }

  /// 手动点击右上角完成，保存当前网页的 Cookie
  Future<void> saveAndClose() async {
    _saved = true;
    _pollTimer?.cancel();
    final uri = await webViewController?.getUrl();
    final cookieStr = await collectCookies(uri);
    if (cookieStr.isNotEmpty) {
      SettingsService.to.cookieManager.douyinCookie.v = cookieStr;
    }
    Navigator.of(Get.context!).pop(true);
  }
}
