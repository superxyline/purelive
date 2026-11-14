import 'package:pure_live/common/index.dart';

class GlobalPlayerState extends GetxController {
  static GlobalPlayerState get to => Get.find<GlobalPlayerState>();
  // 全屏
  var isFullscreen = false.obs;
  // window 半屏
  var isWindowFullscreen = false.obs;

  // 是否画中画
  var isPipMode = false.obs;
  bool get fullscreenUI => isFullscreen.value || isWindowFullscreen.value;

  @override
  void onInit() {
    super.onInit();
    // 刷新率策略跟随全屏状态：全屏直播间固定 ~60Hz 省电（直播流约 60 帧），
    // 高刷只作用于非全屏页面；是否启用由用户开关决定（DisplayModeService 内部合并）。
    ever(isFullscreen, (_) => _syncRefreshRate());
    ever(isWindowFullscreen, (_) => _syncRefreshRate());
  }

  void _syncRefreshRate() {
    if (!PlatformUtils.isAndroid) return;
    DisplayModeService.updateFullscreen(fullscreenUI);
  }

  void reset() {
    isFullscreen.value = false;
    isWindowFullscreen.value = false;
    isPipMode.value = false;
  }

  String? _currentRoomId;

  void setCurrentRoom(String roomId) {
    if (_currentRoomId != roomId) {
      _currentRoomId = roomId;
    }
  }
}
