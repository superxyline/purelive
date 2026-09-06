import 'package:remixicon/remixicon.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/settings/pages/general_settings_page.dart';
import 'package:pure_live/modules/settings/pages/language_settings_page.dart';
import 'package:pure_live/modules/settings/pages/navigation_settings_page.dart';
import 'package:pure_live/modules/settings/pages/network_proxy_settings_page.dart';
import 'package:pure_live/modules/settings/pages/pip_danmaku_settings_page.dart';
import 'package:pure_live/modules/settings/pages/platform_settings_page.dart';
import 'package:pure_live/modules/settings/pages/player_kernel_settings_page.dart';
import 'package:pure_live/modules/settings/pages/refresh_settings.dart';
import 'package:pure_live/modules/settings/pages/theme_settings_page.dart';
import 'package:pure_live/modules/settings/pages/video_settings_page.dart';

/// 设置项全局搜索：按标题/所属分组过滤，点击直达对应设置页。
/// 索引只收录各设置页的代表性条目，新设置项在 [_entries] 中补充。
class SettingsSearchPage extends StatefulWidget {
  const SettingsSearchPage({super.key});

  @override
  State<SettingsSearchPage> createState() => _SettingsSearchPageState();
}

class _SettingsSearchEntry {
  final String titleKey;
  final String groupKey;
  final Widget page;

  const _SettingsSearchEntry(this.titleKey, this.groupKey, this.page);
}

class _SettingsSearchPageState extends State<SettingsSearchPage> {
  String _keyword = '';

  static const List<_SettingsSearchEntry> _entries = [
    // ===== 视频设置 =====
    _SettingsSearchEntry('prefer_resolution', 'video', VideoSettingsPage()),
    _SettingsSearchEntry('mobile_quality', 'video', VideoSettingsPage()),
    _SettingsSearchEntry('prefer_hevc', 'video', VideoSettingsPage()),
    _SettingsSearchEntry('cdn_speed_test', 'video', VideoSettingsPage()),
    _SettingsSearchEntry('enable_fullscreen_default', 'video', VideoSettingsPage()),
    _SettingsSearchEntry('enable_asmr_sleep_mode', 'video', VideoSettingsPage()),
    _SettingsSearchEntry('enable_background_play', 'video', VideoSettingsPage()),
    // ===== 播放内核 =====
    _SettingsSearchEntry('audio_only_mode', 'player_kernel', PlayerKernelSettingsPage()),
    _SettingsSearchEntry('enable_codec', 'player_kernel', PlayerKernelSettingsPage()),
    _SettingsSearchEntry('anime4k_super_resolution', 'player_kernel', PlayerKernelSettingsPage()),
    _SettingsSearchEntry('live_buffer_size', 'player_kernel', PlayerKernelSettingsPage()),
    _SettingsSearchEntry('volume_normalization', 'player_kernel', PlayerKernelSettingsPage()),
    _SettingsSearchEntry('video_output_driver', 'player_kernel', PlayerKernelSettingsPage()),
    _SettingsSearchEntry('hardware_decoder', 'player_kernel', PlayerKernelSettingsPage()),
    _SettingsSearchEntry('compat_mode', 'player_kernel', PlayerKernelSettingsPage()),
    _SettingsSearchEntry('custom_output_hwdec', 'player_kernel', PlayerKernelSettingsPage()),
    _SettingsSearchEntry('force_destroy_player', 'player_kernel', PlayerKernelSettingsPage()),
    // ===== PiP / 弹幕 =====
    _SettingsSearchEntry('pip_danmaku', 'video', PipDanmakuSettingsPage()),
    // ===== 通用 =====
    _SettingsSearchEntry('high_refresh_rate', 'general', GeneralSettingsPage()),
    _SettingsSearchEntry('show_live_duration', 'general', GeneralSettingsPage()),
    _SettingsSearchEntry('splash_animation', 'general', GeneralSettingsPage()),
    _SettingsSearchEntry('enable_auto_check_update', 'general', GeneralSettingsPage()),
    _SettingsSearchEntry('esports_reminder_lead', 'general', GeneralSettingsPage()),
    _SettingsSearchEntry('enable_countdown_close', 'general', GeneralSettingsPage()),
    _SettingsSearchEntry('audience_metric_settings', 'general', GeneralSettingsPage()),
    _SettingsSearchEntry('custom_network_proxy', 'general', NetworkProxySettingsPage()),
    // ===== 首页与内容 =====
    _SettingsSearchEntry('navigation_display_settings', 'settings_group_home_content', NavigationSettingsPage()),
    _SettingsSearchEntry('platform_settings', 'settings_group_home_content', PlatformSettingsPage()),
    _SettingsSearchEntry('refresh_settings', 'settings_group_home_content', RefreshSettingsPage()),
    _SettingsSearchEntry('dense_favorites', 'settings_group_home_content', NavigationSettingsPage()),
    // ===== 外观与语言 =====
    _SettingsSearchEntry('theme_customization', 'settings_group_appearance', ThemeSettingsPage()),
    _SettingsSearchEntry('language_settings', 'settings_group_appearance', LanguageSettingsPage()),
  ];

  List<_SettingsSearchEntry> get _filtered {
    final keyword = _keyword.trim().toLowerCase();
    if (keyword.isEmpty) return _entries;
    return _entries.where((entry) {
      final title = i18n(entry.titleKey).toLowerCase();
      final group = i18n(entry.groupKey).toLowerCase();
      return title.contains(keyword) || group.contains(keyword);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = _filtered;
    return Scaffold(
      appBar: AppBar(title: Text(i18n('settings_search'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              autofocus: true,
              onChanged: (value) => setState(() => _keyword = value),
              decoration: InputDecoration(
                hintText: i18n('settings_search_hint'),
                prefixIcon: const Icon(Remix.search_line, size: 20),
                isDense: true,
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerLow,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          Expanded(
            child: results.isEmpty
                ? Center(
                    child: Text(
                      i18n('settings_search_empty'),
                      style: AppTextStyles.t14.copyWith(color: theme.hintColor),
                    ),
                  )
                : ListView.builder(
                    physics: const PureLiveScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    itemCount: results.length,
                    itemBuilder: (context, index) {
                      final entry = results[index];
                      return ListTile(
                        leading: Icon(
                          Remix.settings_4_line,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        title: Text(i18n(entry.titleKey)),
                        subtitle: Text(
                          i18n(entry.groupKey),
                          style: AppTextStyles.t12.copyWith(color: theme.hintColor),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        dense: true,
                        onTap: () => Get.to(() => entry.page),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
