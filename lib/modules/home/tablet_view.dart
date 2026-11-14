import 'package:remixicon/remixicon.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/consts/app_consts.dart';
import 'dart:ui' as ui;

import 'package:pure_live/modules/home/widgets/liquid_glass_bar.dart';

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

                // 液态玻璃导航（参照 wzgrx/PureLive）：竖向玻璃胶囊只含菜单项，
                // 水滴在菜单项间弹簧移动；设置/搜索是动作入口，不纳入玻璃栏，
                // 单独以磨砂小圆钮悬浮在左上角。
                final List<int> realIndices = [];
                final List<HomeMenu> menus = [];
                for (String id in activeMenuIds) {
                  final menu = HomeMenu.fromId(id);
                  if (menu != null) {
                    realIndices.add(menu.index);
                    menus.add(menu);
                  }
                }

                final slot = GlassBarMetrics.railSlotHeight;
                final barHeight = menus.length * slot;
                int glassSelected = realIndices.indexOf(index);
                if (glassSelected == -1) glassSelected = 0;
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
                      child: Column(
                        children: [
                          _GlassEntryButton(
                            icon: Icons.menu_rounded,
                            tooltip: i18n('settings_title'),
                            onTap: () => Get.toNamed(RoutePath.kSettings),
                          ),
                          const SizedBox(height: 8),
                          _GlassEntryButton(
                            icon: CustomIcons.search,
                            tooltip: i18n('search_live'),
                            onTap: () => Get.toNamed(RoutePath.kSearch),
                          ),
                          const Spacer(),
                          SizedBox(
                            height: barHeight,
                            child: LiquidGlassBar(
                              axis: LiquidGlassBarAxis.vertical,
                              height: slot,
                              items: [
                                for (int i = 0; i < menus.length; i++)
                                  LiquidGlassBarItem(
                                    icon: _iconFor(menus[i]),
                                    selectedIcon: _iconFor(menus[i], selected: true),
                                    label: _labelFor(menus[i]),
                                  ),
                              ],
                              selectedIndex: glassSelected,
                              onSelected: (int menuIndex) {
                                if (menuIndex >= 0 && menuIndex < realIndices.length) {
                                  onDestinationSelected(realIndices[menuIndex]);
                                }
                              },
                            ),
                          ),
                        ],
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

/// 左上角的磨砂玻璃小圆钮（设置/搜索入口）：BackdropFilter 磨砂 + rim 描边，
/// 与液态玻璃栏的磨砂降级同质感。
class _GlassEntryButton extends StatelessWidget {
  const _GlassEntryButton({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final tint = theme.colorScheme.surfaceContainerHighest;
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14, tileMode: TileMode.mirror),
        child: Material(
          color: tint.withValues(alpha: dark ? 0.30 : 0.34),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
            side: BorderSide(
              color: (dark ? Colors.white : Colors.black).withValues(alpha: dark ? 0.16 : 0.10),
              width: 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(26),
            onTap: onTap,
            child: SizedBox(
              width: 52,
              height: 52,
              child: Icon(icon, size: 24, color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      ),
    );
  }
}
