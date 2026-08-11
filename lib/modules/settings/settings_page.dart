import 'package:remixicon/remixicon.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/backup/backup_page.dart';
import 'package:pure_live/modules/settings/pages/refresh_settings.dart';
import 'package:pure_live/modules/settings/pages/theme_settings_page.dart';
import 'package:pure_live/modules/settings/pages/video_settings_page.dart';
import 'package:pure_live/modules/settings/pages/local_config_preveiw.dart';
import 'package:pure_live/modules/settings/pages/general_settings_page.dart';
import 'package:pure_live/modules/settings/pages/platform_settings_page.dart';
import 'package:pure_live/modules/settings/pages/navigation_settings_page.dart';
import 'package:pure_live/modules/settings/pages/cache_data_settings_page.dart';
import 'package:pure_live/modules/settings/pages/network_proxy_settings_page.dart';
import 'package:pure_live/modules/settings/pages/player_kernel_settings_page.dart';

class SettingsPage extends GetView<SettingsService> {
  const SettingsPage({super.key});

  BuildContext get context => Get.context!;

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      appBar: AppBar(
        scrolledUnderElevation: screenWidth > 640 ? 0 : null,
        title: Text(i18n("settings_title")),
        actions: [
          TextButton(
            onPressed: () => Get.to(() => LocalConfigPreviewPage()),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [Icon(Remix.file_text_line, size: 18), const SizedBox(width: 4), Text(i18n("config_preview"))],
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // 主题设置
          context.buildGroupTitle(i18n("theme_settings")),
          context.buildModernCard([
            context.buildTile(
              icon: Remix.palette_line,
              title: i18n("theme_customization"),
              subtitle: i18n("theme_customization_desc"),
              onTap: () => Get.to(() => const ThemeSettingsPage()),
            ),
          ]),

          // 视频设置（含播放器内核）
          const SizedBox(height: 20),
          context.buildGroupTitle(i18n("video_settings")),
          context.buildModernCard([
            context.buildTile(
              icon: Remix.film_line,
              title: i18n("video"),
              subtitle: i18n("video_desc"),
              onTap: () => Get.to(() => const VideoSettingsPage()),
            ),
            context.buildTile(
              icon: Remix.cpu_line,
              title: i18n("player_kernel"),
              subtitle: i18n("player_kernel_desc"),
              onTap: () => Get.to(() => const PlayerKernelSettingsPage()),
            ),
          ]),

          // 通用设置（含刷新、导航栏显示、平台显示与授权、自定义网络代理）
          const SizedBox(height: 20),
          context.buildGroupTitle(i18n("general_settings")),
          context.buildModernCard([
            context.buildTile(
              icon: Remix.settings_4_line,
              title: i18n("general"),
              subtitle: i18n("general_desc"),
              onTap: () => Get.to(() => const GeneralSettingsPage()),
            ),
            context.buildTile(
              icon: Remix.refresh_line,
              title: i18n("refresh_settings"),
              subtitle: i18n("refresh_settings_subtitle"),
              onTap: () => Get.to(() => const RefreshSettingsPage()),
            ),
            context.buildTile(
              icon: Remix.menu_line,
              title: i18n("navigation_display_settings"),
              subtitle: i18n("navigation_display_settings_desc"),
              onTap: () => Get.to(() => NavigationSettingsPage()),
            ),
            context.buildTile(
              icon: Remix.apps_2_line,
              title: i18n("platform_settings"),
              subtitle: i18n("platform_settings_desc"),
              onTap: () => Get.to(() => const PlatformSettingsPage()),
            ),
            context.buildTile(
              icon: Remix.global_line,
              title: i18n("custom_network_proxy"),
              subtitle: i18n("custom_network_proxy_desc"),
              onTap: () => Get.to(() => const NetworkProxySettingsPage()),
            ),
          ]),

          // 数据管理
          const SizedBox(height: 20),
          context.buildGroupTitle(i18n("data_manage")),
          context.buildModernCard([
            context.buildTile(
              icon: Remix.database_2_line,
              title: i18n("cache_and_data"),
              subtitle: i18n("cache_and_data_desc"),
              onTap: () => Get.to(() => const CacheDataSettingsPage()),
            ),
          ]),

          // 备份管理
          const SizedBox(height: 20),
          context.buildGroupTitle(i18n("backup_manage")),
          context.buildModernCard([
            context.buildTile(
              icon: Remix.cloud_line,
              title: i18n("backup_recover"),
              subtitle: i18n("backup_recover_desc"),
              onTap: () => Get.to(() => const BackupPage()),
            ),
          ]),

          // 关于
          const SizedBox(height: 20),
          context.buildGroupTitle(i18n("about")),
          context.buildModernCard([
            context.buildTile(
              icon: Remix.information_line,
              title: i18n("about"),
              subtitle: i18n("about_desc"),
              onTap: () => Get.toNamed(RoutePath.kAbout),
            ),
          ]),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
