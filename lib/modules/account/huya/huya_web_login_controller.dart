import 'dart:async';
import 'package:pure_live/common/index.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class HuyaWebLoginController extends GetxController {
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
    // 虎牙登录是 SPA，无独立 passport 域名，直接打开登录页
    webViewController!.loadUrl(urlRequest: URLRequest(url: WebUri('https://www.huya.com/login')));
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
      SettingsService.to.cookieManager.huyaCookie.v = cookieStr;
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
    // 虎牙登录 cookie 通常落在 www.huya.com 与 udblgn.huya.com
    for (final domain in const ['https://www.huya.com/', 'https://udblgn.huya.com/']) {
      final cookies = await cookieManager.getCookies(url: WebUri(domain));
      for (final c in cookies) {
        cookieSet.add('${c.name}=${c.value}');
      }
    }
    return cookieSet.join(';');
  }

  bool _isLogined(String cookieStr) {
    return cookieStr.contains('yyuid') && cookieStr.contains('token');
  }

  /// 手动点击右上角完成，保存当前网页的 Cookie
  Future<void> saveAndClose() async {
    _saved = true;
    _pollTimer?.cancel();
    final uri = await webViewController?.getUrl();
    final cookieStr = await collectCookies(uri);
    if (cookieStr.isNotEmpty) {
      SettingsService.to.cookieManager.huyaCookie.v = cookieStr;
    }
    Navigator.of(Get.context!).pop(true);
  }
}