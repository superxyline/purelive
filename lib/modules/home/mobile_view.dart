import 'package:remixicon/remixicon.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/consts/app_consts.dart';
import 'package:pure_live/modules/home/widgets/liquid_glass_bar.dart';

class HomeMobileView extends StatelessWidget {
  final Widget body;
  final int index;
  final void Function(int) onDestinationSelected;

  const HomeMobileView({
    super.key,
    required this.body,
    required this.index,
    required this.onDestinationSelected,
  });

  IconData _iconFor(HomeMenu menu, {bool selected = false}) {
    switch (menu) {
      case HomeMenu.favorites:
        return selected ? Remix.heart_3_fill : Remix.heart_3_line;
      case HomeMenu.popular:
        return selected ? Remix.fire_fill : Remix.fire_line;
      case HomeMenu.areas:
        return selected ? Remix.apps_2_fill : Remix.apps_2_line;
      case HomeMenu.esports:
        return selected ? Remix.trophy_fill : Remix.trophy_line;
    }
  }

  String _labelFor(HomeMenu menu) {
    switch (menu) {
      case HomeMenu.favorites:
        return i18n("favorites_title");
      case HomeMenu.popular:
        return i18n("popular_title");
      case HomeMenu.areas:
        return i18n("areas_title");
      case HomeMenu.esports:
        return i18n("esports_title");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final List<int> realIndices = [];
      final List<HomeMenu> menus = [];
      final activeMenuIds = SettingsService.to.app.savedMenuIds.v;
      for (String id in activeMenuIds) {
        final menu = HomeMenu.fromId(id);
        if (menu != null) {
          realIndices.add(menu.index);
          menus.add(menu);
        }
      }
      if (menus.isEmpty) return const Scaffold();

      final bool useGlass = SettingsService.to.app.useLiquidGlass.value;

      if (!useGlass) {
        // 现有 NavigationBar（当前样式）
        int activeSelectedIndex = realIndices.indexOf(index);
        if (activeSelectedIndex == -1) activeSelectedIndex = 0;
        return Scaffold(
          bottomNavigationBar: NavigationBar(
            destinations: [
              for (int i = 0; i < menus.length; i++)
                NavigationDestination(
                  icon: Icon(_iconFor(menus[i])),
                  selectedIcon: Icon(_iconFor(menus[i], selected: true)),
                  label: _labelFor(menus[i]),
                ),
            ],
            selectedIndex: activeSelectedIndex,
            onDestinationSelected: (int virtualIndex) {
              if (virtualIndex < realIndices.length) {
                onDestinationSelected(realIndices[virtualIndex]);
              }
            },
          ),
          body: body,
        );
      }

      // 液态玻璃导航（参照 wzgrx/PureLive）：一条浮动玻璃胶囊，页面内容
      // 从底栏后面穿过（extendBody），选中项是弹簧水滴。
      // 必须用 viewPadding：extendBody 时 Scaffold 会把底栏高度注入
      // padding.bottom，用它算 gap 会形成栏越高→gap越大的反馈循环，
      // 把玻璃栏一路顶到屏幕中央；viewPadding 始终是系统手势条真实 inset。
      final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
      final gap = GlassBarMetrics.barGap(
        safeBottom: safeBottom,
        ios: Theme.of(context).platform == TargetPlatform.iOS,
      );
      int glassSelected = realIndices.indexOf(index);
      if (glassSelected == -1) glassSelected = 0;
      return Scaffold(
        extendBody: true,
        bottomNavigationBar: Padding(
          padding: EdgeInsets.only(left: 12, right: 12, bottom: gap),
          // heightFactor: 1 必须加：bottomNavigationBar 的约束是松的（最大为屏高），
          // 默认 Center 会撑满最大高度，把玻璃栏垂直居中到屏幕中央。
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: GlassBarMetrics.barMaxWidth),
              child: LiquidGlassBar(
                items: [
                  for (int i = 0; i < menus.length; i++)
                    LiquidGlassBarItem(
                      icon: _iconFor(menus[i]),
                      selectedIcon: _iconFor(menus[i], selected: true),
                      label: _labelFor(menus[i]),
                    ),
                ],
                selectedIndex: glassSelected,
                onSelected: (int virtualIndex) {
                  if (virtualIndex < realIndices.length) {
                    onDestinationSelected(realIndices[virtualIndex]);
                  }
                },
              ),
            ),
          ),
        ),
        body: body,
      );
    });
  }
}
