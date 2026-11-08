import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:pure_live/common/index.dart';
import 'package:file_picker/file_picker.dart';
import 'package:date_format/date_format.dart' hide S;
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/common/services/settings/backup_controller.dart';

class BackupRecoveryService {
  Future<String?> createAppSettingsBackup(String backupDirectory) async {
    final backup = Get.find<BackupController>();
    final json = const JsonEncoder.withIndent('  ').convert(backup.exportAllSettings());
    final dateStr = formatDate(DateTime.now(), [yyyy, '-', mm, '-', dd, 'T', HH, '_', nn, '_', ss]);
    final fileName = 'purelive_$dateStr.txt';

    // 移动端走系统"另存为"（SAF）：targetSdk 37 下 manageExternalStorage 请求
    // 必被拒（Manifest 未声明），而 SAF 写入本身无需存储权限。
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final saved = await FilePicker.saveFile(
          fileName: fileName,
          bytes: Uint8List.fromList(utf8.encode(json)),
          type: FileType.custom,
          allowedExtensions: const ['txt'],
          mimeType: 'text/plain',
        );
        if (saved == null) return null;
        ToastUtil.show(i18n("create_backup_success"));
        return saved.toString();
      } catch (e) {
        ToastUtil.show(i18n("create_backup_failed"));
        return null;
      }
    }

    String? selectedDirectory = await FilePicker.getDirectoryPath(
      initialDirectory: backupDirectory.isEmpty ? '/' : backupDirectory,
    );
    if (selectedDirectory == null) return null;

    final file = File('$selectedDirectory/$fileName');

    if (backup.backup(file)) {
      ToastUtil.show(i18n("create_backup_success"));
      if (backup.backupDirectory.v.isEmpty) {
        backup.backupDirectory.v = selectedDirectory;
      }
      return selectedDirectory;
    } else {
      ToastUtil.show(i18n("create_backup_failed"));
      return null;
    }
  }

  Future<void> recoverSettingsFromFile() async {
    final backup = Get.find<BackupController>();
    final result = await FilePicker.pickFile(
      dialogTitle: i18n("select_recover_file"),
      type: FileType.custom,
      allowedExtensions: ['txt'],
    );

    if (result?.path == null) return;

    final file = File(result!.path!);
    if (backup.recover(file)) {
      ToastUtil.show(i18n("recover_backup_success"));
    } else {
      ToastUtil.show(i18n("recover_backup_failed"));
    }
  }

  Future<String?> updateBackupDirectory() async {
    final backup = Get.find<BackupController>();
    String? selectedDirectory = await FilePicker.getDirectoryPath();
    if (selectedDirectory == null) return null;

    backup.backupDirectory.v = selectedDirectory;
    return selectedDirectory;
  }

  Future<bool> pushSettingsToRemoteServer(String httpAddress) async {
    final backup = Get.find<BackupController>();
    try {
      final response = await HttpClient.instance.postJson(
        '$httpAddress/api/setSettings',
        queryParameters: {"settings": jsonEncode(backup.exportToTVSettings())},
      );
      return jsonDecode(response)['data'] ?? false;
    } catch (e) {
      return false;
    }
  }

  /// 扫码推送数据到电视端（TV 模式）。
  /// 电视二维码 URL 路径以 /tv/ 开头；载荷与跨端传输一致（关注+登录+全部设置），
  /// 走请求体而非查询串——全量设置拼接后可达数十 KB，超过 HTTP 头长度上限会被
  /// 电视端直接断连（表现为"同步失败"）。电视端只提取关注与登录态。
  Future<bool> pushDataToTv(String httpAddress) async {
    final backup = Get.find<BackupController>();
    try {
      final response = await HttpClient.instance.postJson(
        '$httpAddress/api/setSettings',
        data: backup.exportTransferData(),
      );
      return jsonDecode(response)['data'] ?? false;
    } catch (e) {
      return false;
    }
  }
}
