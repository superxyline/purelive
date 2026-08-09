import 'dart:io';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:pure_live/common/index.dart';
import 'package:move_to_desktop/move_to_desktop.dart';
import 'package:pure_live/common/consts/app_consts.dart';
import 'package:pure_live/modules/areas/areas_page.dart';
import 'package:pure_live/modules/home/mobile_view.dart';
import 'package:pure_live/modules/home/tablet_view.dart';
import 'package:pure_live/modules/popular/popular_page.dart';
import 'package:pure_live/modules/favorite/favorite_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with AutomaticKeepAliveClientMixin {
  Timer? _debounceTimer;
  final FavoriteController favoriteController = Get.find<FavoriteController>();
  StreamSubscription? _tabBottomSub;

  int _selectedIndex = 0;

  final Map<HomeMenu, Widget> _pageMap = const {
    HomeMenu.favorites: FavoritePage(),
    HomeMenu.popular: PopularPage(),
    HomeMenu.areas: AreasPage(),
  };

  @override
  void initState() {
    super.initState();
    _syncInitialIndex();

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) async {
      if (Platform.isAndroid) {
        SystemChrome.setSystemUIOverlayStyle(
          SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Theme.of(context).navigationBarTheme.backgroundColor,
          ),
        );
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    });

    _tabBottomSub = favoriteController.tabBottomIndex.listen((_) {
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

  @override
  void dispose() {
    _tabBottomSub?.cancel();
    super.dispose();
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

  void handMoveRefresh() {
    favoriteController.refreshData();
  }

  void onDestinationSelected(int index) {
    if (mounted) {
      setState(() => _selectedIndex = index);
    }
    favoriteController.tabBottomIndex.value = index;
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
                    onFavoriteDoubleTap: handMoveRefresh,
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
