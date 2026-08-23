import 'package:flutter/services.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/live_play/controllers/live_play_controller.dart';

class DanmakuMessageActions {
  DanmakuMessageActions._();

  static Future<void> show(BuildContext context, LiveMessage message) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              title: Text('${message.userName}: ${message.message}'),
              subtitle: message.userLevel.isEmpty ? null : Text('Lv.${message.userLevel}'),
            ),
            ListTile(
              leading: const Icon(Icons.copy_all_rounded),
              title: Text(i18n('copy')),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await Clipboard.setData(ClipboardData(text: '${message.userName}: ${message.message}'));
                ToastUtil.show(i18n('copied_to_clipboard'));
              },
            ),
            ListTile(
              leading: const Icon(Icons.plus_one_rounded),
              title: Text(i18n('danmaku_plus_one')),
              subtitle: Text(message.message, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await sendPlusOne(message);
              },
            ),
            if (!message.isLocal && message.userName.trim().isNotEmpty)
              ListTile(
                leading: const Icon(Icons.person_off_rounded),
                title: Text(i18n('block_danmaku_user')),
                subtitle: Text(message.userName, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () {
                  SettingsService.to.fav.addBlockedDanmakuUser(message.userName);
                  if (Get.isRegistered<LivePlayController>()) {
                    Get.find<LivePlayController>().removeDanmakuWhere(
                      (item) => item.userName.trim().toLowerCase() == message.userName.trim().toLowerCase(),
                    );
                  }
                  Navigator.of(sheetContext).pop();
                  ToastUtil.show(i18n('danmaku_user_blocked'));
                },
              ),
            ListTile(
              leading: const Icon(Icons.filter_alt_rounded),
              title: Text(i18n('block_danmaku_keyword')),
              subtitle: Text(message.message, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () {
                Navigator.of(sheetContext).pop();
                showKeywordDialog(context, message.message);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 加一：把该条弹幕内容直接发出去。
  ///
  /// 已登录 B站（且当前为 B站直播间）时真实发送到 B站服务器；
  /// 否则走本地互动回显（需要开启本地互动）。两者都不可用时给出提示。
  static Future<void> sendPlusOne(LiveMessage message) async {
    final text = message.message.trim();
    if (text.isEmpty) return;
    if (!Get.isRegistered<LivePlayController>()) return;
    final controller = Get.find<LivePlayController>();
    final canSendReal =
        controller.site == Sites.bilibiliSite &&
        SettingsService.to.cookieManager.bilibiliCookie.v.trim().isNotEmpty;
    if (canSendReal) {
      await controller.sendLiveDanmaku(text);
      return;
    }
    final local = controller.localInteractionController;
    if (!local.enabled.v) {
      ToastUtil.show(i18n('danmaku_plus_one_unavailable'));
      return;
    }
    controller.emitLocalMessage(
      local.createChat(text, platform: controller.site),
      showAsDanmaku: local.showAsDanmaku.v,
      delay: LivePlayController.localChatDeliveryDelay,
    );
    ToastUtil.show(i18n('local_message_queued'));
  }

  static Future<void> showKeywordDialog(BuildContext context, String message) async {
    final textController = TextEditingController(text: message);
    final keyword = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(i18n('block_danmaku_keyword')),
        content: TextField(
          controller: textController,
          autofocus: true,
          maxLength: 40,
          decoration: InputDecoration(hintText: i18n('please_enter_keyword')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(i18n('cancel'))),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(textController.text.trim()),
            child: Text(i18n('confirm')),
          ),
        ],
      ),
    );
    textController.dispose();
    if (keyword == null || keyword.isEmpty) return;
    SettingsService.to.fav.addShieldList(keyword);
    if (Get.isRegistered<LivePlayController>()) {
      Get.find<LivePlayController>().removeDanmakuWhere(
        (item) => item.message.toLowerCase().contains(keyword.toLowerCase()),
      );
    }
    ToastUtil.show(i18n('danmaku_keyword_blocked'));
  }
}
