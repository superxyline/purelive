import 'package:pure_live/common/index.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:remixicon/remixicon.dart'; // 🌟 Imported Remix Icons pack

import 'features_page.dart';
import 'package:pure_live/common/utils/update_checker.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  static const String kProjectUrl = 'https://gitee.com/superxyline/purelive';
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
    // 启动时的检查可能还没跑完（或用户关了自动检查），关于页自己补一次：
    // 只刷新状态不弹窗，保证「项目主页」那行能显示有无新发行版。
    if (!UpdateChecker.checked) UpdateChecker.check(showDialog: false, force: true);
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _version = info.version);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        physics: const PureLiveScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: <Widget>[
          Center(
            child: Column(
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 1000),
                  curve: Curves.elasticOut,
                  builder: (context, value, child) {
                    return Transform.scale(scale: value, child: child);
                  },
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.08), width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.primary.withValues(alpha: 0.06),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Image.asset('assets/icons/icon.png', fit: BoxFit.contain),
                  ),
                ),

                const SizedBox(height: 18),
                Text(
                  i18n("app_name"),
                  style: AppTextStyles.t18.copyWith(fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.dividerColor.withValues(alpha: 0.05), width: 0.5),
                  ),
                  child: Text(
                    'v$_version',
                    style: AppTextStyles.t11.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
              ],
            ),
          ),
          context.buildGroupTitle(i18n("features")),
          const SizedBox(height: 8),
          context.buildModernCard([
            buildTile(
              icon: Remix.apps_2_line,
              title: i18n("features"),
              subtitle: i18n('features_summary', args: {'count': '${FeaturesPage.featureCount}'}),
              onTap: () => Get.to(() => const FeaturesPage()),
            ),
          ]),
          const SizedBox(height: 24),
          context.buildGroupTitle(i18n("about")),
          const SizedBox(height: 8),
          context.buildModernCard([
            context.buildTile(icon: Remix.shield_user_line, title: i18n("license"), onTap: openLicensePage),
          ]),
          const SizedBox(height: 24),
          context.buildGroupTitle(i18n("project")),
          const SizedBox(height: 8),
          context.buildModernCard([
            Obx(() {
              final bool hasUpdate = UpdateChecker.hasUpdate.value;
              final String? latest = UpdateChecker.latestVersion.value;
              final bool showUpdate = hasUpdate && latest != null;
              return context.buildTile(
                icon: Remix.code_s_slash_line,
                title: i18n("project_page"),
                // 有新发行版时把地址换成更新提示；点击仍然打开项目主页下载
                subtitle: showUpdate
                    ? i18n('update_about_hint', args: {'version': latest})
                    : kProjectUrl,
                subtitleColor: showUpdate ? theme.colorScheme.error : null,
                isLong: true,
                // 徽标 + 原本的箭头，保留"可点击"的提示
                trailing: showUpdate
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildUpdateBadge(theme),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: theme.hintColor.withValues(alpha: 0.4),
                            size: 20,
                          ),
                        ],
                      )
                    : null,
                onTap: () {
                  launchUrl(Uri.parse(kProjectUrl), mode: LaunchMode.externalApplication);
                },
              );
            }),
            buildTile(
              icon: Remix.error_warning_line,
              title: i18n("project_alert"),
              subtitle: i18n("app_legalese"),
              isLong: true,
              iconColor: theme.colorScheme.error,
            ),
          ]),
        ],
      ),
    );
  }

  /// 「项目主页」行右侧的更新徽标
  Widget _buildUpdateBadge(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.error.withValues(alpha: 0.4)),
      ),
      child: Text(
        i18n('update_badge_new'),
        style: TextStyle(color: theme.colorScheme.error, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget buildTile({
    required String title,
    IconData? icon,
    String? subtitle,
    VoidCallback? onTap,
    Color? iconColor,
    Color? subtitleColor,
    Widget? trailing,
    bool isLong = false,
  }) {
    final theme = Get.theme;
    final bool hasSubtitle = subtitle != null && subtitle.isNotEmpty;

    return ListTile(
      leading: null,
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 3, right: 12),
              child: Icon(icon, color: iconColor ?? theme.colorScheme.primary, size: 22),
            ),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: AppTextStyles.t15.copyWith(fontWeight: FontWeight.w600, height: 1.2)),
                if (hasSubtitle) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      subtitle,
                      style: AppTextStyles.t12.copyWith(
                        color: subtitleColor ?? theme.hintColor.withValues(alpha: 0.75),
                        height: 1.3,
                      ),
                      maxLines: isLong ? null : 1,
                      overflow: isLong ? TextOverflow.visible : TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      trailing:
          trailing ??
          (onTap != null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(Icons.chevron_right_rounded, color: theme.hintColor.withValues(alpha: 0.4), size: 20),
                    ),
                  ],
                )
              : null),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    );
  }

  void openLicensePage() {
    showLicensePage(
      context: Get.context!,
      applicationName: i18n("app_name"),
      applicationLegalese: i18n("app_legalese"),
      applicationVersion: _version,
      useRootNavigator: true,
      applicationIcon: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(width: 60, child: Center(child: Image.asset('assets/icons/icon.png'))),
      ),
    );
  }
}
