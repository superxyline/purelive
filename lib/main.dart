import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/areas/areas_controller.dart';
import 'package:pure_live/modules/auth/auth_controller.dart';
import 'package:pure_live/modules/favorite/favorite_controller.dart';
import 'package:pure_live/modules/popular/popular_controller.dart';
import 'package:pure_live/plugins/supabase.dart';
import 'package:pure_live/plugins/window_util.dart';
import 'package:pure_live/routes/app_pages.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:media_kit/media_kit.dart'; // Provides [Player], [Media], [Playlist] etc.

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
<<<<<<< HEAD
    // Necessary initialization for package:media_kit.
=======
>>>>>>> 3248227e738197247e8ebbc391480065a5c0fab4
  MediaKit.ensureInitialized();
  JsEngine.init();
  PrefUtil.prefs = await SharedPreferences.getInstance();

  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    await WindowUtil.init(width: 1280, height: 720);
  }
  // 先初始化supdatabase
  await SupaBaseManager.getInstance().initial();
  // 初始化服务
  initService();

  runApp(const MyApp());
}

void initService() {
  Get.put(AuthController());
  Get.put(SettingsService());
  Get.put(FavoriteController());
  Get.put(PopularController());
  Get.put(AreasController());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WindowListener {
  final settings = Get.find<SettingsService>();
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _init();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowFocus() {
    setState(() {});
    super.onWindowFocus();
  }

  @override
  void onWindowEvent(String eventName) {
    WindowUtil.setPosition();
  }

  void _init() async {
<<<<<<< HEAD
    // Add this line to override the default close handler
    if (Platform.isWindows) {
=======
    if (Platform.isWindows) {
      // Add this line to override the default close handler
>>>>>>> 3248227e738197247e8ebbc391480065a5c0fab4
      await WindowUtil.setTitle();
      await WindowUtil.setWindowsPort();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        return Obx(() {
          var themeColor =
              SettingsService.themeColors[settings.themeColorName]!;
          // 主题颜色设定/Monet取色
          var lightTheme = MyTheme(primaryColor: themeColor).lightThemeData;
          var darkTheme = MyTheme(primaryColor: themeColor).darkThemeData;
          if (settings.enableDynamicTheme.value) {
            lightTheme = MyTheme(colorScheme: lightDynamic).lightThemeData;
            darkTheme = MyTheme(colorScheme: darkDynamic).darkThemeData;
          }

          return GetMaterialApp(
            title: 'PureLive',
            themeMode:
                SettingsService.themeModes[settings.themeModeName.value]!,
            theme: lightTheme,
            darkTheme: darkTheme,
            locale: SettingsService.languages[settings.languageName.value]!,
            supportedLocales: S.delegate.supportedLocales,
            localizationsDelegates: const [
              S.delegate,
              RefreshLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            initialRoute: AppPages.initial,
            getPages: AppPages.routes,
          );
        });
      },
    );
  }
}
