import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:pure_live/common/index.dart';

class DonatePage extends StatelessWidget {
  const DonatePage({Key? key}) : super(key: key);

  final widgets = const [AlipayItem(), WechatItem()];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraint) {
      final width = constraint.maxWidth;
      final crossAxisCount = width > 640 ? 2 : 1;
      return Scaffold(
        appBar: AppBar(title: Text(S.of(context).support_donate)),
        body: MasonryGridView.count(
          physics: const BouncingScrollPhysics(),
          crossAxisCount: crossAxisCount,
          itemCount: 2,
          itemBuilder: (BuildContext context, int index) => widgets[index],
        ),
      );
    });
  }
}

class AlipayItem extends StatelessWidget {
  const AlipayItem({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SectionTitle(title: 'Alipay'),
        Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.all(12),
          child: Image.asset(
            'assets/images/alipay.jpg',
            fit: BoxFit.contain,
          ),
        ),
      ],
    );
  }
}

class WechatItem extends StatelessWidget {
  const WechatItem({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SectionTitle(title: 'Wechat'),
        Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.all(12),
          child: Container(),
        ),
      ],
    );
  }
}
