import 'dart:convert';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:pure_live/common/index.dart';

/// 检查 Gitee 上是否发布了更新的**发行版（Release）**。
///
/// 版本源优先用 Releases 的 `latest` 接口（能直接反映你发布的最新发行版），
/// 接口不可用时回退到 `custom` 分支 pubspec 的 `version` 行。远端高于本地时：
/// - 启动后弹窗提示（含该版本的更新内容），确认后打开项目主页下载；
/// - 同时把结果写进 [hasUpdate] / [latestVersion] / [latestBody]，供关于页提示。
///
/// 版本比较统一用语义版本编码（`2.3.5` → `20305`），因为 Release tag 里没有
/// build 号；「忽略此版本」也复用 `updateIgnoredBuild` 存这个编码值，口径一致。
/// 任何网络异常都静默忽略，不打扰使用。
class UpdateChecker {
  static const String projectUrl = 'https://gitee.com/superxyline/purelive';
  static const String releasesApi = 'https://gitee.com/api/v5/repos/superxyline/purelive/releases/latest';
  static const String _pubspecUrl = '$projectUrl/raw/custom/pubspec.yaml';

  /// 远端最新发行版版本号（如 `2.3.5`），未检查或检查失败时为空
  static final Rxn<String> latestVersion = Rxn<String>();

  /// 远端发行版的正文（更新说明原文），用于弹窗展示"这个版本更新了什么"
  static final RxString latestBody = RxString('');

  /// 是否发现比当前更高的发行版，供关于页做行内提示
  static final RxBool hasUpdate = false.obs;

  /// 是否已经完成过一次检查（关于页据此决定要不要自己补一次）
  static bool get checked => _checked;
  static bool _checked = false;

  /// 把 `2.3.5` 编码成可比较的整数（Major*10000 + Minor*100 + Patch）。
  static int versionCode(String version) {
    final parts = version.trim().split('.');
    if (parts.length < 3) return 0;
    final major = int.tryParse(parts[0]) ?? 0;
    final minor = int.tryParse(parts[1]) ?? 0;
    final patch = int.tryParse(parts[2]) ?? 0;
    return major * 10000 + minor * 100 + patch;
  }

  /// [showDialog] 为 false 时只刷新状态、不弹窗（关于页用）。
  /// [force] 为 true 时忽略「自动检查」开关——用户主动打开关于页时
  /// 仍然应该看到有没有新发行版。
  static Future<void> check({bool showDialog = true, bool force = false}) async {
    try {
      if (!force && !SettingsService.to.app.enableAutoCheckUpdate.v) return;

      final info = await PackageInfo.fromPlatform();
      final localVersion = info.version;
      final localCode = versionCode(localVersion);

      final remote = await _fetchRemoteRelease();
      // 只有真正拿到远端版本才算"检查过"；断网/接口异常时留待下次重试
      if (remote == null) return;
      _checked = true;

      final remoteCode = versionCode(remote.version);
      latestVersion.value = remote.version;
      latestBody.value = remote.body;
      hasUpdate.value = remoteCode > localCode;
      if (!hasUpdate.value || !showDialog) return;
      // 用户已对同一版本选择过「忽略此版本」
      if (remoteCode <= SettingsService.to.app.updateIgnoredBuild.v) return;

      final changelog = cleanChangelog(remote.body);
      await Get.dialog(
        AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(i18n('update_available_title'), style: AppTextStyles.t16Bold),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  i18n('update_available_body', args: {'remote': remote.version, 'local': localVersion}),
                  style: AppTextStyles.t14.copyWith(height: 1.5),
                ),
                if (changelog.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(i18n('update_changelog_title'), style: AppTextStyles.t13Medium),
                  const SizedBox(height: 6),
                  // 更新说明可能很长，限高滚动，避免弹窗撑满屏幕
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: Get.height * 0.36),
                    child: SingleChildScrollView(
                      child: Text(
                        changelog,
                        style: AppTextStyles.t12.copyWith(height: 1.55),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                // 忽略此版本：记住该版本编码，之后不再对该版本弹提醒
                SettingsService.to.app.updateIgnoredBuild.v = remoteCode;
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

  /// 把 Release 正文整理成可读的纯文本：只留当前版本段落，去掉 Markdown 标记。
  static String cleanChangelog(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return '';
    // 正文里 "---" 之后是更早版本的内容，截断
    final cut = text.indexOf('\n---');
    if (cut > 0) text = text.substring(0, cut);
    final lines = text.split('\n');
    // 首行通常是 "# Pure Live vX.Y.Z"，与弹窗标题重复，去掉
    if (lines.isNotEmpty && RegExp(r'^#+\s*Pure Live').hasMatch(lines.first.trim())) {
      lines.removeAt(0);
    }
    text = lines.join('\n');
    text = text.replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '');
    text = text.replaceAll(RegExp(r'\*\*(.+?)\*\*'), r'$1');
    text = text.replaceAll('`', '');
    return text.trim();
  }

  /// 取远端最新发行版（版本号 + 正文）；先走 Releases 接口，失败再回退 pubspec。
  static Future<_RemoteRelease?> _fetchRemoteRelease() async {
    try {
      final raw = await HttpClient.instance.getText(releasesApi);
      if (raw.isNotEmpty) {
        final dynamic decoded = jsonDecode(raw);
        if (decoded is Map) {
          final tag = (decoded['tag_name'] ?? decoded['name'] ?? '').toString();
          final version = normalizeVersion(tag);
          if (version != null) {
            return _RemoteRelease(version, (decoded['body'] ?? '').toString());
          }
        }
      }
    } catch (_) {
      // Releases 接口不可用（未发布过发行版 / 频率限制 / 断网），继续回退
    }

    try {
      final raw = await HttpClient.instance.getText(_pubspecUrl);
      final match = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(raw);
      final version = normalizeVersion(match?.group(1) ?? '');
      // pubspec 回退时没有更新说明
      return version == null ? null : _RemoteRelease(version, '');
    } catch (_) {
      return null;
    }
  }

  /// 从 `v2.3.5` / `2.3.5+4042` / `Pure Live v2.3.5` 里取出 `2.3.5`。
  static String? normalizeVersion(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;
    if (text.startsWith('v') || text.startsWith('V')) text = text.substring(1);
    final match = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(text);
    if (match == null) return null;
    return '${match.group(1)}.${match.group(2)}.${match.group(3)}';
  }
}

class _RemoteRelease {
  const _RemoteRelease(this.version, this.body);

  final String version;
  final String body;
}
