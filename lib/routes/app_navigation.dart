import 'dart:io';
import 'dart:async';
import 'dart:developer';

import 'package:flutter/services.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/plugins/utils.dart';
import 'package:pure_live/modules/live_play/controllers/live_play_controller.dart';
import 'package:pure_live/player/utils/fullscreen.dart';

/// APP页面跳转封装
/// * 需要参数的页面都应使用此类
/// * 如不需要参数，可以使用Get.toNamed
class AppNavigator {
  static bool _openingLiveRoom = false;

  /// 跳转至分类详情
  static void toCategoryDetail({required Site site, required LiveArea category}) {
    Get.toNamed(RoutePath.kAreaRooms, arguments: [site, category]);
  }

  /// 跳转至直播间
  static Future<void> toLiveRoomDetail({required LiveRoom liveRoom}) async {
    if (_openingLiveRoom) return;
    final platform = (liveRoom.platform?.trim() ?? '').toLowerCase();
    final roomId = liveRoom.roomId?.trim() ?? '';
    if (platform.isEmpty || roomId.isEmpty || !Sites.isSupported(platform)) {
      ToastUtil.show(i18n('get_room_info_failed_retry'));
      return;
    }
    final normalizedRoom = liveRoom.platform == platform && liveRoom.roomId == roomId
        ? liveRoom
        : liveRoom.copyWith(platform: platform, roomId: roomId);
    _openingLiveRoom = true;
    try {
      // 从搜索等带输入框的页面进入时，先清除输入焦点并收起键盘：
      // 活跃的输入连接会让系统把返回手势优先用于收起键盘（事件到不了应用），
      // 同时残留在下层页面的编辑焦点会干扰返回处理，表现为“返回失效”。
      FocusManager.instance.primaryFocus?.unfocus();
      unawaited(SystemChannels.textInput.invokeMethod('TextInput.hide'));
      await Get.toNamed(RoutePath.kLivePlay, arguments: normalizedRoom, parameters: {"site": platform});
    } finally {
      _openingLiveRoom = false;
    }
  }

  static Future<void> offAndToRoomDetail({required LiveRoom liveRoom}) async {
    final platform = (liveRoom.platform?.trim() ?? '').toLowerCase();
    final roomId = liveRoom.roomId?.trim() ?? '';
    if (platform.isEmpty || roomId.isEmpty || !Sites.isSupported(platform)) {
      ToastUtil.show(i18n('get_room_info_failed_retry'));
      return;
    }
    final normalizedRoom = liveRoom.platform == platform && liveRoom.roomId == roomId
        ? liveRoom
        : liveRoom.copyWith(platform: platform, roomId: roomId);
    await Get.offAndToNamed(RoutePath.kLivePlay, arguments: normalizedRoom, parameters: {"site": platform});
  }

  /// 跳转至哔哩哔哩登录
  static Future toBiliBiliLogin() async {
    var contents = [i18n("sms_login"), i18n("qrcode_login")];
    if (Platform.isAndroid || Platform.isIOS) {
      var result = await Utils.showOptionDialog(contents, '', title: i18n("select_login_method"));
      if (result == i18n("sms_login")) {
        await Get.toNamed(RoutePath.kBiliBiliWebLogin);
      } else if (result == i18n("qrcode_login")) {
        await Get.toNamed(RoutePath.kBiliBiliQRLogin);
      }
    } else {
      await Get.toNamed(RoutePath.kBiliBiliQRLogin);
    }
  }
}

class BackButtonObserver extends RouteObserver<PageRoute<dynamic>> {
  @override
  void didPop(Route route, Route? previousRoute) {
    super.didPop(route, previousRoute);
    if (route.settings.name == RoutePath.kLivePlay) {
      try {
        final livePlayController = Get.find<LivePlayController>();
        final state = livePlayController.state.value;

        // 更新房间状态
        livePlayController.updateRoom(success: false);

        final manager = GlobalPlayerService.instance.playerManager;
        if (SettingsService.to.player.floatPlay.v) {
          livePlayController.prepareAppFloating();
          Future.delayed(Duration(milliseconds: 200), () {
            manager.showAppFloating();
          });
        } else {
          // 清理播放器
          final videoController = state.player.videoController;
          if (videoController != null) {
            videoController.clearListener();
          }

          // 检查是否音频模式
          if (state.player.isCurrentRoomAudioOnly) {
            manager.hardDispose();
          } else {
            manager.close();
          }
        }
      } catch (e) {
        log("BackButtonObserver Error: ${e.toString()}");
      }
      // 任何路径离开直播间都兜底恢复手机竖屏与系统栏，
      // 防止被绕过全屏处理直接弹出时横屏状态泄漏到首页。
      unawaited(restoreMobileScreenAfterLeaveRoom());
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (route.settings.name == RoutePath.kLivePlay) {
      final manager = GlobalPlayerService.instance.playerManager;
      manager.closeAppFloating();
    }
  }
}
