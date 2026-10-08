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
import 'package:pure_live/common/services/nas_discovery_service.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  final LogController logController = LogController.to;
  final NasSyncController nasSync = NasSyncController.to;
  String get backupDirectory => SettingsService.to.backup.backupDirectory.v;

  /// NAS 服务选择：只搜索/选择并保存服务器地址，**不执行任何同步**——
  /// 同步动作只从上一级菜单的「推送到 NAS」「从 NAS 拉取」两个按钮触发。
  Future<void> _showNasSyncDialog() async {
    var mode = 0; // 0=搜索中 1=结果列表 2=手动输入
    List<NasServiceInfo>? results;
    var progress = 0.0;
    var scanStarted = false; // 首次扫描只自动触发一次
    final ctrl = TextEditingController(text: nasSync.serverAddress.v);

    Future<void> runScan(BuildContext dialogContext, void Function(VoidCallback) setState) async {
      // 对话框可能在扫描完成前被关闭，state 回调必须先查 mounted
      void safe(VoidCallback fn) {
        if (dialogContext.mounted) setState(fn);
      }

      safe(() {
        mode = 0;
        results = null;
        progress = 0.0;
      });
      final found = await NasDiscoveryService.discover(
        onProgress: (p) => safe(() => progress = p),
      );
      safe(() {
        results = found;
        mode = 1;
      });
    }

    final action = await Get.dialog<String>(
      StatefulBuilder(
        builder: (dialogContext, setState) {
          // 打开对话框即自动启动首次扫描（此前 bug：只画了进度条没调 discover）
          if (!scanStarted && mode == 0) {
            scanStarted = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (dialogContext.mounted) runScan(dialogContext, setState);
            });
          }
          return AlertDialog(
            title: Text(i18n('nas_sync_title')),
            content: SizedBox(
              width: double.maxFinite,
              child: mode == 2
                  ? TextField(
                      controller: ctrl,
                      keyboardType: TextInputType.url,
                      autofocus: true,
                      decoration: InputDecoration(hintText: i18n('nas_addr_hint'), labelText: 'NAS'),
                    )
                  : mode == 0
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            LinearProgressIndicator(value: progress <= 0 ? null : progress),
                            const SizedBox(height: 12),
                            Text(i18n('nas_discovering'), style: dialogContext.textTheme.bodySmall),
                          ],
                        )
                      : results!.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                i18n('nas_discover_none'),
                                style: dialogContext.textTheme.bodySmall,
                              ),
                            )
                          : ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 320),
                              child: ListView.separated(
                                shrinkWrap: true,
                                itemCount: results!.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (_, i) {
                                  final s = results![i];
                                  return ListTile(
                                    dense: true,
                                    leading: const Icon(Remix.server_line),
                                    title:
                                        Text('Pure Live', style: dialogContext.textTheme.bodyMedium),
                                    subtitle: Text(
                                      '${s.address} · ${s.follows} 个关注',
                                      style: dialogContext.textTheme.bodySmall,
                                    ),
                                    trailing: const Icon(Remix.arrow_right_s_line),
                                    onTap: () => Navigator.pop(dialogContext, s.address),
                                  );
                                },
                              ),
                            ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext, 'cancel'),
                  child: Text(i18n('cancel'))),
              // 搜索完成后提供"重新搜索"；输入模式提供"搜索"返回；输入中不显示
              if (mode == 1)
                TextButton(
                  onPressed: () => runScan(dialogContext, setState),
                  child: Text(i18n('nas_discover_retry')),
                ),
              if (mode != 2)
                TextButton(
                  onPressed: () => setState(() => mode = 2),
                  child: Text(i18n('nas_discover_manual')),
                )
              else
                TextButton(
                  onPressed: () => runScan(dialogContext, setState),
                  child: Text(i18n('nas_discover')),
                ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, 'save'),
                child: Text(i18n('save')),
              ),
            ],
          );
        },
      ),
    );
    if (action == null || action == 'cancel') return;
    // 纯地址配置：无论点选服务还是手动保存，都只存地址不触发同步
    if (action == 'save') {
      nasSync.saveAddress(ctrl.text);
    } else {
      nasSync.saveAddress(action);
    }
    setState(() {}); // 刷新卡片上显示的地址
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
          // NAS 服务器常连同步：存地址 + 方向可选（推送/拉取/并集）+ 局域网自动发现
          context.buildGroupTitle(i18n("nas_sync_title")),
          context.buildModernCard([
            Obx(() => context.buildTile(
                  icon: Remix.server_line,
                  title: i18n("nas_sync_title"),
                  subtitle: nasSync.baseUrl.isEmpty
                      ? i18n("nas_not_configured")
                      : "${nasSync.serverAddress.v} · ${i18n('tap_to_config')}",
                  onTap: _showNasSyncDialog,
                )),
            context.buildTile(
              icon: Remix.upload_2_line,
              title: i18n("nas_push_tile"),
              subtitle: i18n("nas_push_sub"),
              onTap: () => nasSync.pushNow(),
            ),
            context.buildTile(
              icon: Remix.download_2_line,
              title: i18n("nas_pull_tile"),
              subtitle: i18n("nas_pull_sub"),
              onTap: () => nasSync.pullNow(),
            ),
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
