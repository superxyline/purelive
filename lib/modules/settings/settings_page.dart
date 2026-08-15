import 'package:remixicon/remixicon.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/backup/backup_page.dart';
import 'package:pure_live/modules/settings/pages/refresh_settings.dart';
import 'package:pure_live/modules/settings/pages/theme_settings_page.dart';
import 'package:pure_live/modules/settings/pages/video_settings_page.dart';
import 'package:pure_live/modules/settings/pages/local_config_preveiw.dart';
import 'package:pure_live/modules/settings/pages/general_settings_page.dart';
import 'package:pure_live/modules/settings/pages/page_settings.dart';
import 'package:pure_live/modules/settings/pages/platform_settings_page.dart';
import 'package:pure_live/modules/settings/pages/danmaku_settings_page.dart';
import 'package:pure_live/modules/settings/pages/font_and_text_page.dart';
import 'package:pure_live/modules/settings/pages/language_settings_page.dart';
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
          // 播放设置（视频播放 / 弹幕 / 播放器内核）
          context.buildGroupTitle(i18n("playback_settings")),
          context.buildModernCard([
            context.buildTile(
              icon: Remix.film_line,
              title: i18n("video"),
              subtitle: i18n("video_desc"),
              onTap: () => Get.to(() => const VideoSettingsPage()),
            ),
            context.buildTile(
              icon: Remix.chat_smile_2_line,
              title: i18n("danmaku_settings"),
              subtitle: i18n("danmaku_settings_desc"),
              onTap: () => Get.to(() => const DanmakuSettingsPage()),
            ),
            context.buildTile(
              icon: Remix.cpu_line,
              title: i18n("player_kernel"),
              subtitle: i18n("player_kernel_desc"),
              onTap: () => Get.to(() => const PlayerKernelSettingsPage()),
            ),
          ]),

          // 外观与显示（主题 / 字体字号 / 导航显示 / 页面设置）
          const SizedBox(height: 20),
          context.buildGroupTitle(i18n("appearance_settings")),
          context.buildModernCard([
            context.buildTile(
              icon: Remix.palette_line,
              title: i18n("theme_customization"),
              subtitle: i18n("theme_customization_desc"),
              onTap: () => Get.to(() => const ThemeSettingsPage()),
            ),
            context.buildTile(
              icon: Remix.font_size,
              title: i18n("font_text_settings"),
              subtitle: i18n("font_text_settings_desc"),
              onTap: () => Get.to(() => const FontAndTextPage()),
            ),
            context.buildTile(
              icon: Remix.menu_line,
              title: i18n("navigation_display_settings"),
              subtitle: i18n("navigation_display_settings_desc"),
              onTap: () => Get.to(() => NavigationSettingsPage()),
            ),
            if (Get.width > 680)
              context.buildTile(
                icon: Remix.pages_line,
                title: i18n("page_settings"),
                subtitle: i18n("page_settings_subtitle"),
                onTap: () => Get.to(() => const PageSettingsPage()),
              ),
          ]),

          // 平台与账号（平台 / 账号与同步 / 标签管理）
          const SizedBox(height: 20),
          context.buildGroupTitle(i18n("platform_account_settings")),
          context.buildModernCard([
            context.buildTile(
              icon: Remix.apps_2_line,
              title: i18n("platform_settings"),
              subtitle: i18n("platform_settings_desc"),
              onTap: () => Get.to(() => const PlatformSettingsPage()),
            ),
            context.buildTile(
              icon: Remix.account_circle_line,
              title: i18n("account_sync"),
              subtitle: i18n("account_sync_desc"),
              onTap: () => Get.toNamed(RoutePath.kSettingsAccount),
            ),
            context.buildTile(
              icon: Remix.price_tag_3_line,
              title: i18n("tag_management"),
              subtitle: i18n("tag_management_desc"),
              onTap: () => Get.toNamed(RoutePath.kSettingsTags),
            ),
          ]),

          // 网络与数据（网络代理 / 缓存与数据 / 备份与恢复）
          const SizedBox(height: 20),
          context.buildGroupTitle(i18n("network_data_settings")),
          context.buildModernCard([
            context.buildTile(
              icon: Remix.global_line,
              title: i18n("custom_network_proxy"),
              subtitle: i18n("custom_network_proxy_desc"),
              onTap: () => Get.to(() => const NetworkProxySettingsPage()),
            ),
            context.buildTile(
              icon: Remix.database_2_line,
              title: i18n("cache_and_data"),
              subtitle: i18n("cache_and_data_desc"),
              onTap: () => Get.to(() => const CacheDataSettingsPage()),
            ),
            context.buildTile(
              icon: Remix.cloud_line,
              title: i18n("backup_recover"),
              subtitle: i18n("backup_recover_desc"),
              onTap: () => Get.to(() => const BackupPage()),
            ),
          ]),

          // 通用（通用 / 刷新设置 / 语言）
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
              icon: Remix.global_line,
              title: i18n("language_settings"),
              subtitle: i18n("language_settings_desc"),
              onTap: () => Get.to(() => const LanguageSettingsPage()),
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
