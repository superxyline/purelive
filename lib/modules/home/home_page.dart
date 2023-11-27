import 'dart:io';
import 'dart:async';
import 'package:get/get.dart';
import '../search/search_page.dart';
import 'package:flutter/services.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/areas/areas_page.dart';
import 'package:pure_live/modules/home/mobile_view.dart';
import 'package:pure_live/modules/home/tablet_view.dart';
import 'package:pure_live/modules/popular/popular_page.dart';
import 'package:pure_live/modules/favorite/favorite_page.dart';
import 'package:pure_live/modules/about/widgets/version_dialog.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with AutomaticKeepAliveClientMixin, WindowListener {
  Timer? _debounceTimer;
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

  void onDestinationSelected(int index) {
    if (index == 0) {
      debounceListen(() {
        final FavoriteController favoriteController = Get.find<FavoriteController>();
        favoriteController.onRefresh(isHandMove: true);
      }, 2000);
    }
    setState(() => _selectedIndex = index);
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

  Future<bool> _onBackPressed() async {
    if (Get.currentRoute != RoutePath.kInitial) {
      return false;
    }
    bool doubleExit = Get.find<SettingsService>().doubleExit.value;
    if (!doubleExit) {
      return false;
    }
    var result = await Get.dialog<bool>(
      AlertDialog(
        title: Text(S.of(context).exit_app),
        contentPadding: const EdgeInsets.all(2),
        actionsPadding: const EdgeInsets.all(10),
        actions: <Widget>[
          TextButton(
            onPressed: () => Get.back(result: false),
            child: Text(S.of(context).exit_yes),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            child: Text(S.of(context).exit_no),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return BackButtonListener(
      onBackButtonPressed: _onBackPressed,
      child: LayoutBuilder(
        builder: (context, constraint) => constraint.maxWidth <= 680
            ? HomeMobileView(
                body: bodys[_selectedIndex],
                index: _selectedIndex,
                onDestinationSelected: onDestinationSelected,
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
