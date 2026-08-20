import 'dart:io';
import 'dart:convert';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/plugins/file_utils.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pure_live/plugins/backup_recovery_service.dart';
import 'package:pure_live/common/services/settings/backup_controller.dart';

class ScanCodePage extends StatefulWidget {
  const ScanCodePage({super.key, this.transferMode = false});

  /// 跨端传输模式：扫码后把本机关注 + 登录 + 全部设置推送到对方（覆盖对方）
  final bool transferMode;

  @override
  State<ScanCodePage> createState() => _ScanCodePageState();
}

class _ScanCodePageState extends State<ScanCodePage> {
  MobileScannerController cameraController = MobileScannerController(torchEnabled: true);
  bool hasFound = false;
  bool syncResult = false;
  bool isSuccess = false;

  /// 跨端传输模式：把本机关注 + 登录 + 全部设置 POST 到对方接收服务（/api/importData）
  Future<bool> _pushTransferData(String httpAddress) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse('$httpAddress/api/importData'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(Get.find<BackupController>().exportTransferData()));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      await response.drain<void>();
      final decoded = jsonDecode(body);
      return decoded is Map && decoded['data'] == true;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(i18n("scan_qr_code")),
        actions: [
          hasFound
              ? Container()
              : IconButton(
                  icon: ValueListenableBuilder(
                    valueListenable: cameraController,
                    builder: (context, state, child) {
                      switch (state.torchState) {
                        case TorchState.off:
                          return const Icon(Icons.flash_off, color: Colors.grey);
                        case TorchState.on:
                          return const Icon(Icons.flash_on, color: Colors.yellow);
                        case TorchState.auto:
                          return IconButton(
                            color: Colors.white,
                            iconSize: 32.0,
                            icon: const Icon(Icons.flash_auto),
                            onPressed: () async {
                              await cameraController.toggleTorch();
                            },
                          );
                        case TorchState.unavailable:
                          return const Icon(Icons.no_flash, color: Colors.grey);
                      }
                    },
                  ),
                  iconSize: 20.0,
                  onPressed: () => cameraController.toggleTorch(),
                ),
          hasFound
              ? Container()
              : IconButton(
                  icon: ValueListenableBuilder(
                    valueListenable: cameraController,
                    builder: (context, state, child) {
                      if (state.cameraDirection == CameraFacing.back) {
                        return const Icon(Icons.camera_rear);
                      } else {
                        return const Icon(Icons.camera_front);
                      }
                    },
                  ),
                  iconSize: 20.0,
                  onPressed: () => cameraController.switchCamera(),
                ),
        ],
      ),
      body: hasFound
          ? Center(
              child: syncResult
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AppStatusView(type: AppStatusType.loading, title: "", subtitle: ""),
                        SizedBox(height: 20),
                        Text(i18n("syncing"), style: AppTextStyles.t16.copyWith(fontWeight: FontWeight.bold)),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          isSuccess ? i18n("sync_success") : i18n("sync_failed"),
                          style: AppTextStyles.t16.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              hasFound = false;
                              syncResult = false;
                              isSuccess = false;
                            });
                            cameraController = MobileScannerController();
                          },
                          child: Text(i18n("tap_to_sync")),
                        ),
                      ],
                    ),
            )
          : MobileScanner(
              // fit: BoxFit.contain,
              controller: cameraController,
              onDetect: (capture) async {
                final List<Barcode> barcodes = capture.barcodes;
                if (barcodes.isNotEmpty && FileUtils.isHostUrl(barcodes[0].rawValue!)) {
                  setState(() {
                    hasFound = true;
                    syncResult = true;
                  });
                  final result = widget.transferMode
                      ? await _pushTransferData(barcodes[0].rawValue!)
                      : await BackupRecoveryService().pushSettingsToRemoteServer(barcodes[0].rawValue!);
                  ToastUtil.show(result ? i18n("sync_success") : i18n("sync_failed"));
                  setState(() {
                    isSuccess = result;
                    syncResult = false;
                  });
                }
              },
            ),
    );
  }
}
