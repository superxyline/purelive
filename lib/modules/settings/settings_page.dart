import 'dart:io';

import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/widgets/utils.dart';
import 'package:pure_live/modules/auth/utils/constants.dart';
import 'package:pure_live/modules/backup/backup_page.dart';
import 'package:pure_live/modules/settings/danmuset.dart';
import 'package:pure_live/modules/util/rx_util.dart';
import 'package:pure_live/modules/util/site_logo_widget.dart';
import 'package:pure_live/modules/util/time_util.dart';
import 'package:pure_live/plugins/cache_to_file.dart';
import 'package:pure_live/plugins/file_recover_utils.dart';

class SettingsPage extends GetView<SettingsService> {
  const SettingsPage({super.key});

  BuildContext get context => Get.context!;

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    return Scaffold(
      appBar: AppBar(
        scrolledUnderElevation: screenWidth > 640 ? 0 : null,
        title: Text(S.of(context).settings_title),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        children: <Widget>[
          SectionTitle(title: S.of(context).general),
          ListTile(
            leading: const Icon(Icons.dark_mode_rounded, size: 32),
            title: Text(S.of(context).change_theme_mode),
            subtitle: Text(S.of(context).change_theme_mode_subtitle),
            onTap: showThemeModeSelectorDialog,
          ),
          ListTile(
            leading: const Icon(Icons.color_lens, size: 32),
            title: Text(S.of(context).change_theme_color),
            subtitle: Text(S.of(context).change_theme_color_subtitle),
            trailing: ColorIndicator(
              width: 44,
              height: 44,
              borderRadius: 4,
              color: HexColor(controller.themeColorSwitch.value),
              onSelectFocus: false,
            ),
            onTap: colorPickerDialog,
          ),
          ListTile(
            leading: const Icon(Icons.translate_rounded, size: 32),
            title: Text(S.of(context).change_language),
            subtitle: Text(S.of(context).change_language_subtitle),
            onTap: showLanguageSelecterDialog,
          ),
          ListTile(
            leading: const Icon(Icons.backup_rounded, size: 32),
            title: Text(S.of(context).backup_recover),
            subtitle: Text(S.of(context).backup_recover_subtitle),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const BackupPage()),
            ),
          ),
          SectionTitle(title: S.of(context).video),
          Obx(() => SwitchListTile(
                title: Text(S.of(context).enable_background_play),
                subtitle: Text(S.of(context).enable_background_play_subtitle),
                value: controller.enableBackgroundPlay.value,
                activeColor: Theme.of(context).colorScheme.primary,
                onChanged: (bool value) => controller.enableBackgroundPlay.value = value,
              )),
          if (Platform.isAndroid)
            Obx(() => SwitchListTile(
                  title: Text(S.of(context).auto_rotate_screen),
                  subtitle: Text(S.of(context).auto_rotate_screen_info),
                  value: controller.enableRotateScreenWithSystem.value,
                  activeColor: Theme.of(context).colorScheme.primary,
                  onChanged: (bool value) => controller.enableRotateScreenWithSystem.value = value,
                )),
          Obx(() => SwitchListTile(
                title: Text(S.of(context).enable_screen_keep_on),
                subtitle: Text(S.of(context).enable_screen_keep_on_subtitle),
                value: controller.enableScreenKeepOn.value,
                activeColor: Theme.of(context).colorScheme.primary,
                onChanged: (bool value) => controller.enableScreenKeepOn.value = value,
              )),
          Obx(() => SwitchListTile(
                title: Text(S.of(context).enable_fullscreen_default),
                subtitle: Text(S.of(context).enable_fullscreen_default_subtitle),
                value: controller.enableFullScreenDefault.value,
                activeColor: Theme.of(context).colorScheme.primary,
                onChanged: (bool value) => controller.enableFullScreenDefault.value = value,
              )),
          ListTile(
            title: Text(S.of(context).prefer_resolution),
            subtitle: Text(S.of(context).prefer_resolution_subtitle),
            onTap: showPreferResolutionSelectorDialog,
          ),
          SectionTitle(title: S.of(context).custom),
          Obx(() => SwitchListTile(
                title: Text(S.of(context).enable_dynamic_color),
                subtitle: Text(S.of(context).enable_dynamic_color_subtitle),
                value: controller.enableDynamicTheme.value,
                activeColor: Theme.of(context).colorScheme.primary,
                onChanged: (bool value) => controller.enableDynamicTheme.value = value,
              )),
          Obx(() => SwitchListTile(
                title: Text(S.of(context).enable_dense_favorites_mode),
                subtitle: Text(S.of(context).enable_dense_favorites_mode_subtitle),
                value: controller.enableDenseFavorites.value,
                activeColor: Theme.of(context).colorScheme.primary,
                onChanged: (bool value) => controller.enableDenseFavorites.value = value,
              )),
          Obx(() => SwitchListTile(
                title: Text(S.of(context).enable_auto_check_update),
                subtitle: Text(S.of(context).enable_auto_check_update_subtitle),
                value: controller.enableAutoCheckUpdate.value,
                activeColor: Theme.of(context).colorScheme.primary,
                onChanged: (bool value) => controller.enableAutoCheckUpdate.value = value,
              )),
          ListTile(
            title: Text(S.of(context).prefer_platform),
            subtitle: Text(S.of(context).prefer_platform_subtitle),
            onTap: showPreferPlatformSelectorDialog,
          ),
          ListTile(
            title: Text(S.of(context).auto_refresh_time),
            subtitle: Text(S.of(context).auto_refresh_time_subtitle),
            trailing: Obx(() => Text(TimeUtil.minuteValueToStr(controller.autoRefreshTime.value))),
            onTap: showAutoRefreshTimeSetDialog,
          ),
          ListTile(
            title: Text(S.of(context).settings_danmaku_title),
            onTap: showDanmuSetDialog,
          ),
          ListTile(
            title: Text(S.of(context).danmu_filter),
            subtitle: Text(S.of(context).danmu_filter_info),
            onTap: () => Get.toNamed(RoutePath.kSettingsDanmuShield),
          ),
          ListTile(
            title: Text(S.of(context).platform_settings),
            subtitle: Text(S.of(context).platform_settings_info),
            onTap: () => Get.toNamed(RoutePath.kSettingsHotAreas),
          ),
          if (Platform.isAndroid)
            Obx(() => SwitchListTile(
                  title: Text(S.of(context).double_click_to_exit),
                  value: controller.doubleExit.value,
                  activeColor: Theme.of(context).colorScheme.primary,
                  onChanged: (bool value) => controller.doubleExit.value = value,
                )),
          // if (Platform.isAndroid)
          ListTile(
            title: Text(S.of(context).change_player),
            subtitle: Text(S.of(context).change_player_subtitle),
            trailing: Obx(() => Text(controller.playerlist[controller.videoPlayerIndex.value])),
            onTap: showVideoSetDialog,
          ),
          if (Platform.isAndroid)
            Obx(() => SwitchListTile(
                  title: Text(S.of(context).enable_codec),
                  value: controller.enableCodec.value,
                  activeColor: Theme.of(context).colorScheme.primary,
                  onChanged: (bool value) => controller.enableCodec.value = value,
                )),
          if (Platform.isAndroid)
            ListTile(
              title: Text(S.of(context).auto_shutdown_time),
              subtitle: Text(S.of(context).auto_shutdown_time_subtitle),
              trailing: Obx(() => Text(TimeUtil.minuteValueToStr(controller.autoShutDownTime.value))),
              onTap: showAutoShutDownTimeSetDialog,
            ),
          ListTile(
            title: Text(S.of(context).cache_manage),
            subtitle: Text(S.of(context).cache_manage),
            onTap: showCacheManageSetDialog,
          ),
        ],
      ),
    );
  }

  /// 主题模式
  static void showThemeModeSelectorDialog() {
    var controller = Get.find<SettingsService>();
    var context = Get.context!;
    Utils.showRightOrBottomSheet(
        title: S.of(Get.context!).change_theme_mode,
        child: ListView(
          children: SettingsService.themeModes.keys.map<Widget>((name) {
            return RadioListTile<String>(
              activeColor: Theme.of(context).colorScheme.primary,
              groupValue: controller.themeModeName.value,
              value: name,
              title: Text(SettingsService.getThemeTitle(name)),
              onChanged: (value) {
                controller.changeThemeMode(value!);
                Navigator.of(context).pop();
              },
            );
          }).toList(),
        ));
  }

  /// 主题颜色
  static Future<bool> colorPickerDialog() async {
    var controller = Get.find<SettingsService>();
    var context = Get.context!;
    return ColorPicker(
      color: HexColor(controller.themeColorSwitch.value),
      onColorChanged: (Color color) {
        controller.themeColorSwitch.value = color.hex;
        var themeColor = color;
        var lightTheme = MyTheme(primaryColor: themeColor).lightThemeData;
        var darkTheme = MyTheme(primaryColor: themeColor).darkThemeData;
        Get.changeTheme(lightTheme);
        Get.changeTheme(darkTheme);
      },
      width: 40,
      height: 40,
      borderRadius: 4,
      spacing: 5,
      runSpacing: 5,
      wheelDiameter: 155,
      heading: Text(
        S.of(Get.context!).change_theme_color,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      subheading: Text(
        S.of(Get.context!).select_transparency,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      wheelSubheading: Text(
        S.of(Get.context!).theme_color_and_transparency,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      showMaterialName: false,
      showColorName: false,
      showColorCode: true,
      copyPasteBehavior: const ColorPickerCopyPasteBehavior(
        longPressMenu: true,
      ),
      materialNameTextStyle: Theme.of(context).textTheme.bodySmall,
      colorNameTextStyle: Theme.of(context).textTheme.bodySmall,
      colorCodeTextStyle: Theme.of(context).textTheme.bodyMedium,
      colorCodePrefixStyle: Theme.of(context).textTheme.bodySmall,
      selectedPickerTypeColor: Theme.of(context).colorScheme.primary,
      customColorSwatchesAndNames: controller.colorsNameMap,
      pickersEnabled: const <ColorPickerType, bool>{
        ColorPickerType.both: false,
        ColorPickerType.primary: true,
        ColorPickerType.accent: true,
        ColorPickerType.bw: false,
        ColorPickerType.custom: true,
        ColorPickerType.wheel: true,
      },
      // customColorSwatchesAndNames: colorsNameMap,
    ).showPickerDialog(
      context,
      actionsPadding: const EdgeInsets.all(16),
      constraints: const BoxConstraints(minHeight: 480, minWidth: 375, maxWidth: 420),
    );
  }

  /// 语言选择
  static void showLanguageSelecterDialog() {
    var controller = Get.find<SettingsService>();
    var context = Get.context!;
    Utils.showRightOrBottomSheet(
      title: S.of(context).change_language,
      child: ListView(
        children: SettingsService.languages.keys.map<Widget>((name) {
          return RadioListTile<String>(
            activeColor: Theme.of(context).colorScheme.primary,
            groupValue: controller.languageName.value,
            value: name,
            title: Text(name),
            onChanged: (value) {
              controller.changeLanguage(value!);
              Navigator.of(context).pop();
            },
          );
        }).toList(),
      ),
    );
  }

  /// 视频播放器
  static void showVideoSetDialog() {
    var controller = Get.find<SettingsService>();
    var context = Get.context!;
    List<String> playerList = controller.playerlist;
    Utils.showRightOrBottomSheet(
      title: S.of(context).change_player,
      child: ListView(
        children: playerList.map<Widget>((name) {
          return RadioListTile<String>(
            activeColor: Theme.of(context).colorScheme.primary,
            groupValue: playerList[controller.videoPlayerIndex.value],
            value: name,
            title: Text(name),
            onChanged: (value) {
              controller.changePlayer(playerList.indexOf(name));
              Navigator.of(context).pop();
            },
          );
        }).toList(),
      ),
    );
  }

  /// 直播 清晰度
  static void showPreferResolutionSelectorDialog() {
    var controller = Get.find<SettingsService>();
    var context = Get.context!;
    Utils.showRightOrBottomSheet(
      title: S.of(context).prefer_resolution,
      child: ListView(
        children: SettingsService.resolutions.map<Widget>((name) {
          return RadioListTile<String>(
            activeColor: Theme.of(context).colorScheme.primary,
            groupValue: controller.preferResolution.value,
            value: name,
            title: Text(name),
            onChanged: (value) {
              controller.changePreferResolution(value!);
              Navigator.of(context).pop();
            },
          );
        }).toList(),
      ),
    );
  }

  /// 平台选择
  static void showPreferPlatformSelectorDialog() {
    var controller = Get.find<SettingsService>();
    var context = Get.context!;
    Utils.showRightOrBottomSheet(
      title: S.of(context).prefer_platform,
      child: ListView(
        children: Sites.supportSites.map<Widget>((site) {
          return RadioListTile<String>(
            activeColor: Theme.of(context).colorScheme.primary,
            groupValue: controller.preferPlatform.value,
            value: site.id,
            title: Row(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: SiteWidget.getSiteLogeImage(site.id), // 替换为你的图片路径
                ),
                Expanded(
                  child: Text(
                    Sites.getSiteName(site.id), // 替换为你的文本
                  ),
                ),
              ],
            ),
            onChanged: (value) {
              controller.changePreferPlatform(value!);
              Navigator.of(context).pop();
            },
          );
        }).toList(),
      ),
    );
  }

  /// 定时更新关注
  static void showAutoRefreshTimeSetDialog() {
    var controller = Get.find<SettingsService>();
    var context = Get.context!;
    Utils.showRightOrBottomSheet(
      title: S.of(context).auto_refresh_time,
      child: Obx(() => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Slider(
                min: 0,
                max: 120,
                label: S.of(context).auto_refresh_time,
                value: controller.autoRefreshTime.toDouble(),
                onChanged: (value) => controller.autoRefreshTime.value = value.toInt(),
              ),
              Text('${S.of(context).auto_refresh_time}:'
                  ' ${TimeUtil.minuteValueToStr(controller.autoRefreshTime.value)}'),
            ],
          )),
    );
  }

  /// 弹幕设置
  static void showDanmuSetDialog() {
    var controller = Get.find<SettingsService>();
    var context = Get.context!;
    Utils.showRightOrBottomSheet(
      title: S.of(context).settings_danmaku_title,
      child: ListView(
        // shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        children: [
          VideoFitSetting(
            controller: controller,
          ),
          DanmakuSetting(
            controller: controller,
          ),
          const SizedBox(
            height: 20,
          ),
        ],
      ),
    );
  }

  /// 定时关闭 app
  static void showAutoShutDownTimeSetDialog() {
    var controller = Get.find<SettingsService>();
    var context = Get.context!;
    Utils.showRightOrBottomSheet(
      title: S.of(context).auto_refresh_time,
      child: Obx(() => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: Text(S.of(context).auto_shutdown_time_subtitle),
                value: controller.enableAutoShutDownTime.value,
                activeColor: Theme.of(context).colorScheme.primary,
                onChanged: (bool value) => controller.enableAutoShutDownTime.value = value,
              ),
              Slider(
                min: 1,
                max: 1200,
                label: S.of(context).auto_refresh_time,
                value: controller.autoShutDownTime.toDouble(),
                onChanged: (value) {
                  controller.autoShutDownTime.value = value.toInt();
                },
              ),
              Text('${S.of(context).auto_shutdown_time}:'
                  ' ${TimeUtil.minuteValueToStr(controller.autoShutDownTime.value)}'),
            ],
          )),
    );
  }

  /// Web 端口
  static Future<String?> showWebPortDialog() async {
    var controller = Get.find<SettingsService>();
    var context = Get.context!;
    final TextEditingController textEditingController = TextEditingController();
    textEditingController.text = controller.webPort.value;
    var result = await Get.dialog(
        AlertDialog(
          title: const Text('请输入端口号'),
          content: SizedBox(
            width: 400.0,
            height: 140.0,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                children: [
                  TextField(
                    controller: textEditingController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.all(12),
                      hintText: '端口地址(1-65535)',
                    ),
                  ),
                  spacer(20.0),
                  Obx(() => SwitchListTile(
                        title: const Text('是否开启web服务'),
                        value: controller.webPortEnable.value,
                        activeColor: Theme.of(context).colorScheme.primary,
                        onChanged: (bool value) {
                          controller.webPortEnable.value = value;
                        },
                      )),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                if (controller.webPortEnable.value) {
                  SmartDialog.showToast('请先关闭web服务');
                  return;
                }
                if (textEditingController.text.isEmpty) {
                  SmartDialog.showToast('请输入端口号');
                  return;
                }
                bool validate = FileRecoverUtils.isPort(textEditingController.text);
                if (!validate) {
                  SmartDialog.showToast('请输入正确的端口号');
                  return;
                }
                if (int.parse(textEditingController.text) < 1 || int.parse(textEditingController.text) > 65535) {
                  SmartDialog.showToast('请输入正确的端口号');
                  return;
                }
                controller.webPort.value = textEditingController.text;
                SmartDialog.showToast('设置成功');
              },
              child: const Text("确定"),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(Get.context!).pop();
              },
              child: const Text("关闭弹窗"),
            ),
          ],
        ),
        barrierDismissible: false);
    return result;
  }

  /// 缓存管理
  static Future<void> showCacheManageSetDialog() async {
    // var controller = Get.find<SettingsService>();
    var cacheDirectorySize = "0 B".obs;
    CustomCache.instance.getCacheDirectorySize().then((value) => cacheDirectorySize.updateValueNotEquate(value));
    var imageCacheDirectorySize = "0 B".obs;
    CustomCache.instance.getImageCacheDirectorySize().then((value) => imageCacheDirectorySize.updateValueNotEquate(value));
    var areaCacheDirectorySize = "0 B".obs;
    CustomCache.instance.getAreaCacheDirectorySize().then((value) => areaCacheDirectorySize.updateValueNotEquate(value));

    Utils.showRightOrBottomSheet(
      title: S.of(Get.context!).cache_manage,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: Text(S.of(Get.context!).cache_manage_clear_all),
            subtitle: Obx(() => Text(cacheDirectorySize.value)),
            onTap: () async {
              var result = await Utils.showAlertDialog(S.of(Get.context!).cache_manage_clear_prompt, title: S.of(Get.context!).cache_manage_clear_all);
              if (result) {
                CustomCache.instance.deleteCacheDirectory();
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: Text(S.of(Get.context!).cache_manage_clear_image),
            subtitle: Obx(() => Text(imageCacheDirectorySize.value)),
            onTap: () async {
              var result = await Utils.showAlertDialog(S.of(Get.context!).cache_manage_clear_prompt, title: S.of(Get.context!).cache_manage_clear_image);
              if (result) {
                CustomCache.instance.deleteImageCacheDirectory();
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: Text(S.of(Get.context!).cache_manage_clear_area),
            // subtitle: Text(areaCacheDirectorySize),
            subtitle: Obx(() => Text(areaCacheDirectorySize.value)),
            onTap: () async {
              var result = await Utils.showAlertDialog(S.of(Get.context!).cache_manage_clear_prompt, title: S.of(Get.context!).cache_manage_clear_area);
              if (result) {
                CustomCache.instance.deleteAreaCacheDirectory();
              }
            },
          ),
        ],
      ),
    );
  }
}
