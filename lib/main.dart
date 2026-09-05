import 'dart:async';

import 'package:flutter/services.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/routes/app_navigation.dart';
import 'package:pure_live/common/consts/app_consts.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:pure_live/common/global/initialized.dart';
import 'package:pure_live/player/utils/player_consts.dart';
import 'package:pure_live/player/models/player_engine.dart';
import 'package:pure_live/common/global/platform_utils.dart';
import 'package:pure_live/routes/route_observer_controller.dart';
import 'package:pure_live/modules/esports/esports_controller.dart';
import 'package:pure_live/modules/esports/esports_reminder_service.dart';

/// 安卓返回键修复：MIUI 手势返回有时以按键事件（KEYCODE_BACK→goBack）形式
/// 送入 Flutter 键盘管线，而引擎对该键的"重派发→onBackPressed"链路存在丢事件
/// 的情况（表现为滑动返回偶尔完全无反应）。这里在 Dart 层直接接管 goBack 键，
/// 走与系统返回一致的 RouterDelegate.popRoute（尊重 PopScope/弹窗/全屏拦截）。
/// 处理后返回 true 告知引擎"已处理"，避免引擎重派发造成双击返回。
bool _backKeyHandler(KeyEvent event) {
  if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.goBack) {
    return false;
  }
  final context = Get.context;
  if (context == null) return false;
  final routerState = Router.maybeOf(context);
  final delegate = routerState?.routerDelegate;
  if (delegate is GetDelegate) {
    unawaited(delegate.popRoute());
    return true;
  }
  return false;
}

void main(List<String> args) async {
  await AppInitializer().initialize(args);

  HardwareKeyboard.instance.addHandler(_backKeyHandler);

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('zh')],
      path: 'assets/translations',
      fallbackLocale: const Locale('zh'),
      assetLoader: const RootBundleAssetLoader(),
      child: MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    unawaited(initGlobalPlayer());
    // 观看统计先于快捷方式注册：快捷方式的数据源是观看时长 Top3 主播
    Get.put(WatchStatsService());
    Get.put(RecentRoomsService());
    // 按直播间维度的礼物卡片屏蔽
    Get.put(RoomGiftBlockService());
    // 冷启动后台预取赛事数据：延后几秒避开首页首屏的网络竞争，
    // 用户点击赛事标签时大概率已就绪，直接命中缓存秒开。
    Future.delayed(const Duration(seconds: 5), () {
      unawaited(EsportsController.prefetch());
      // 初始化赛事提醒服务
      unawaited(EsportsReminderService().init());
    });
  }

  Future<void> initGlobalPlayer() async {
    final String savedKey = SettingsService.to.player.videoPlayerKey.v;
    final String validKey = PlayerConsts.engines.containsKey(savedKey) ? savedKey : PlayerConsts.defaultKey;
    final PlayerEngine targetEngine = PlayerConsts.engines[validKey]!;
    final PlayerEngine defaultEngine;

    if (PlatformUtils.isDesktop) {
      defaultEngine = PlayerEngine.mediaKit;
    } else {
      defaultEngine = targetEngine;
    }
    await GlobalPlayerService.instance.initialize(defaultEngine: defaultEngine);
  }

  @override
  void dispose() {
    unawaited(GlobalPlayerService.instance.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        return Obx(() {
          final themeColor = HexColor(SettingsService.to.theme.themeColorSwitch.v);
          final showSplashPage = SettingsService.to.app.showSplashPage.v;
          final currentFactor = SettingsService.to.font.textScaleFactor.v;

          ThemeData lightTheme;
          ThemeData darkTheme;

          if (SettingsService.to.theme.enableDynamicTheme.v && lightDynamic != null && darkDynamic != null) {
            lightTheme = MyTheme(colorScheme: lightDynamic.harmonized()).lightThemeData;
            darkTheme = MyTheme(colorScheme: darkDynamic.harmonized()).darkThemeData;
          } else {
            lightTheme = MyTheme(primaryColor: themeColor).lightThemeData;
            darkTheme = MyTheme(primaryColor: themeColor).darkThemeData;
          }

          return GetMaterialApp(
            title: i18n('app_name'),
            debugShowCheckedModeBanner: false,
            themeMode: AppConsts.themeModes[SettingsService.to.theme.themeModeName.v]!,
            theme: lightTheme.copyWith(
              appBarTheme: const AppBarTheme(surfaceTintColor: Colors.transparent),
              pageTransitionsTheme: const PageTransitionsTheme(
                builders: <TargetPlatform, PageTransitionsBuilder>{
                  TargetPlatform.android: ZoomPageTransitionsBuilder(),
                  TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
                },
              ),
            ),
            darkTheme: darkTheme.copyWith(
              appBarTheme: const AppBarTheme(surfaceTintColor: Colors.transparent),
              pageTransitionsTheme: const PageTransitionsTheme(
                builders: <TargetPlatform, PageTransitionsBuilder>{
                  TargetPlatform.android: ZoomPageTransitionsBuilder(),
                  TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
                },
              ),
            ),
            locale: context.locale,
            navigatorObservers: [FlutterSmartDialog.observer, BackButtonObserver()],
            builder: FlutterSmartDialog.init(
              builder: (context, child) {
                final Widget resultWidget = child ?? const SizedBox.shrink();
                return MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(currentFactor)),
                  child: resultWidget,
                );
              },
            ),
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            initialRoute: showSplashPage ? RoutePath.kSplash : RoutePath.kInitial,
            defaultTransition: Transition.native,
            routingCallback: (routing) {
              if (routing != null) {
                RouteObserverController.to.updateRoute(routing.current);
              }
            },
            getPages: AppPages.routes,
          );
        });
      },
    );
  }
}
