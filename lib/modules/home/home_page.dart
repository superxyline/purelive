import 'dart:io';
import 'dart:async';
import 'package:get/get.dart';
import 'package:flutter/services.dart';
import 'package:pure_live/common/index.dart';
import 'package:move_to_desktop/move_to_desktop.dart';
import 'package:pure_live/modules/areas/areas_page.dart';
import 'package:pure_live/modules/home/mobile_view.dart';
import 'package:pure_live/modules/home/tablet_view.dart';
import 'package:pure_live/modules/popular/popular_page.dart';
import 'package:pure_live/modules/favorite/favorite_page.dart';
import 'package:pure_live/modules/about/widgets/version_dialog.dart';
import 'package:pure_live/modules/search/search_page.dart';
import 'package:pure_live/modules/search/search_controller.dart' as search_controller;

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with AutomaticKeepAliveClientMixin, WindowListener {
  Timer? _debounceTimer;
  final FavoriteController favoriteController = Get.find<FavoriteController>();
  @override
  void initState() {
    super.initState();
    // check update overlay ui
    WidgetsBinding.instance.addPostFrameCallback(
      (timeStamp) async {
        // Android statusbar and navigationbar
        if (Platform.isAndroid) {
          SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Theme.of(context).navigationBarTheme.backgroundColor,
          ));
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        } else {
          windowManager.addListener(this);
        }
      },
    );
    addToOverlay();
    favoriteController.tabBottomIndex.addListener(() {
      setState(() => _selectedIndex = favoriteController.tabBottomIndex.value);
      setPageController(_selectedIndex);
    });
  }

  void setPageController(int selectIndex){
    switch(selectIndex){
      case 0 : Get.put(FavoriteController()); break;
      case 1 : Get.put(PopularController()); break;
      case 2 : Get.put(AreasController()); break;
      case 3 : Get.put(search_controller.SearchController()); break;
      default:
        Get.put(FavoriteController()); break;
    }
  }

  @override
  void dispose() {
    if (Platform.isWindows) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowFocus() {
    setState(() {});
  }

  int _selectedIndex = 0;
  final List<Widget> bodys = const [
    FavoritePage(),
    PopularPage(),
    AreasPage(),
    SearchPage(),
  ];
  void debounceListen(Function? func, [int delay = 1000]) {
    if (_debounceTimer != null) {
      _debounceTimer?.cancel();
    }
    _debounceTimer = Timer(Duration(milliseconds: delay), () {
      func?.call();

      _debounceTimer = null;
    });
  }

  handMoveRefresh() {
    favoriteController.onRefresh();
  }

  void onDestinationSelected(int index) {
    setState(() => _selectedIndex = index);
    favoriteController.tabBottomIndex.value = index;
  }

  Future<void> addToOverlay() async {
    final overlay = Overlay.maybeOf(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => Container(
        alignment: Alignment.center,
        color: Colors.black54,
        child: NewVersionDialog(entry: entry),
      ),
    );
    await VersionUtil.checkUpdate();
    bool isHasNerVersion = Get.find<SettingsService>().enableAutoCheckUpdate.value && VersionUtil.hasNewVersion();
    if (mounted) {
      if (overlay != null && isHasNerVersion) {
        WidgetsBinding.instance.addPostFrameCallback((_) => overlay.insert(entry));
      } else {
        if (overlay != null && isHasNerVersion) {
          overlay.insert(entry);
        }
      }
    }
  }

  void onBackButtonPressed(bool canPop, data) async {
    if (canPop) {
      final moveToDesktopPlugin = MoveToDesktop();
      await moveToDesktopPlugin.moveToDesktop();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return PopScope(
      canPop: Get.currentRoute == RoutePath.kInitial,
      onPopInvokedWithResult: onBackButtonPressed,
      child: LayoutBuilder(
        builder: (context, constraint) => constraint.maxWidth <= 680
            ? HomeMobileView(
                body: bodys[_selectedIndex],
                index: _selectedIndex,
                onDestinationSelected: onDestinationSelected,
                onFavoriteDoubleTap: handMoveRefresh,
              )
            : HomeTabletView(
                body: bodys[_selectedIndex],
                index: _selectedIndex,
                onDestinationSelected: onDestinationSelected,
              ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}
