import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/global/platform_utils.dart';

class ShareCommandHandler {
  static final ShareCommandHandler instance = ShareCommandHandler._internal();

  ShareCommandHandler._internal();

  Future<void> onShareRoomPressed(LiveRoom room) async {
    final String shareText = room.link?.isNotEmpty == true ? room.link! : (room.title ?? '');
    if (PlatformUtils.isDesktop) {
      await Clipboard.setData(ClipboardData(text: shareText));
      SnackBarUtil.success(i18n('copied_to_clipboard'));
    } else {
      await SharePlus.instance.share(ShareParams(text: shareText));
    }
  }
}
