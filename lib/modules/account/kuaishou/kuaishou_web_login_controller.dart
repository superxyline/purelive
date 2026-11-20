import 'package:pure_live/common/index.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class KuaishouWebLoginController extends GetxController {
  InAppWebViewController? webViewController;
  final CookieManager cookieManager = CookieManager.instance();

  void onWebViewCreated(InAppWebViewController controller) {
    webViewController = controller;
    // 打开快手直播间首页，由用户点击页面上的「登录」完成登录
    webViewController!.loadUrl(urlRequest: URLRequest(url: WebUri('https://live.kuaishou.com/')));
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

  // 不做登录态自动检测：检测到 cookie 就保存退出会导致无法在网页里
  // 换登其他账号。统一由用户点右上角「完成」时抓取并保存。
  Future<void> saveAndClose() async {
    final uri = await webViewController?.getUrl();
    final cookieStr = await collectCookies(uri);
    if (cookieStr.isNotEmpty) {
      SettingsService.to.cookieManager.kuaishouCookie.v = cookieStr;
      // 尽力从登录后的页面提取昵称（账号页显示用户名而非 UID）：
      // 快手无公开的当前用户信息接口，页面右上角/全局状态里带昵称。
      // 必须在 pop 之前同步提取——pop 后 WebView 销毁，JS 就没得执行了。
      // 提取失败静默——账号页回退显示 UID。
      await _extractNick();
    }
    Navigator.of(Get.context!).pop(true);
  }

  /// 从登录后的页面提取自己的昵称：DOM 候选选择器 + 全局初始状态兜底。
  static const String _nickExtractorJs = '''
(function() {
  try {
    var candidates = document.querySelectorAll(
      '[class*="username"] , [class*="nickName"] , [class*="nickname"] , ' +
      '.header-user-name, .user-name, .user-nickname'
    );
    for (var i = 0; i < candidates.length; i++) {
      var text = (candidates[i].textContent || '').trim();
      if (text && text.length >= 1 && text.length <= 30 && text.indexOf('登录') === -1) return text;
    }
    var states = [window.__APOLLO_STATE__, window.__NUXT__, window.__INITIAL_STATE__, window.__data];
    for (var s = 0; s < states.length; s++) {
      var st = states[s];
      if (!st || typeof st !== 'object') continue;
      for (var key in st) {
        var v = st[key];
        if (!v || typeof v !== 'object') continue;
        var nick = v.nickname || v.nickName || v.userName || v.name;
        if (typeof nick === 'string' && nick && nick.length <= 30) return nick;
      }
    }
  } catch (e) {}
  return '';
})();
''';

  Future<void> _extractNick() async {
    try {
      final controller = webViewController;
      if (controller == null) return;
      final result = await controller.evaluateJavascript(source: _nickExtractorJs);
      final nick = result?.toString().trim() ?? '';
      // evaluateJavascript 返回带引号的字符串字面量（如 "xxx"），剥掉
      final cleaned = nick.length >= 2 && nick.startsWith('"') && nick.endsWith('"')
          ? nick.substring(1, nick.length - 1)
          : nick;
      if (cleaned.isNotEmpty && cleaned != 'null' && cleaned != '""') {
        SettingsService.to.cookieManager.kuaishouNick.v = cleaned;
      }
    } catch (_) {
      // 页面已销毁/JS 执行失败：静默，账号页回退 UID
    }
  }
}
