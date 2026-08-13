import 'package:remixicon/remixicon.dart';
import 'package:pure_live/common/index.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:pure_live/modules/account/huya/huya_web_login_controller.dart';

class HuyaWebLoginPage extends GetView<HuyaWebLoginController> {
  const HuyaWebLoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(i18n("huya_login")),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: TextButton.icon(
              onPressed: controller.saveAndClose,
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
                textStyle: const TextStyle(fontWeight: FontWeight.w600),
              ),
              icon: const Icon(Remix.check_line, size: 16),
              label: Text(i18n("done")),
            ),
          ),
        ],
      ),
      body: InAppWebView(
        onWebViewCreated: controller.onWebViewCreated,

        initialSettings: InAppWebViewSettings(
          userAgent:
              "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.43",
          useShouldOverrideUrlLoading: false,
          javaScriptEnabled: true,
          domStorageEnabled: true,
        ),
      ),
    );
  }
}