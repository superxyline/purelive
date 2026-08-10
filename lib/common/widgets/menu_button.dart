import 'package:remixicon/remixicon.dart';
import 'package:pure_live/common/index.dart';

class MenuButton extends StatelessWidget {
  const MenuButton({super.key});

  final menuRoutes = const [RoutePath.kSettings, RoutePath.kAbout, RoutePath.kHistory];

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton(
      tooltip: i18n('menu'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      offset: const Offset(12, 0),
      position: PopupMenuPosition.under,
      icon: const Icon(Icons.menu_rounded),
      onSelected: (int index) {
        Get.toNamed(menuRoutes[index]);
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 0,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: MenuListTile(leading: const Icon(Remix.settings_5_line), text: i18n("settings_title")),
        ),
        PopupMenuItem(
          value: 1,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: MenuListTile(leading: const Icon(Remix.information_line), text: i18n("about")),
        ),
        PopupMenuItem(
          value: 2,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: MenuListTile(leading: const Icon(Remix.history_line), text: i18n("history")),
        ),
      ],
    );
  }
}

class MenuListTile extends StatelessWidget {
  final Widget? leading;
  final String text;
  final Widget? trailing;

  const MenuListTile({super.key, required this.leading, required this.text, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (leading != null) ...[
          SizedBox(width: 22, height: 22, child: Center(child: leading!)),
          const SizedBox(width: 10),
        ],
        SizedBox(
          height: 22,
          child: Center(
            child: Text(
              text,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(fontSize: 13, height: 1.0),
            ),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 10), trailing!],
      ],
    );
  }
}
