import 'package:pure_live/common/index.dart';

/// 主界面左上角按钮：点击直接进入设置页。
class MenuButton extends StatelessWidget {
  const MenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: i18n('settings_title'),
      icon: const Icon(Icons.menu_rounded),
      onPressed: () => Get.toNamed(RoutePath.kSettings),
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