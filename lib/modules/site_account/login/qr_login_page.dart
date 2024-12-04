import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pure_live/core/interface/live_site_mixin.dart';
import 'package:pure_live/modules/site_account/login/qr_login_controller.dart';
import 'package:qr_flutter/qr_flutter.dart';

class SiteQRLoginPage extends GetView<SiteQRLoginController> {
  const SiteQRLoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("${controller.site.name}账号登录")),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Center(
            child: Obx(
              () {
                if (controller.qrStatus.value == QRStatus.loading) {
                  return const CircularProgressIndicator();
                }
                if (controller.qrStatus.value == QRStatus.failed) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text("二维码加载失败"),
                      TextButton(
                        onPressed: controller.loadQRCode,
                        child: const Text("重试"),
                      ),
                    ],
                  );
                }
                if (controller.qrStatus.value == QRStatus.failed) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text("二维码已失效"),
                      TextButton(
                        onPressed: controller.loadQRCode,
                        child: const Text("刷新二维码"),
                      ),
                    ],
                  );
                }
                return Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: QrImageView(
                        data: controller.qrcodeUrl.value,
                        version: QrVersions.auto,
                        backgroundColor: Colors.white,
                        size: 200.0,
                        padding: const EdgeInsets.all(12),
                      ),
                    ),
                    const SizedBox(
                      height: 8,
                    ),
                    Visibility(
                      visible: controller.qrStatus.value == QRStatus.scanned,
                      child: const Text("已扫描，请在手机上确认登录"),
                    ),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              "请使用${controller.site.name}手机客户端扫描二维码登录",
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
