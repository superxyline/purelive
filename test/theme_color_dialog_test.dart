import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/settings/app_settings_controller.dart';
import 'package:pure_live/common/services/settings/font_settings_controller.dart';
import 'package:pure_live/common/services/settings/theme_settings_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/settings/pages/theme_settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 回归测试：主题颜色 tile 点击后 ColorPicker 弹窗必须打开。
// 背景：此前 colorPickerDialog 把 Get.context（GetMaterialApp 根上下文，
// 在 Localizations 作用域之上）传给 showPickerDialog，其在传入 context 上
// 取 MaterialLocalizations 抛 "No MaterialLocalizations found." 且异步错误
// 被静默吞掉，表现为点击 tile 毫无反应。修复=传页面自身 BuildContext。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory hiveDirectory;

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
    hiveDirectory = await Directory.systemTemp.createTemp('pure-live-theme-dialog-test-');
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    Hive.init(hiveDirectory.path);
    await HivePrefUtil.init();
  });

  setUp(() async {
    Get.testMode = true;
    Get.reset();
    await HivePrefUtil.clear();
    Get.put<SettingsService>(_TestSettingsService(AppSettingsController()));
    Get.put<FontSettingsController>(FontSettingsController());
    Get.put<ThemeSettingsController>(ThemeSettingsController());
  });

  tearDown(Get.reset);

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  testWidgets('主题颜色 tile 点击后 ColorPicker 弹窗打开', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('zh')],
        path: 'assets/translations',
        fallbackLocale: const Locale('zh'),
        assetLoader: const _TestAssetLoader(),
        child: Builder(
          builder: (context) => GetMaterialApp(
            locale: context.locale,
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            home: const ThemeSettingsPage(),
          ),
        ),
      ),
    );
    // 页面含 AppStatusView 加载演示（无限动画），不能 pumpAndSettle
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    final tile = find.ancestor(of: find.byType(ColorIndicator), matching: find.byType(ListTile));
    expect(tile, findsOneWidget, reason: '主题颜色 tile 应存在');

    await tester.tap(tile);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull, reason: '点击主题颜色 tile 不应抛异常');
    expect(find.byType(ColorPicker), findsOneWidget, reason: '点击后 ColorPicker 弹窗应打开');
  });
}

class _TestAssetLoader extends AssetLoader {
  const _TestAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => {
    'theme_customization': '主题定制',
    'change_theme_mode': '切换主题模式',
    'change_theme_mode_subtitle': '深色/浅色/跟随系统',
    'change_theme_color': '主题颜色',
    'change_theme_color_subtitle': '自定义 App 主题色',
    'theme_color': '主题色',
    'select_opacity': '选择不透明度',
    'theme_color_opacity': '不透明度',
    'enable_dynamic_color': '动态取色',
    'enable_dynamic_color_subtitle': '跟随壁纸颜色',
    'change_loading_style': '加载样式',
    'change_loading_style_subtitle': '自定义加载动画',
    'refresh_loading': '刷新加载',
    'grid_spacing_settings': '网格间距',
    'cross_axis_spacing': '横向间距',
    'cross_axis_spacing_subtitle': '卡片横向间距',
    'main_axis_spacing': '纵向间距',
    'main_axis_spacing_subtitle': '卡片纵向间距',
    'page_settings': '页面设置',
    'page_settings_subtitle': '自定义首页页面',
    'cancel': '取消',
    'confirm': '确定',
  };
}

class _TestSettingsService extends SettingsService {
  _TestSettingsService(this._app) : _font = FontSettingsController();

  final AppSettingsController _app;
  final FontSettingsController _font;

  @override
  AppSettingsController get app => _app;

  @override
  FontSettingsController get font => _font;

  @override
  // Test fixture intentionally skips production controller registrations.
  // ignore: must_call_super
  void onInit() {}
}
