import 'dart:io';

import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/widgets/settings/settings_card_v2.dart';
import 'package:pure_live/common/widgets/settings/settings_switch.dart';
import 'package:pure_live/common/widgets/utils.dart';
import 'package:pure_live/modules/backup/backup_page.dart';
import 'package:pure_live/modules/settings/settings_page.dart';
import 'package:pure_live/modules/util/time_util.dart';
import 'package:remixicon/remixicon.dart';

class SettingsPageV2 extends GetView<SettingsService> {
  const SettingsPageV2({super.key});

  BuildContext get context => Get.context!;

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    return Scaffold(
      appBar: AppBar(
        scrolledUnderElevation: screenWidth > 640 ? 0 : null,
        title: Text(S.current.settings_title),
      ),
      body: ListView(physics: const BouncingScrollPhysics(), children: [
        SettingsCardV2(children: [
          // 外观设置
          ListTile(
            leading: const Icon(Remix.moon_line),
            title: Text(S.current.settings_app),
            trailing: const Icon(
              Icons.chevron_right,
              color: Colors.grey,
            ),
            onTap: () {
              settingMineInfoSheet();
            },
          ),

          /// 主页设置
          ListTile(
            leading: const Icon(Remix.home_2_line),
            title: Text(S.current.settings_home),
            trailing: const Icon(
              Icons.chevron_right,
              color: Colors.grey,
            ),
            onTap: () {
              settingHomeInfoSheet();
            },
          ),
          ListTile(
            leading: const Icon(Remix.play_circle_line),
            title: Text(S.current.settings_player),
            trailing: const Icon(
              Icons.chevron_right,
              color: Colors.grey,
            ),
            onTap: () {
              settingPlayerInfoSheet();
            },
          ),

          /// 弹幕设置
          ListTile(
            leading: const Icon(Remix.text),
            title: Text(S.current.settings_danmaku_title),
            trailing: const Icon(
              Icons.chevron_right,
              color: Colors.grey,
            ),
            onTap: () async {
              settingDanmakuInfoSheet();
            },
          ),
          ListTile(
            leading: const Icon(Remix.heart_line),
            title: Text(S.current.settings_favorite),
            trailing: const Icon(
              Icons.chevron_right,
              color: Colors.grey,
            ),
            onTap: () {
              settingFavoriteInfoSheet();
            },
          ),
          ListTile(
            leading: const Icon(Remix.timer_2_line),
            title: Text(S.current.settings_time_close),
            trailing: const Icon(
              Icons.chevron_right,
              color: Colors.grey,
            ),
            onTap: () {
              settingTimeCloseInfoSheet();
            },
          ),

          /// 其他设置
          ListTile(
            leading: const Icon(Remix.apps_line),
            title: Text(S.current.settings_other),
            trailing: const Icon(
              Icons.chevron_right,
              color: Colors.grey,
            ),
            onTap: () {
              settingOtherInfoSheet();
            },
          ),
          /// 缓存设置
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(S.current.cache_manage),
            trailing: const Icon(
              Icons.chevron_right,
              color: Colors.grey,
            ),
            onTap: () {
              SettingsPage.showCacheManageSetDialog();
            },
          ),
        ]),
      ]),
    );
  }

  /// 设置里的外观设置
  static void settingMineInfoSheet() async {
    var controller = SettingsService.instance;
    await Utils.showRightOrBottomSheet(
      title: S.current.settings_app,
      child: ListView(
          // shrinkWrap: true,
          children: [
            SettingsCardV2(children: [
              /// 外观主题设置
              ListTile(
                leading: const Icon(Icons.dark_mode_rounded),
                title: Text(S.current.change_theme_mode),
                subtitle: Text(S.current.change_theme_mode_subtitle),
                onTap: () {
                  SettingsPage.showThemeModeSelectorDialog();
                },
              ),

              /// 外观主题颜色
              ListTile(
                leading: const Icon(Icons.color_lens),
                title: Text(S.current.change_theme_color),
                subtitle: Text(S.current.change_theme_color_subtitle),
                trailing: ColorIndicator(
                  width: 44,
                  height: 44,
                  borderRadius: 4,
                  color: HexColor(SettingsService.instance.themeColorSwitch.value),
                  onSelectFocus: false,
                ),
                onTap: () {
                  SettingsPage.colorPickerDialog();
                },
              ),

              /// 外观 语言
              ListTile(
                leading: const Icon(Icons.translate_rounded),
                title: Text(S.current.change_language),
                subtitle: Text(S.current.change_language_subtitle),
                onTap: () => SettingsPage.showLanguageSelecterDialog(),
              ),

              ///动态取色
              Obx(() => SettingsSwitch(
                    leading: const Icon(Icons.self_improvement),
                    title: Text(S.current.enable_dynamic_color),
                    subtitle: Text(S.current.enable_dynamic_color_subtitle),
                    value: controller.enableDynamicTheme.value,
                    onChanged: (bool value) => controller.enableDynamicTheme.value = value,
                  )),

              ///
            ])
          ]),
    );
  }

  /// 主页设置
  static void settingHomeInfoSheet() async {
    var controller = SettingsService.instance;
    await Utils.showRightOrBottomSheet(
      title: S.current.settings_home,
      child: ListView(
          // shrinkWrap: true,
          children: [
            SettingsCardV2(children: [
              /// 紧凑模式
              Obx(() => SettingsSwitch(
                    leading: const Icon(Icons.screenshot),
                    title: Text(S.current.enable_dense_favorites_mode),
                    subtitle: Text(S.current.enable_dense_favorites_mode_subtitle),
                    value: controller.enableDenseFavorites.value,
                    onChanged: (bool value) => controller.enableDenseFavorites.value = value,
                  )),

              ///
              ListTile(
                leading: const Icon(Icons.favorite),
                title: Text(S.current.prefer_platform),
                subtitle: Text(S.current.prefer_platform_subtitle),
                onTap: () {
                  SettingsPage.showPreferPlatformSelectorDialog();
                },
                trailing: const Icon(
                  Icons.chevron_right,
                  color: Colors.grey,
                ),
              ),

              ///
              ListTile(
                leading: const Icon(Icons.show_chart_outlined),
                title: Text(S.current.platform_settings),
                subtitle: Text(S.current.platform_settings_info),
                onTap: () => Get.toNamed(RoutePath.kSettingsHotAreas),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: Colors.grey,
                ),
              ),

              /////
            ])
          ]),
    );
  }

  /// 弹幕设置
  static void settingDanmakuInfoSheet() async {
    await Utils.showRightOrBottomSheet(
      title: S.current.settings_danmaku_title,
      child: ListView(
          // shrinkWrap: true,
          children: [
            SettingsCardV2(children: [
              /// 弹幕设置
              ListTile(
                  leading: const Icon(Remix.text_wrap),
                  title: Text(S.current.settings_danmaku_title),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Colors.grey,
                  ),
                  onTap: () async {
                    SettingsPage.showDanmuSetDialog();
                  }),

              /// 弹幕过滤
              ListTile(
                  leading: const Icon(Remix.filter_off_line),
                  title: Text(S.current.danmu_filter),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Colors.grey,
                  ),
                  onTap: () async {
                    Get.toNamed(RoutePath.kSettingsDanmuShield);
                  })
            ])
          ]),
    );
  }

  /// 关注设置
  static void settingFavoriteInfoSheet() async {
    var controller = SettingsService.instance;
    await Utils.showRightOrBottomSheet(
      title: S.current.settings_favorite,
      child: ListView(
          // shrinkWrap: true,
          children: [
            SettingsCardV2(children: [
              // 定时关闭设置
              ListTile(
                leading: const Icon(Remix.timer_2_line),
                title: Text(S.current.auto_refresh_time),
                subtitle: Text(S.current.auto_refresh_time_subtitle),
                trailing: Obx(() => Text(TimeUtil.minuteValueToStr(controller.autoRefreshTime.value))),
                onTap: () {
                  SettingsPage.showAutoRefreshTimeSetDialog();
                },
              ),

              /////
            ])
          ]),
    );
  }

  /// 定时关闭设置
  static void settingTimeCloseInfoSheet() async {
    var controller = SettingsService.instance;
    await Utils.showRightOrBottomSheet(
      title: S.current.settings_time_close,
      child: ListView(
          // shrinkWrap: true,
          children: [
            SettingsCardV2(children: [

              // 定时关闭设置
              if (Platform.isAndroid)
                ListTile(
                  leading: const Icon(Remix.timer_2_line),
                  title: Text(S.current.auto_shutdown_time),
                  subtitle: Text(S.current.auto_shutdown_time_subtitle),
                  trailing: Obx(() => Text(TimeUtil.minuteValueToStr(controller.autoShutDownTime.value))),
                  onTap: () {
                    SettingsPage.showAutoShutDownTimeSetDialog();
                  },
                ),

              /////
            ])
          ]),
    );
  }

  /// 直播设置
  static void settingPlayerInfoSheet() async {
    var controller = SettingsService.instance;
    var context = Get.context!;
    await Utils.showRightOrBottomSheet(
      title: S.current.settings_player,
      child: ListView(
          // shrinkWrap: true,
          children: [
            SettingsCardV2(children: [
              Obx(() => SettingsSwitch(
                    leading: Icon(Icons.play_circle_outline_sharp),
                    title: Text(S.current.enable_background_play),
                    subtitle: Text(S.current.enable_background_play_subtitle),
                    value: controller.enableBackgroundPlay.value,
                    onChanged: (bool value) => controller.enableBackgroundPlay.value = value,
                  )),
              if (Platform.isAndroid)
                Obx(() => SettingsSwitch(
                      leading: Icon(Icons.currency_exchange_sharp),
                      title: Text(S.current.auto_rotate_screen),
                      subtitle: Text(S.current.auto_rotate_screen_info),
                      value: controller.enableRotateScreenWithSystem.value,
                      onChanged: (bool value) => controller.enableRotateScreenWithSystem.value = value,
                    )),
              Obx(() => SettingsSwitch(
                    leading: Icon(Icons.fiber_smart_record),
                    title: Text(S.current.enable_screen_keep_on),
                    subtitle: Text(S.current.enable_screen_keep_on_subtitle),
                    value: controller.enableScreenKeepOn.value,
                    onChanged: (bool value) => controller.enableScreenKeepOn.value = value,
                  )),
              Obx(() => SettingsSwitch(
                    leading: Icon(Icons.fullscreen),
                    title: Text(S.current.enable_fullscreen_default),
                    subtitle: Text(S.current.enable_fullscreen_default_subtitle),
                    value: controller.enableFullScreenDefault.value,
                    onChanged: (bool value) => controller.enableFullScreenDefault.value = value,
                  )),
              ListTile(
                leading: Icon(Icons.video_camera_back_outlined),
                title: Text(S.current.prefer_resolution),
                subtitle: Text(S.current.prefer_resolution_subtitle),
                onTap: () {
                  SettingsPage.showPreferResolutionSelectorDialog();
                },
                trailing: const Icon(
                  Icons.chevron_right,
                  color: Colors.grey,
                ),
              ),

              if (Platform.isAndroid)
                Obx(() => SettingsSwitch(
                      leading: const Icon(Icons.exit_to_app),
                      title: Text(S.current.double_click_to_exit),
                      value: controller.doubleExit.value,
                      onChanged: (bool value) => controller.doubleExit.value = value,
                    )),
              // if (Platform.isAndroid)
              ListTile(
                leading: const Icon(Icons.play_circle_outline_outlined),
                title: Text(S.current.change_player),
                subtitle: Text(S.current.change_player_subtitle),
                trailing: Obx(() => Text(controller.playerlist[controller.videoPlayerIndex.value])),
                onTap: () {
                  SettingsPage.showVideoSetDialog();
                },
              ),
              if (Platform.isAndroid)
                Obx(() => SettingsSwitch(
                      leading: const Icon(Icons.qr_code),
                      title: Text(S.current.enable_codec),
                      value: controller.enableCodec.value,
                      onChanged: (bool value) => controller.enableCodec.value = value,
                    )),

              /////
            ])
          ]),
    );
  }

  /// 其他设置
  static void settingOtherInfoSheet() async {
    var controller = SettingsService.instance;
    await Utils.showRightOrBottomSheet(
      title: S.current.settings_other,
      child: ListView(
          // shrinkWrap: true,
          children: [
            SettingsCardV2(children: [
              // 备份与恢复
              ListTile(
                leading: const Icon(Icons.backup_rounded),
                title: Text(S.current.backup_recover),
                subtitle: Text(S.current.backup_recover_subtitle),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: Colors.grey,
                ),
                onTap: () => Navigator.push(
                  Get.context!,
                  MaterialPageRoute(builder: (context) => const BackupPage()),
                ),
              ),

              Obx(() => SettingsSwitch(
                    leading: const Icon(Icons.update),
                    title: Text(S.current.enable_auto_check_update),
                    subtitle: Text(S.current.enable_auto_check_update_subtitle),
                    value: controller.enableAutoCheckUpdate.value,
                    onChanged: (bool value) => controller.enableAutoCheckUpdate.value = value,
                  )),

              /////
            ])
          ]),
    );
  }
}
