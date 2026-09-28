import 'package:flutter/material.dart';
import 'package:remixicon/remixicon.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/consts/app_consts.dart';
import 'package:pure_live/modules/home/widgets/liquid_glass_nav_button.dart';

class HomeTabletView extends StatelessWidget {
  final Widget body;
  final int index;
  final List<String> activeMenuIds;
  final void Function(int) onDestinationSelected;

  const HomeTabletView({
    super.key,
    required this.body,
    required this.index,
    required this.activeMenuIds,
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
    final MediaQueryData mediaQuery = MediaQuery.of(context);
    // 沉浸小白条（参照 PiliPlus 主页做法）：只消费顶部与左右安全区，底部
    // inset 不消费，让页面内容（直播间卡片列表）延伸到透明手势条下方滑动。
    // 之前整页 SafeArea 把底部裁掉了，导致手势条区域只能露出一条白色背景。
    final EdgeInsets safePadding = EdgeInsets.only(
      top: mediaQuery.padding.top,
      left: mediaQuery.padding.left,
      right: mediaQuery.padding.right,
    );

    return Scaffold(
      body: MediaQuery.removePadding(
        context: context,
        removeTop: true,
        removeLeft: true,
        removeRight: true,
        child: Padding(
          padding: safePadding,
          child: Builder(
            builder: (context) {
              final List<NavigationRailDestination> destinations = [];
              final List<int> virtualToRealMap = [];

              for (String id in activeMenuIds) {
                final menu = HomeMenu.fromId(id);
                if (menu != null) {
                  virtualToRealMap.add(menu.index);

                  switch (menu) {
                    case HomeMenu.favorites:
                      destinations.add(
                        NavigationRailDestination(
                          icon: const Icon(Remix.heart_3_line),
                          selectedIcon: const Icon(Remix.heart_3_fill),
                          label: Text(i18n("favorites_title")),
                        ),
                      );
                      break;
                    case HomeMenu.popular:
                      destinations.add(
                        NavigationRailDestination(
                          icon: const Icon(Remix.fire_line),
                          selectedIcon: const Icon(Remix.fire_fill),
                          label: Text(i18n("popular_title")),
                        ),
                      );
                      break;
                    case HomeMenu.areas:
                      destinations.add(
                        NavigationRailDestination(
                          icon: const Icon(Remix.apps_2_line),
                          selectedIcon: const Icon(Remix.apps_2_fill),
                          label: Text(i18n("areas_title")),
                        ),
                      );
                      break;
                    case HomeMenu.esports:
                      destinations.add(
                        NavigationRailDestination(
                          icon: const Icon(Remix.trophy_line),
                          selectedIcon: const Icon(Remix.trophy_fill),
                          label: Text(i18n("esports_title")),
                        ),
                      );
                      break;
                  }
                }
              }

              int activeSelectedIndex = virtualToRealMap.indexOf(index);
              if (activeSelectedIndex == -1) {
                activeSelectedIndex = 0;
              }

              final bool isRailVisible = destinations.length > 1;

              return Obx(() {
                final bool useGlass = SettingsService.to.app.useLiquidGlass.value;

                if (!useGlass) {
                  // 现有 NavigationRail（当前样式）
                  return Row(
                    children: [
                      if (isRailVisible) ...[
                        Padding(
                          // 手势条区域不响应点击，rail 图标垫高避免落入其中点不到
                          padding: EdgeInsets.only(bottom: mediaQuery.padding.bottom),
                          child: NavigationRail(
                            groupAlignment: 0.9,
                            labelType: NavigationRailLabelType.all,
                            leading: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Padding(padding: EdgeInsets.all(12), child: MenuButton()),
                                Padding(
                                  padding: const EdgeInsets.only(top: 0, bottom: 12, left: 12, right: 12),
                                  child: IconButton(
                                    onPressed: () => Get.toNamed(RoutePath.kToolbox),
                                    icon: const Icon(Remix.link),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(top: 0, bottom: 12, left: 12, right: 12),
                                  child: IconButton(
                                    onPressed: () => Get.toNamed(RoutePath.kSearch),
                                    icon: const Icon(CustomIcons.search),
                                  ),
                                ),
                              ],
                            ),
                            destinations: destinations,
                            selectedIndex: activeSelectedIndex,
                            onDestinationSelected: (int virtualIndex) {
                              if (virtualIndex < virtualToRealMap.length) {
                                onDestinationSelected(virtualToRealMap[virtualIndex]);
                              }
                            },
                          ),
                        ),
                        const VerticalDivider(width: 1),
                      ],
                      Expanded(child: body),
                    ],
                  );
                }

                // 液态玻璃导航（替换现有左侧栏）：设置/搜索直播/链接访问 + 各菜单
                final Color accent = Theme.of(context).colorScheme.primary;
                final List<int> realIndices = [];
                final List<HomeMenu> menus = [];
                for (String id in activeMenuIds) {
                  final menu = HomeMenu.fromId(id);
                  if (menu != null) {
                    realIndices.add(menu.index);
                    menus.add(menu);
                  }
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 108,
                      padding: EdgeInsets.only(
                        top: 12,
                        bottom: mediaQuery.padding.bottom + 12,
                        left: 10,
                        right: 4,
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            LiquidGlassNavButton(
                              icon: Icons.menu_rounded,
                              label: i18n('settings_title'),
                              accent: accent,
                              onTap: () => Get.toNamed(RoutePath.kSettings),
                            ),
                            LiquidGlassNavButton(
                              icon: CustomIcons.search,
                              label: i18n('search_live'),
                              accent: accent,
                              onTap: () => Get.toNamed(RoutePath.kSearch),
                            ),
                            LiquidGlassNavButton(
                              icon: Icons.link,
                              label: i18n('link_access'),
                              accent: accent,
                              onTap: () => Get.toNamed(RoutePath.kToolbox),
                            ),
                            const SizedBox(height: 10),
                            for (int i = 0; i < menus.length; i++)
                              LiquidGlassNavButton(
                                icon: _iconFor(menus[i], selected: realIndices[i] == index),
                                label: _labelFor(menus[i]),
                                selected: realIndices[i] == index,
                                accent: accent,
                                onTap: () => onDestinationSelected(realIndices[i]),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: body),
                  ],
                );
              });
            },
          ),
        ),
      ),
    );
  }
}
