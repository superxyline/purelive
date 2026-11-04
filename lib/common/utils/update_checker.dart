import 'dart:convert';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:pure_live/common/index.dart';

/// 检查 Gitee 上是否发布了更新的**发行版（Release）**。
///
/// 版本源优先用 Releases 的 `latest` 接口（能直接反映你发布的最新发行版），
/// 接口不可用时回退到 `custom` 分支 pubspec 的 `version` 行。远端高于本地时：
/// - 启动后弹窗提示，确认后打开项目主页去下载安装包；
/// - 同时把结果写进 [hasUpdate] / [latestVersion]，供「关于 → 项目主页」那行提示。
///
/// 版本比较统一用语义版本编码（`2.3.4` → `20304`），因为 Release tag 里没有
/// build 号；「忽略此版本」也复用 `updateIgnoredBuild` 存这个编码值，口径一致。
/// 任何网络异常都静默忽略，不打扰使用。
class UpdateChecker {
  static const String projectUrl = 'https://gitee.com/superxyline/purelive';
  static const String releasesApi = 'https://gitee.com/api/v5/repos/superxyline/purelive/releases/latest';
  static const String _pubspecUrl = '$projectUrl/raw/custom/pubspec.yaml';

  /// 远端最新发行版版本号（如 `2.3.4`），未检查或检查失败时为空
  static final Rxn<String> latestVersion = Rxn<String>();

  /// 是否发现比当前更高的发行版，供关于页做行内提示
  static final RxBool hasUpdate = false.obs;

  /// 是否已经完成过一次检查（关于页据此决定要不要自己补一次）
  static bool get checked => _checked;
  static bool _checked = false;

  /// 把 `2.3.4` 编码成可比较的整数（Major*10000 + Minor*100 + Patch）。
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

      final remote = await _fetchRemoteVersion();
      // 只有真正拿到远端版本才算"检查过"；断网/接口异常时留待下次重试
      if (remote == null) return;
      _checked = true;

      final remoteCode = versionCode(remote);
      latestVersion.value = remote;
      hasUpdate.value = remoteCode > localCode;
      if (!hasUpdate.value || !showDialog) return;
      // 用户已对同一版本选择过「忽略此版本」
      if (remoteCode <= SettingsService.to.app.updateIgnoredBuild.v) return;

      await Get.dialog(
        AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(i18n('update_available_title'), style: AppTextStyles.t16Bold),
          content: Text(
            i18n(
              'update_available_body',
              args: {'remote': remote, 'local': localVersion},
            ),
            style: AppTextStyles.t14.copyWith(height: 1.6),
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

  /// 取远端最新发行版版本号；先走 Releases 接口，失败再回退 pubspec。
  static Future<String?> _fetchRemoteVersion() async {
    try {
      final raw = await HttpClient.instance.getText(releasesApi);
      if (raw.isNotEmpty) {
        final dynamic decoded = jsonDecode(raw);
        if (decoded is Map) {
          final tag = (decoded['tag_name'] ?? decoded['name'] ?? '').toString();
          final version = normalizeVersion(tag);
          if (version != null) return version;
        }
      }
    } catch (_) {
      // Releases 接口不可用（未发布过发行版 / 频率限制 / 断网），继续回退
    }

    try {
      final raw = await HttpClient.instance.getText(_pubspecUrl);
      final match = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(raw);
      return normalizeVersion(match?.group(1) ?? '');
    } catch (_) {
      return null;
    }
  }

  /// 从 `v2.3.4` / `2.3.4+4041` / `Pure Live v2.3.4` 里取出 `2.3.4`。
  static String? normalizeVersion(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;
    if (text.startsWith('v') || text.startsWith('V')) text = text.substring(1);
    final match = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(text);
    if (match == null) return null;
    return '${match.group(1)}.${match.group(2)}.${match.group(3)}';
  }
}
