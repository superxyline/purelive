import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:remixicon/remixicon.dart';
import 'package:pure_live/common/index.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pure_live/plugins/file_utils.dart';
import 'package:pure_live/modules/backup/scan_page.dart';
import 'package:pure_live/modules/transfer/receive_transfer_page.dart';
import 'package:pure_live/common/global/app_path_manager.dart';
import 'package:pure_live/plugins/backup_recovery_service.dart';
import 'package:pure_live/common/services/settings/log_controller.dart';
import 'package:pure_live/common/services/settings/nas_sync_controller.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  final LogController logController = LogController.to;
  final NasSyncController nasSync = NasSyncController.to;
  String get backupDirectory => SettingsService.to.backup.backupDirectory.v;

  /// NAS 地址配置：保存即生效；"保存并同步"额外做一次并集同步（拉 NAS 关注并入本地，再把并集推回）
  Future<void> _showNasSyncDialog() async {
    final ctrl = TextEditingController(text: nasSync.serverAddress.v);
    final action = await Get.dialog<String>(
      AlertDialog(
        title: Text(i18n('nas_sync_title')),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.url,
          autofocus: true,
          decoration: InputDecoration(hintText: i18n('nas_addr_hint'), labelText: 'NAS'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, 'cancel'), child: Text(i18n('cancel'))),
          TextButton(onPressed: () => Navigator.pop(context, 'save'), child: Text(i18n('save'))),
          FilledButton(onPressed: () => Navigator.pop(context, 'sync'), child: Text(i18n('nas_save_and_sync'))),
        ],
      ),
    );
    if (action == null || action == 'cancel') return;
    nasSync.saveAddress(ctrl.text);
    if (action == 'sync') await nasSync.syncNow();
  }

  Future<void> _openLogDirectory() async {
    try {
      Directory logDir;
      if (Platform.isAndroid) {
        final dir = await getDownloadsDirectory();
        logDir = Directory(path.join(dir!.path, AppPathManager.dirLogs));
      } else {
        logDir = await AppPathManager().getDir(AppPathManager.dirLogs);
      }

      if (await logDir.exists()) {
        FileUtils.openFileOrUrl(path.join(logDir.path, 'log'));
      } else {
        ToastUtil.show(i18n('log_dir_not_exist'));
      }
    } catch (e) {
      ToastUtil.show(i18n('open_log_dir_failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(i18n("backup_recover"))),
      body: ListView(
        physics: const PureLiveScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          context.buildGroupTitle(i18n("cloud_backup")),
          context.buildModernCard([
            context.buildTile(
              icon: Remix.cloud_line,
              title: i18n("webdav"),
              subtitle: i18n("backup_to_webdav"),
              onTap: () => Get.toNamed(RoutePath.kWebDavPage),
            ),
            if (Platform.isAndroid || Platform.isIOS) ...[
              context.buildTile(
                icon: Remix.qr_scan_line,
                title: i18n("transfer_send"),
                subtitle: i18n("transfer_send_subtitle"),
                onTap: () => Get.to(() => const ScanCodePage(transferMode: true)),
              ),
              context.buildTile(
                icon: Remix.download_2_line,
                title: i18n("transfer_receive"),
                subtitle: i18n("transfer_receive_subtitle"),
                onTap: () => Get.to(() => const ReceiveTransferPage()),
              ),
            ],
          ]),
          const SizedBox(height: 20),
          // NAS 服务器常连同步：存地址 + 与 NAS 关注列表做并集
          context.buildGroupTitle(i18n("nas_sync_title")),
          context.buildModernCard([
            Obx(() => context.buildTile(
                  icon: Remix.server_line,
                  title: i18n("nas_sync_title"),
                  subtitle: nasSync.baseUrl.isEmpty
                      ? i18n("nas_not_configured")
                      : "${nasSync.serverAddress.v} · ${i18n('tap_to_sync')}",
                  onTap: _showNasSyncDialog,
                )),
          ]),
          const SizedBox(height: 20),
            context.buildGroupTitle(i18n("local_backup")),
            context.buildModernCard([
              context.buildTile(
                icon: Remix.file_download_line,
                title: i18n("create_backup"),
                subtitle: i18n("create_backup_subtitle"),
                onTap: () async {
                  if (backupDirectory.isEmpty) {
                    ToastUtil.show(i18n('please_set_backup_directory'));
                    return;
                  }
                  await BackupRecoveryService().createAppSettingsBackup(backupDirectory);
                },
              ),
              context.buildTile(
                icon: Remix.file_upload_line,
                title: i18n("recover_backup"),
                subtitle: i18n("recover_backup_subtitle"),
                onTap: () => BackupRecoveryService().recoverSettingsFromFile(),
              ),
            ]),
            const SizedBox(height: 20),
            context.buildGroupTitle(i18n("backup_settings")),
            context.buildModernCard([
              context.buildTile(
                icon: Remix.folder_open_line,
                title: i18n("backup_directory"),
                subtitle: backupDirectory.isEmpty ? i18n('please_set_backup_directory') : backupDirectory,
                onTap: () async {
                  await BackupRecoveryService().updateBackupDirectory();
                },
              ),
            ]),
            const SizedBox(height: 20),
            context.buildGroupTitle(i18n("log_manage")),
            context.buildModernCard([
              context.buildTile(
                icon: Remix.file_text_line,
                title: i18n("enable_local_log"),
                subtitle: i18n("enable_local_log_desc"),
                trailing: Switch(
                  value: logController.storedEnableLog.v,
                  onChanged: (val) => logController.storedEnableLog.v = val,
                ),
                onTap: () => logController.storedEnableLog.v = !logController.storedEnableLog.v,
              ),
              Obx(() {
                if (logController.serverPort.value == 0) return const SizedBox.shrink();
                final String displayAddress = logController.serverAddress.value == '0.0.0.0'
                    ? 'localhost'
                    : logController.serverAddress.value;
                final String urlStr = 'http://$displayAddress:${logController.serverPort.value}';
                return context.buildTile(
                  icon: Remix.global_line,
                  title: i18n("view_logs_in_browser"),
                  subtitle: urlStr,
                  trailing: const Icon(Remix.arrow_right_s_line),
                  onTap: () async {
                    final Uri uri = Uri.parse(urlStr);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                );
              }),

              context.buildTile(
                icon: Remix.folder_open_line,
                title: i18n("open_log_dir"),
                subtitle: i18n("open_log_dir_desc"),
                onTap: _openLogDirectory,
              ),
            ]),
            const SizedBox(height: 32),
          ],
        ),
    );
  }
}
