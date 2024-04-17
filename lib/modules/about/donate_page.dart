import 'package:pure_live/common/index.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

class DonatePage extends StatelessWidget {
  const DonatePage({super.key});

  final widgets = const [WechatItem()];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraint) {
      final width = constraint.maxWidth;
      final crossAxisCount = width > 640 ? 2 : 1;
      return Scaffold(
        appBar: AppBar(title: const Text("帮助与支持")),
        body: MasonryGridView.count(
          physics: const BouncingScrollPhysics(),
          crossAxisCount: crossAxisCount,
          itemCount: 1,
          itemBuilder: (BuildContext context, int index) => widgets[index],
        ),
      );
    });
  }
}

class WechatItem extends StatelessWidget {
  const WechatItem({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.all(32.0),
          child: Text(
            "感谢您的使用！",
          ),
        ),
        Padding(
          padding: EdgeInsets.all(32.0),
          child: Text(
            "如果您觉得有更好的建议或者意见，欢迎您联系我们。",
          ),
        ),
        Padding(
          padding: EdgeInsets.all(32.0),
          child: Text(
            "QQ群：920447827",
          ),
        ),
      ],
    );
  }
}
