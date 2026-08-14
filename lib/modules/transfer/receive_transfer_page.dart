import 'package:qr_flutter/qr_flutter.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/utils/file_utils.dart';
import 'package:pure_live/common/utils/event_bus.dart';
import 'package:pure_live/common/services/transfer_receiver_service.dart';
import 'package:pure_live/common/services/settings/backup_controller.dart';

/// 跨端传输（接收）：生成二维码，等待对方扫码后完全覆盖本机的关注与登录数据
class ReceiveTransferPage extends StatefulWidget {
  const ReceiveTransferPage({super.key});

  @override
  State<ReceiveTransferPage> createState() => _ReceiveTransferPageState();
}

class _ReceiveTransferPageState extends State<ReceiveTransferPage> {
  final TransferReceiverService _service = TransferReceiverService();
  String? _qrData;
  bool _failed = false;
  bool _received = false;
  bool _receiveOk = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final ip = await FileUtils.getLocalIpv4();
    if (ip == null) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    final port = await _service.start((data) async {
      final ok = Get.find<BackupController>().importTransferData(data);
      if (ok) {
        // 数据已覆盖，通知关注页刷新
        EventBus.instance.emit('refresh_favorite_rooms', null);
      }
      if (mounted) {
        setState(() {
          _received = true;
          _receiveOk = ok;
        });
      }
      return ok;
    });
    if (port == 0) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    if (mounted) setState(() => _qrData = 'http://$ip:$port');
  }

  @override
  void dispose() {
    _service.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(i18n("transfer_receive"))),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_failed)
                AppStatusView(type: AppStatusType.error, title: "", subtitle: i18n("transfer_ip_not_found"))
              else if (_qrData == null)
                const AppStatusView(type: AppStatusType.loading, title: "", subtitle: "")
              else if (_received)
                Column(
                  children: [
                    Icon(
                      _receiveOk ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      size: 64,
                      color: _receiveOk ? Colors.green : theme.colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _receiveOk ? i18n("transfer_received") : i18n("transfer_failed"),
                      style: AppTextStyles.t16.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(i18n("confirm")),
                    ),
                  ],
                )
              else
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: QrImageView(
                        data: _qrData!,
                        version: QrVersions.auto,
                        size: 220,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      i18n("transfer_waiting"),
                      style: AppTextStyles.t15.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _qrData!,
                      style: AppTextStyles.t13.copyWith(color: theme.colorScheme.primary),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        i18n("transfer_receive_desc"),
                        textAlign: TextAlign.center,
                        style: AppTextStyles.t12.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
