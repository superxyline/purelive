import 'package:flutter/material.dart';
import 'package:remixicon/remixicon.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/consts/app_consts.dart';
import 'package:pure_live/modules/home/widgets/liquid_glass_nav_button.dart';

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

      // 液态玻璃导航（替换现有底部栏）：四个玻璃按钮等宽铺满底栏
      final Color accent = Theme.of(context).colorScheme.primary;
      return Scaffold(
        bottomNavigationBar: Container(
          margin: EdgeInsets.only(
            left: 12,
            right: 12,
            bottom: MediaQuery.of(context).padding.bottom + 10,
            top: 8,
          ),
          child: Row(
            children: [
              for (int i = 0; i < menus.length; i++)
                Expanded(
                  child: LiquidGlassNavButton(
                    icon: _iconFor(menus[i], selected: realIndices[i] == index),
                    label: _labelFor(menus[i]),
                    selected: realIndices[i] == index,
                    accent: accent,
                    onTap: () => onDestinationSelected(realIndices[i]),
                  ),
                ),
            ],
          ),
        ),
        body: body,
      );
    });
  }
}
