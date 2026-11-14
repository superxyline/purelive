import 'dart:convert';

import 'package:pure_live/common/index.dart';

/// 局域网互推的接收侧确认流程（手机/平板/电视共用）：
/// 收到推送 → 弹确认对话框（TV 上遥控 OK/返回同样可用）→ 确认后并集合并。
class LanSyncConfirm {
  /// 注册接收确认回调（在 LanDiscoveryService.start 之后调用一次）。
  static void register() {
    LanDiscoveryService.to.confirmHandler = (request) async {
      // 原生 showDialog + Navigator.of(context).pop(result)：Get.back(result:)
      // 在嵌套 Get.dialog 场景下 result 传递失效（Get 4.7.3 的坑，两端确认/取消
      // 都会被当成取消）；barrierDismissible=false 不允许点框外关闭。
      final result = await showDialog<bool>(
        context: Get.context!,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: Text(i18n('lan_receive_title')),
          content: Text(
            i18n('lan_receive_body', args: {
              'ip': request.senderIp,
              'count': '${request.favoriteCount}',
            }),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(i18n('cancel')),
            ),
            FilledButton(
              autofocus: true,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(i18n('confirm')),
            ),
          ],
        ),
      );
      if (result != true) return false;
      try {
        final data = jsonDecode(request.payload);
        if (data is! Map) return false;
        final (ok, added) = LanDiscoveryService.mergeTransferPayload(Map<String, dynamic>.from(data));
        ToastUtil.show(ok ? i18n('lan_receive_done', args: {'count': '$added'}) : i18n('sync_failed'));
        return ok;
      } catch (_) {
        return false;
      }
    };
  }
}
