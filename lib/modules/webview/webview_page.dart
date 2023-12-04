import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:pure_live/modules/webview/webview_page_controller.dart';

class WebviewPagePage extends GetView<WebviewPageController> {
  const WebviewPagePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(controller.site.siteTitle),
      ),
      body: Center(child: WebViewWidget(controller: controller.controller)),
    );
  }
}
