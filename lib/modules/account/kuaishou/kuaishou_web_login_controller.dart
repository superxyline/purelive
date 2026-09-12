import 'dart:async';
import 'package:pure_live/common/index.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class KuaishouWebLoginController extends GetxController {
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
    // 打开快手直播间首页，由用户点击页面上的「登录」完成登录
    webViewController!.loadUrl(urlRequest: URLRequest(url: WebUri('https://live.kuaishou.com/')));
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
      SettingsService.to.cookieManager.kuaishouCookie.v = cookieStr;
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
    // 主站与直播域的登录态 cookie（kuaishou.server.web_st / passToken 等）一并收集
    for (final domain in const ['https://www.kuaishou.com/', 'https://live.kuaishou.com/']) {
      final cookies = await cookieManager.getCookies(url: WebUri(domain));
      for (final c in cookies) {
        cookieSet.add('${c.name}=${c.value}');
      }
    }
    return cookieSet.join(';');
  }

  bool _isLogined(String cookieStr) {
    return cookieStr.contains('kuaishou.server.web_st') || cookieStr.contains('passToken');
  }

  /// 手动点击右上角完成，保存当前网页的 Cookie
  Future<void> saveAndClose() async {
    _saved = true;
    _pollTimer?.cancel();
    final uri = await webViewController?.getUrl();
    final cookieStr = await collectCookies(uri);
    if (cookieStr.isNotEmpty) {
      SettingsService.to.cookieManager.kuaishouCookie.v = cookieStr;
    }
    Navigator.of(Get.context!).pop(true);
  }
}
