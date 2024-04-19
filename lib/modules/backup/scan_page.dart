import 'package:pure_live/common/index.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pure_live/plugins/file_recover_utils.dart';

class ScanCodePage extends StatefulWidget {
  const ScanCodePage({super.key});

  @override
  State<ScanCodePage> createState() => _ScanCodePageState();
}

class _ScanCodePageState extends State<ScanCodePage> {
  MobileScannerController cameraController = MobileScannerController();
  bool hasFound = false;
  bool syncResult = false;
  bool isSuccess = false;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('扫描二维码'),
        actions: [
          hasFound
              ? Container()
              : IconButton(
                  icon: ValueListenableBuilder(
                    valueListenable: cameraController.torchState,
                    builder: (context, state, child) {
                      switch (state) {
                        case TorchState.off:
                          return const Icon(Icons.flash_off, color: Colors.grey);
                        case TorchState.on:
                          return const Icon(Icons.flash_on, color: Colors.yellow);
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
                    valueListenable: cameraController.cameraFacingState,
                    builder: (context, state, child) {
                      switch (state) {
                        case CameraFacing.front:
                          return const Icon(Icons.camera_front);
                        case CameraFacing.back:
                          return const Icon(Icons.camera_rear);
                      }
                    },
                  ),
                  iconSize: 20.0,
                  onPressed: () => cameraController.switchCamera(),
                ),
        ],
      ),
      body: hasFound
          ? Expanded(
              child: Center(
                child: syncResult
                    ? const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(
                            height: 20,
                          ),
                          Text(
                            "正在同步...",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      )
                    : Text(
                        isSuccess ? '同步成功' : "同步失败",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
              ),
            )
          : MobileScanner(
              // fit: BoxFit.contain,
              controller: cameraController,
              onDetect: (capture) async {
                final List<Barcode> barcodes = capture.barcodes;
                if (barcodes.isNotEmpty && FileRecoverUtils.isHostUrl(barcodes[0].rawValue!)) {
                  setState(() {
                    hasFound = true;
                    syncResult = true;
                  });
                  final result = await FileRecoverUtils().recoverSettingsBackup(barcodes[0].rawValue!);
                  SmartDialog.showToast(result ? '同步成功' : "同步失败");
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
