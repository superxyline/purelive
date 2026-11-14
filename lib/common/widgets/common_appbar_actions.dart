import 'package:remixicon/remixicon.dart';
import 'package:pure_live/common/index.dart';

class CommonAppBarActions extends StatelessWidget {
  const CommonAppBarActions({super.key});

  @override
  Widget build(BuildContext context) {
    // 只剩搜索一个入口：直接点击跳转，不再弹菜单。
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: i18n("search_live"),
          icon: const Icon(Remix.search_line, size: 24),
          onPressed: () => Get.toNamed(RoutePath.kSearch),
        ),

        const SizedBox(width: 4),
      ],
    );
  }
}
