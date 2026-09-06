import 'package:remixicon/remixicon.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/backup/backup_page.dart';
import 'package:pure_live/modules/settings/pages/refresh_settings.dart';
import 'package:pure_live/modules/settings/pages/theme_settings_page.dart';
import 'package:pure_live/modules/settings/pages/video_settings_page.dart';
import 'package:pure_live/modules/settings/pages/pip_danmaku_settings_page.dart';
import 'package:pure_live/modules/settings/pages/local_config_preveiw.dart';
import 'package:pure_live/modules/settings/pages/general_settings_page.dart';
import 'package:pure_live/modules/settings/pages/platform_settings_page.dart';
import 'package:pure_live/modules/settings/pages/navigation_settings_page.dart';
import 'package:pure_live/modules/settings/pages/cache_data_settings_page.dart';
import 'package:pure_live/modules/settings/pages/network_proxy_settings_page.dart';
import 'package:pure_live/modules/settings/pages/player_kernel_settings_page.dart';
import 'package:pure_live/modules/settings/pages/local_interaction_settings_page.dart';
import 'package:pure_live/modules/settings/pages/language_settings_page.dart';
import 'package:pure_live/modules/settings/pages/font_and_text_page.dart';
import 'package:pure_live/modules/settings/pages/settings_search_page.dart';
import 'package:pure_live/common/services/settings/bilibili_account_service.dart';

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
          IconButton(
            tooltip: i18n('settings_search'),
            icon: const Icon(Remix.search_line, size: 20),
            onPressed: () => Get.to(() => const SettingsSearchPage()),
          ),
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
        physics: const PureLiveScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // ===== 账号与同步（高频：登录、同步关注都在这） =====
          context.buildGroupTitle(i18n("settings_group_account")),
          context.buildModernCard([
            Obx(() {
              final cookie = SettingsService.to.cookieManager;
              final loggedPlatforms = <String>[
                if (BiliBiliAccountService.instance.logined.v) i18n("site_bilibili"),
                if (cookie.huyaCookie.v.isNotEmpty) i18n("site_huya"),
                if (cookie.douyuCookie.v.isNotEmpty) i18n("site_douyu"),
                if (cookie.douyinCookie.v.isNotEmpty) i18n("site_douyin"),
              ];
              final subtitle = loggedPlatforms.isEmpty
                  ? i18n("account_sync_none_logged")
                  : i18n("account_sync_logged", args: {"platforms": loggedPlatforms.join("、")});
              return context.buildTile(
                icon: Remix.user_3_line,
                title: i18n('third_party_auth'),
                subtitle: subtitle,
                onTap: () => Get.toNamed(RoutePath.kSettingsAccount),
              );
            }),
            context.buildTile(
              icon: Remix.price_tag_3_line,
              title: i18n('tag_management'),
              onTap: () => Get.toNamed(RoutePath.kSettingsTags),
            ),
          ]),

          const SizedBox(height: 20),
          // ===== 播放体验 =====
          context.buildGroupTitle(i18n("settings_group_video_playback")),
          context.buildModernCard([
            context.buildTile(
              icon: Remix.film_line,
              title: i18n("video"),
              subtitle: i18n("video_desc"),
              onTap: () => Get.to(() => const VideoSettingsPage()),
            ),
            context.buildTile(
              icon: Remix.picture_in_picture_2_line,
              title: i18n('pip_danmaku'),
              subtitle: i18n('pip_danmaku_desc'),
              onTap: () => Get.to(() => const PipDanmakuSettingsPage()),
            ),
            context.buildTile(
              icon: Remix.cpu_line,
              title: i18n("player_kernel"),
              subtitle: i18n("player_kernel_desc"),
              onTap: () => Get.to(() => const PlayerKernelSettingsPage()),
            ),
            context.buildTile(
              icon: Icons.auto_awesome_rounded,
              title: i18n('local_interaction_title'),
              subtitle: i18n('local_interaction_settings_desc'),
              onTap: () => Get.to(() => const LocalInteractionSettingsPage()),
            ),
          ]),

          const SizedBox(height: 20),
          // ===== 首页与内容 =====
          context.buildGroupTitle(i18n("settings_group_home_content")),
          context.buildModernCard([
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
              icon: Remix.refresh_line,
              title: i18n("refresh_settings"),
              subtitle: i18n("refresh_settings_subtitle"),
              onTap: () => Get.to(() => const RefreshSettingsPage()),
            ),
            context.buildSwitchTile(
              icon: Remix.layout_grid_line,
              title: i18n("dense_favorites"),
              subtitle: i18n("dense_favorites_desc"),
              value: SettingsService.to.app.enableDenseFavorites,
            ),
          ]),

          const SizedBox(height: 20),
          // ===== 外观与文字 =====
          context.buildGroupTitle(i18n("settings_group_appearance")),
          context.buildModernCard([
            context.buildTile(
              icon: Remix.palette_line,
              title: i18n("theme_customization"),
              subtitle: i18n("theme_customization_desc"),
              onTap: () => Get.to(() => const ThemeSettingsPage()),
            ),
            context.buildTile(
              icon: Remix.font_size_2,
              title: i18n("font_text_settings"),
              subtitle: i18n("font_text_settings_desc"),
              onTap: () => Get.to(() => const FontAndTextPage()),
            ),
            context.buildTile(
              icon: Remix.translate,
              title: i18n("language_settings"),
              subtitle: i18n("language_settings_desc"),
              onTap: () => Get.to(() => const LanguageSettingsPage()),
            ),
          ]),

          const SizedBox(height: 20),
          // ===== 通用 =====
          context.buildGroupTitle(i18n("general")),
          context.buildModernCard([
            context.buildTile(
              icon: Remix.settings_4_line,
              title: i18n("general"),
              subtitle: i18n("general_desc"),
              onTap: () => Get.to(() => const GeneralSettingsPage()),
            ),
            context.buildTile(
              icon: Remix.translate_2,
              title: i18n("language_settings"),
              subtitle: i18n("language_settings_desc"),
              onTap: () => Get.to(() => const LanguageSettingsPage()),
            ),
            context.buildTile(
              icon: Remix.shield_keyhole_line,
              title: i18n("custom_network_proxy"),
              subtitle: i18n("custom_network_proxy_desc"),
              onTap: () => Get.to(() => const NetworkProxySettingsPage()),
            ),
          ]),

          const SizedBox(height: 20),
          // ===== 关于 =====
          context.buildGroupTitle(i18n("about")),
          context.buildModernCard([
            context.buildTile(
              icon: Remix.information_line,
              title: i18n("about"),
              onTap: () => Get.toNamed(RoutePath.kAbout),
            ),
          ]),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
