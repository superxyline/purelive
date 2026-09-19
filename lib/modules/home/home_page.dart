import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:pure_live/common/index.dart';
import 'package:move_to_desktop/move_to_desktop.dart';
import 'package:pure_live/common/consts/app_consts.dart';
import 'package:pure_live/common/global/platform/mobile_manager.dart';
import 'package:pure_live/modules/areas/areas_page.dart';
import 'package:pure_live/modules/home/mobile_view.dart';
import 'package:pure_live/modules/home/tablet_view.dart';
import 'package:pure_live/modules/popular/popular_page.dart';
import 'package:pure_live/modules/favorite/favorite_page.dart';
import 'package:pure_live/modules/esports/esports_page.dart';
import 'package:pure_live/modules/esports/esports_controller.dart';
import 'package:pure_live/modules/esports/favorite_match_controller.dart';
import 'package:pure_live/common/global/platform_utils.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with AutomaticKeepAliveClientMixin {
  Timer? _debounceTimer;
  final FavoriteController favoriteController = Get.find<FavoriteController>();

  int _selectedIndex = 0;

  /// 双击页签检测：记录上一次点击的页签索引与时间。
  int? _lastTappedMenuIndex;
  DateTime? _lastTappedAt;

  final Map<HomeMenu, Widget> _pageMap = const {
    HomeMenu.favorites: FavoritePage(),
    HomeMenu.popular: PopularPage(),
    HomeMenu.areas: AreasPage(),
    HomeMenu.esports: EsportsPage(),
  };

  @override
  void initState() {
    super.initState();
    // 注册赛事页控制器：EsportsPage 为 GetView，未注册会因 Get.find 失败导致灰屏。
    Get.lazyPut(() => EsportsController());
    Get.lazyPut(() => FavoriteMatchController());
    _syncInitialIndex();

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) async {
      if (PlatformUtils.isAndroid) {
        // 统一系统栏样式：状态栏/导航栏透明 + 图标亮度随主题。不要把导航栏设成
        // navigationBarTheme 背景色，否则平板横屏下底部手势条区域会出现黑条。
        MobileManager.setStatusBarStyle(isDarkTheme: Get.isDarkMode);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    });

    favoriteController.tabBottomIndex.addListener(() {
      if (mounted) {
        setState(() => _selectedIndex = favoriteController.tabBottomIndex.value);
      }
    });

    ever(SettingsService.to.app.savedMenuIds, (v) {
      if (mounted) {
        final List<String> value = List<String>.from(v as List);
        if (value.isNotEmpty) {
          final currentMenuId = HomeMenu.values[_selectedIndex].id;
          if (!value.contains(currentMenuId)) {
            final firstMenu = HomeMenu.fromId(value.first);
            if (firstMenu != null) {
              onDestinationSelected(firstMenu.index);
            }
          }
        }
      }
    });
  }

  void _syncInitialIndex() {
    final activeIds = SettingsService.to.app.savedMenuIds.v;
    if (activeIds.isNotEmpty) {
      final firstMenu = HomeMenu.fromId(activeIds.first);
      if (firstMenu != null) {
        _selectedIndex = firstMenu.index;
        favoriteController.tabBottomIndex.value = firstMenu.index;
      }
    }
  }

  void debounceListen(Function? func, [int delay = 1000]) {
    if (_debounceTimer != null) {
      _debounceTimer?.cancel();
    }
    _debounceTimer = Timer(Duration(milliseconds: delay), () {
      func?.call();
      _debounceTimer = null;
    });
  }

  /// 底部页签点击：单击切换页面，双击（[kDoubleTapTimeout] 内再次点击同一页签）
  /// 刷新该页面。检测放在这里而不是页签图标上，手机端 NavigationBar 与平板端
  /// NavigationRail 因此共用同一套逻辑。
  void onDestinationSelected(int index) {
    final now = DateTime.now();
    final isDoubleTap =
        _lastTappedMenuIndex == index &&
        _lastTappedAt != null &&
        now.difference(_lastTappedAt!) <= kDoubleTapTimeout;
    _lastTappedMenuIndex = index;
    _lastTappedAt = now;

    if (mounted) {
      setState(() => _selectedIndex = index);
    }
    favoriteController.tabBottomIndex.value = index;

    if (isDoubleTap) {
      _refreshMenuAt(index);
    }
  }

  /// 双击页签时刷新对应页面：关注重新拉取房间详情，热门强制重载当前平台。
  void _refreshMenuAt(int index) {
    if (index < 0 || index >= HomeMenu.values.length) return;
    switch (HomeMenu.values[index]) {
      case HomeMenu.favorites:
        favoriteController.refreshData();
        break;
      case HomeMenu.popular:
        if (Get.isRegistered<PopularController>()) {
          Get.find<PopularController>().refreshCurrent();
        }
        break;
      case HomeMenu.areas:
      case HomeMenu.esports:
        break;
    }
  }

  void onBackButtonPressed(bool didPop, _) async {
    if (!didPop) {
      MoveToDesktop().moveToDesktop();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: onBackButtonPressed,
      child: LayoutBuilder(
        builder: (context, constraint) {
          final bool isTablet = constraint.maxWidth > 680;

          return Obx(() {
            final activeMenuIds = List<String>.from(SettingsService.to.app.savedMenuIds.v);
            if (activeMenuIds.isEmpty) return const Scaffold();

            int adjustedIndex = _selectedIndex;
            if (adjustedIndex >= HomeMenu.values.length) {
              final fallbackMenu = HomeMenu.fromId(activeMenuIds.first);
              if (fallbackMenu != null) {
                adjustedIndex = fallbackMenu.index;
              }
            }

            final currentMenu = HomeMenu.values[adjustedIndex];
            final currentWidget = _pageMap[currentMenu] ?? const SizedBox.shrink();

            return !isTablet
                ? HomeMobileView(
                    body: currentWidget,
                    index: adjustedIndex,
                    onDestinationSelected: onDestinationSelected,
                  )
                : HomeTabletView(
                    body: currentWidget,
                    index: adjustedIndex,
                    activeMenuIds: activeMenuIds,
                    onDestinationSelected: onDestinationSelected,
                  );
          });
        },
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}
