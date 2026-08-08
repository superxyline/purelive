import 'package:pure_live/common/index.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:remixicon/remixicon.dart'; // 🌟 Imported Remix Icons pack

import 'package:package_info_plus/package_info_plus.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  static const String _projectUrl = 'https://gitee.com/superxyline/purelive';

  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final PackageInfo info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() => _appVersion = info.version);
    }
  }
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        physics: const BouncingScrollPhysics(),
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
                    'v$_appVersion',
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
          context.buildGroupTitle(i18n("about")),
          const SizedBox(height: 8),
          context.buildModernCard([
            context.buildTile(
              icon: Remix.shield_user_line, title: i18n("license"), onTap: openLicensePage),
          ]),
          const SizedBox(height: 24),
          context.buildGroupTitle(i18n("project")),
          const SizedBox(height: 8),
          context.buildModernCard([
            context.buildTile(
              icon: Remix.code_s_slash_line,
              title: i18n("project_page"),
              subtitle: _projectUrl,
              isLong: true,
              onTap: () {
                launchUrl(Uri.parse(_projectUrl), mode: LaunchMode.externalApplication);
              },
            ),
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
      applicationVersion: _appVersion,
      useRootNavigator: true,
      applicationIcon: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(width: 60, child: Center(child: Image.asset('assets/icons/icon.png'))),
      ),
    );
  }

}
