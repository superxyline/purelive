import 'dart:io';
import 'dart:async';
import 'package:get/get.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:app_links/app_links.dart';
import 'package:pure_live/common/index.dart';
import 'package:easy_refresh/easy_refresh.dart';
import 'package:pure_live/plugins/supabase.dart';
import 'package:pure_live/routes/app_pages.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/plugins/window_util.dart';
import 'package:win32_registry/win32_registry.dart';
import 'package:window_manager/window_manager.dart';
import 'common/services/bilibili_account_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pure_live/modules/auth/auth_controller.dart';
import 'package:pure_live/modules/areas/areas_controller.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:pure_live/modules/popular/popular_controller.dart';
import 'package:pure_live/modules/favorite/favorite_controller.dart';
import 'package:windows_single_instance/windows_single_instance.dart';

const kWindowsScheme = 'purelive://signin';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  JsEngine.init();
  PrefUtil.prefs = await SharedPreferences.getInstance();
  MediaKit.ensureInitialized();
  if (Platform.isWindows) {
    register(kWindowsScheme);
    await WindowsSingleInstance.ensureSingleInstance(args, "pure_live_instance_checker");
    await windowManager.ensureInitialized();
    await WindowUtil.init(width: 1280, height: 720);
  }
  getApplicationCacheDirectory().then((value) => print(value));
  // 先初始化supdatabase
  await SupaBaseManager.getInstance().initial();
  // 初始化服务
  initService();
  initRefresh();
  runApp(const MyApp());
}

void initService() {
  Get.put(AuthController());
  Get.put(SettingsService());
  Get.put(FavoriteController());
  Get.put(PopularController());
  Get.put(AreasController());
  Get.put(BiliBiliAccountService());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WindowListener {
  final settings = Get.find<SettingsService>();
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _init();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _linkSubscription?.cancel();
    super.dispose();
  }

  Future<void> initDeepLinks() async {
    _appLinks = AppLinks();

    // Check initial link if app was in cold state (terminated)
    final appLink = await _appLinks.getInitialAppLink();
    if (appLink != null) {
      openAppLink(appLink);
    }

    // Handle link when app is in warm state (front or background)
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      openAppLink(uri);
    });
  }

  void openAppLink(Uri uri) {
    final AuthController authController = Get.find<AuthController>();
    if (Platform.isWindows) {
      authController.shouldGoReset = true;
      Timer(const Duration(seconds: 2), () {
        authController.shouldGoReset = false;
        Get.offAndToNamed(RoutePath.kUpdatePassword);
      });
    }
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
    if (Platform.isWindows) {
      // Add this line to override the default close handler
      initDeepLinks();
      await WindowUtil.setTitle();
      await WindowUtil.setWindowsPort();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.select): const ActivateIntent(),
      },
      child: DynamicColorBuilder(
        builder: (lightDynamic, darkDynamic) {
          return Obx(() {
            var themeColor = HexColor(settings.themeColorSwitch.value);
            var lightTheme = MyTheme(primaryColor: themeColor).lightThemeData;
            var darkTheme = MyTheme(primaryColor: themeColor).darkThemeData;
            if (settings.enableDynamicTheme.value) {
              lightTheme = MyTheme(colorScheme: lightDynamic).lightThemeData;
              darkTheme = MyTheme(colorScheme: darkDynamic).darkThemeData;
            }
            return GetMaterialApp(
              title: '纯粹直播',
              themeMode: SettingsService.themeModes[settings.themeModeName.value]!,
              theme: lightTheme,
              darkTheme: darkTheme,
              locale: SettingsService.languages[settings.languageName.value]!,
              navigatorObservers: [FlutterSmartDialog.observer],
              builder: FlutterSmartDialog.init(),
              supportedLocales: S.delegate.supportedLocales,
              localizationsDelegates: const [
                S.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              initialRoute: RoutePath.kInitial,
              defaultTransition: Transition.native,
              getPages: AppPages.routes,
            );
          });
        },
      ),
    );
  }
}

initRefresh() {
  EasyRefresh.defaultHeaderBuilder = () => const ClassicHeader(
        armedText: '松开加载',
        dragText: '上拉刷新',
        readyText: '加载中...',
        processingText: '正在刷新...',
        noMoreText: '没有更多数据了',
        failedText: '加载失败',
        messageText: '上次加载时间 %T',
        processedText: '加载成功',
      );
  EasyRefresh.defaultFooterBuilder = () => const ClassicFooter(
        armedText: '松开加载',
        dragText: '下拉刷新',
        readyText: '加载中...',
        processingText: '正在刷新...',
        noMoreText: '没有更多数据了',
        failedText: '加载失败',
        messageText: '上次加载时间 %T',
        processedText: '加载成功',
      );
}

Future<void> register(String scheme) async {
  String appPath = Platform.resolvedExecutable;

  String protocolRegKey = 'Software\\Classes\\$scheme';
  RegistryValue protocolRegValue = const RegistryValue(
    'URL Protocol',
    RegistryValueType.string,
    '',
  );
  String protocolCmdRegKey = 'shell\\open\\command';
  RegistryValue protocolCmdRegValue = RegistryValue(
    '',
    RegistryValueType.string,
    '"$appPath" "%1"',
  );

  final regKey = Registry.currentUser.createKey(protocolRegKey);
  regKey.createValue(protocolRegValue);
  regKey.createKey(protocolCmdRegKey).createValue(protocolCmdRegValue);
}
