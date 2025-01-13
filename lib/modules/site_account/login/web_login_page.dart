import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:pure_live/core/sites.dart';
import 'package:pure_live/modules/site_account/login/web_login_controller.dart';

class SiteWebLoginPage extends GetView<SiteWebLoginController> {
  const SiteWebLoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("${Sites.getSiteName(controller.site.id)}账号登录"),
        actions: [
          TextButton.icon(
            onPressed: controller.toQRLogin,
            icon: const Icon(Icons.qr_code),
            label: const Text("二维码登录"),
          ),
        ],
      ),
      body: InAppWebView(
          onWebViewCreated: controller.onWebViewCreated,
          onLoadStop: controller.onLoadStop,
          initialSettings: InAppWebViewSettings(
            userAgent:
                "Mozilla/5.0 (iPhone; CPU iPhone OS 13_2_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0.3 Mobile/15E148 Safari/604.1 Edg/118.0.0.0",
            useShouldOverrideUrlLoading: false,
          ),
          shouldOverrideUrlLoading: (webController, navigationAction) async {
            var uri = navigationAction.request.url;
            if (uri == null) {
              return NavigationActionPolicy.ALLOW;
            }
            if (controller.site.liveSite.webLoginHandle(uri)) {
              return NavigationActionPolicy.CANCEL;
            }
            return NavigationActionPolicy.ALLOW;
          }),
    );
  }
}
