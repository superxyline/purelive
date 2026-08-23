import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/live_play/local_interaction_controller.dart';

/// 轻量礼物面板：按当前直播间平台展示本地礼物，点击直接发送。
///
/// 供弹幕输入条左侧星星按钮与全屏输入条调用。
Future<void> showLocalGiftSheet(
  BuildContext context, {
  required LocalInteractionController controller,
  required String platform,
  required void Function(LiveMessage message, bool showAsDanmaku) onMessage,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => LocalGiftSheet(controller: controller, platform: platform, onMessage: onMessage),
  );
}

class LocalGiftSheet extends StatelessWidget {
  const LocalGiftSheet({super.key, required this.controller, required this.platform, required this.onMessage});

  final LocalInteractionController controller;
  final String platform;
  final void Function(LiveMessage message, bool showAsDanmaku) onMessage;

  @override
  Widget build(BuildContext context) {
    final gifts = LocalInteractionController.giftsForPlatform(platform);
    final pack = LocalInteractionController.packForPlatform(platform);
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 4, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    i18n('local_gift_center'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Obx(
                  () => Chip(
                    avatar: const Icon(Icons.toll_rounded, size: 18),
                    label: Text('${controller.coins.v} ${i18n(pack.currencyKey)}'),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  tooltip: i18n('cancel'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.0,
              ),
              itemCount: gifts.length,
              itemBuilder: (context, index) {
                final gift = gifts[index];
                return InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    final message = controller.sendGift(gift, platform: platform);
                    if (message == null) {
                      ToastUtil.show(i18n('local_coins_insufficient'));
                      return;
                    }
                    Navigator.pop(context);
                    onMessage(message, controller.showAsDanmaku.v);
                  },
                  child: Ink(
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(gift.emoji, style: const TextStyle(fontSize: 30)),
                        Text(i18n(gift.nameKey), maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text('${gift.price}', style: Theme.of(context).textTheme.labelSmall),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
