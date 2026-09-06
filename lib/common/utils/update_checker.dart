import 'package:package_info_plus/package_info_plus.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:pure_live/common/index.dart';

/// 启动时检查 gitee 上是否发布了更新的版本。
///
/// 版本源是仓库 raw 的 pubspec.yaml（本项目不提供预编译安装包、不发
/// release，master 分支的 version 行即最新版本）。比较 pubspec 的构建号
/// （如 2.0.3+2006 中的 2006），远端高于本地时弹窗提醒，确认后跳转
/// gitee 项目主页。任何网络异常都静默忽略，不打扰使用。
class UpdateChecker {
  static const String projectUrl = 'https://gitee.com/superxyline/purelive';
  static const String _pubspecUrl = '$projectUrl/raw/master/pubspec.yaml';

  static Future<void> check() async {
    try {
      if (!SettingsService.to.app.enableAutoCheckUpdate.v) return;

      final info = await PackageInfo.fromPlatform();
      final localBuild = int.tryParse(info.buildNumber) ?? 0;

      final raw = await HttpClient.instance.getText(_pubspecUrl);
      final match = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(raw);
      final remoteVersion = match?.group(1)?.trim();
      if (remoteVersion == null || remoteVersion.isEmpty) return;
      final remoteBuild = int.tryParse(remoteVersion.split('+').last) ?? 0;
      // 本地更新过、或用户已对该版本选择"忽略此版本"，均不再提醒
      if (remoteBuild <= localBuild || remoteBuild <= SettingsService.to.app.updateIgnoredBuild.v) return;
      final remoteName = remoteVersion.split('+').first;

      await Get.dialog(
        AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(i18n('update_available_title'), style: AppTextStyles.t16Bold),
          content: Text(
            i18n(
              'update_available_body',
              args: {'remote': remoteName, 'local': info.version},
            ),
            style: AppTextStyles.t14.copyWith(height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () {
                // 忽略此版本：记住该构建号，之后不再对该版本弹提醒
                SettingsService.to.app.updateIgnoredBuild.v = remoteBuild;
                Get.back();
              },
              child: Text(i18n('update_later'), style: TextStyle(color: Get.theme.colorScheme.onSurfaceVariant)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Get.theme.colorScheme.primary),
              onPressed: () {
                Get.back();
                launchUrl(Uri.parse(projectUrl), mode: LaunchMode.externalApplication);
              },
              child: Text(i18n('update_go')),
            ),
          ],
        ),
      );
    } catch (_) {
      // 无网络/超时/解析失败：静默跳过
    }
  }
}
