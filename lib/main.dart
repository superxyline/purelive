import 'dart:io';

import 'package:dart_vlc/dart_vlc.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/areas/areas_controller.dart';
import 'package:pure_live/modules/auth/auth_controller.dart';
import 'package:pure_live/modules/favorite/favorite_controller.dart';
import 'package:pure_live/modules/popular/popular_controller.dart';
import 'package:pure_live/plugins/supbase.dart';
import 'package:pure_live/routes/app_pages.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  JsEngine.init();
  PrefUtil.prefs = await SharedPreferences.getInstance();
  if (Platform.isWindows) {
    DartVLC.initialize();
    await windowManager.ensureInitialized();
  }
  await SupBaseManager.getInstance().initial();
  initService();

  runApp(MyApp());
}

void initService() {
  Get.put(AuthController());
  Get.put(SettingsService());
  Get.put(FavoriteController());
  Get.put(PopularController());
  Get.put(AreasController());
}

class MyApp extends StatelessWidget {
  MyApp({Key? key}) : super(key: key);

  final settings = Get.find<SettingsService>();

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
