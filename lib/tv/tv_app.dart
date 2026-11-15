import 'package:easy_localization/easy_localization.dart';
import 'package:pure_live/modules/backup/lan_sync_confirm.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/player/utils/player_consts.dart' as player_consts;
import 'package:pure_live/player/global_player_service.dart';

import 'core/tv_theme.dart';
import 'pages/tv_home_page.dart';
import 'pages/tv_probe_page.dart';
import 'pages/tv_room_loading_page.dart';

/// TV 模式根 App：强制横屏 + 深色固定 + TvScaffold 壳。
/// 手机路径完全不走这里；桌面/iOS 检测恒 false。
class TvApp extends StatefulWidget {
  const TvApp({super.key});

  /// M1 焦点探针开关：验收通过后改 false 直接进主界面
  static const bool kProbe = false;

  @override
  State<TvApp> createState() => _TvAppState();
}

class _TvAppState extends State<TvApp> {
  @override
  void initState() {
    super.initState();
    debugPrint('[TvApp] initState');
    // TV 恒横屏
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // 播放服务链：LivePlayController 依赖 GlobalPlayerService（手机端在
    // _MyAppState 里初始化，TV 需自行补齐），其余为播放页用到的常规服务
    Get.put(WatchStatsService());
    Get.put(RoomGiftBlockService());
    Get.put(VideoMaskService());
    // 局域网设备发现与互推同步（TV 端也可被手机/平板推送关注）。
    // 只注册不 start：仅在互推页打开时启动发现/接收，退出即 stop，
    // 待机零 socket、零后台流量。
    Get.put(LanDiscoveryService());
    LanSyncConfirm.register();
    unawaited(_initPlayer());
  }

  Future<void> _initPlayer() async {
    try {
      final savedKey = SettingsService.to.player.videoPlayerKey.v;
      final validKey = player_consts.PlayerConsts.engines.containsKey(savedKey)
          ? savedKey
          : player_consts.PlayerConsts.defaultKey;
      await GlobalPlayerService.instance.initialize(defaultEngine: player_consts.PlayerConsts.engines[validKey]!);
      debugPrint('[TvApp] player initialized ($validKey)');
    } catch (e) {
      debugPrint('[TvApp] player init failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 路由策略：不能直接挂 AppPages.routes —— 其 kInitial("/home") 会被
    // GetMaterialApp 当作 "/" 解析目标，导致手机版首页整个跑进 TV 树
    // （实测：home 参数被路由表架空）。这里只注册 TV 根 + M1 过渡页；
    // 手机版播放页依赖 MyApp 才初始化的播放服务链，TV 下不推（M2 做 TvPlayPage）。
    return GetMaterialApp(
      title: '纯粹直播 TV',
      debugShowCheckedModeBanner: false,
      theme: TvTheme.themeData(),
      supportedLocales: context.supportedLocales,
      localizationsDelegates: context.localizationDelegates,
      locale: context.locale,
      navigatorObservers: [FlutterSmartDialog.observer],
      // 关键：没有这个 builder，SmartDialog 的 Toast/Dialog 在 TV 树下
      // context 未初始化，ToastUtil.show 会抛 LateInitializationError
      builder: FlutterSmartDialog.init(),
      getPages: [
        GetPage(
          name: '/',
          page: () => TvTheme.scaffoldBackground(
            child: TvApp.kProbe ? TvRootGate() : const TvHomePage(),
          ),
          participatesInRootNavigator: true,
        ),
        GetPage(name: '/tv_room', page: () => const TvRoomLoadingPage()),
      ],
    );
  }
}

/// 探针→主界面 的门页（自管状态，切换确定生效）
class TvRootGate extends StatefulWidget {
  @override
  State<TvRootGate> createState() => _TvRootGateState();
}

class _TvRootGateState extends State<TvRootGate> {
  bool _entered = false;

  @override
  Widget build(BuildContext context) {
    return _entered ? const TvHomePage() : TvProbePage(onEnter: _enter);
  }

  void _enter() {
    if (mounted) setState(() => _entered = true);
  }
}
