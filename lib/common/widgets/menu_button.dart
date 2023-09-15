import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/auth/auth_controller.dart';

import '../../routes/app_pages.dart';

class MenuButton extends GetView<AuthController> {
  const MenuButton({Key? key}) : super(key: key);

  final menuRoutes = const [
    AppPages.settings,
    AppPages.about,
    AppPages.contact,
    AppPages.history,
    AppPages.signIn
  ];

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton(
      tooltip: 'menu',
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      offset: const Offset(12, 0),
      position: PopupMenuPosition.under,
      icon: const Icon(Icons.menu_rounded),
      onSelected: (int index) {
        if (index == 4) {
          if (controller.isLogin) {
            Get.toNamed(AppPages.mine);
          } else {
            Get.toNamed(AppPages.signIn);
          }
        } else {
          Get.toNamed(menuRoutes[index]);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 4,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: MenuListTile(
            leading: const Icon(Icons.account_circle),
            text: controller.isLogin ? S.of(context).supabase_mine : S.of(context).supabase_sign_in,
          ),
        ),
        PopupMenuItem(
          value: 0,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: MenuListTile(
            leading: const Icon(Icons.settings_rounded),
            text: S.of(context).settings_title,
          ),
        ),
        PopupMenuItem(
          value: 1,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: MenuListTile(
            leading: const Icon(Icons.info_rounded),
            text: S.of(context).about,
          ),
        ),
        PopupMenuItem(
          value: 2,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: MenuListTile(
            leading: const Icon(Icons.contact_support),
            text: S.of(context).contact,
          ),
        ),
        PopupMenuItem(
          value: 3,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: MenuListTile(
            leading: const Icon(Icons.history),
            text: S.of(context).history,
          ),
        ),
      ],
    );
  }
}

class MenuListTile extends StatelessWidget {
  final Widget? leading;
  final String text;
  final Widget? trailing;

  const MenuListTile({
    Key? key,
    required this.leading,
    required this.text,
    this.trailing,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (leading != null) ...[
          leading!,
          const SizedBox(width: 12),
        ],
        Text(
          text,
          style: Theme.of(context).textTheme.labelMedium,
        ),
        if (trailing != null) ...[
          const SizedBox(width: 24),
          trailing!,
        ],
      ],
    );
  }
}
