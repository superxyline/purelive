import 'package:flutter/services.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/live_play/player_state.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller.dart';

class VideoKeyboardShortcuts extends StatefulWidget {
  final VideoController controller;
  final Widget child;

  const VideoKeyboardShortcuts({super.key, required this.controller, required this.child});

  @override
  State<VideoKeyboardShortcuts> createState() => _VideoKeyboardShortcutsState();
}

class _VideoKeyboardShortcutsState extends State<VideoKeyboardShortcuts> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleGlobalKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKey);
    super.dispose();
  }

  bool _handleGlobalKey(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _handleEscExit();
        return true;
      }
      // 部分 MIUI 场景（如从搜索页进入直播间后）系统不再处理音量键、
      // 而是把音量键分发给 App；这里接管并自己调整音量，避免音量键失效。
      if (event.logicalKey == LogicalKeyboardKey.audioVolumeUp) {
        _adjustVolume(0.05);
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.audioVolumeDown) {
        _adjustVolume(-0.05);
        return true;
      }
      // 返回键兜底：MIUI 部分场景返回键到不了 Android 层的 onBackPressed，
      // 但 KeyEvent 会到达 Dart；这里走与左上角箭头一致的 maybePop（全屏时先退全屏）。
      if (event.logicalKey == LogicalKeyboardKey.goBack) {
        final ctx = Get.context;
        if (ctx != null) {
          Navigator.of(ctx).maybePop();
        }
        return true;
      }
    }
    return false;
  }

  void _handleEscExit() async {
    if (GlobalPlayerState.to.isPipMode.value) {
      return;
    }
    widget.controller.toggleFullScreen();
  }

  Future<void> _adjustVolume(double delta) async {
    double? volume = await widget.controller.volume();
    volume = (volume ?? 1.0) + delta;
    volume = volume.clamp(0.0, 1.0);
    widget.controller.setVolume(volume);
    widget.controller.updateVolumn(volume);
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.mediaPlay): () => GlobalPlayerService.instance.playerManager.resume(),
        const SingleActivator(LogicalKeyboardKey.mediaPause): () => GlobalPlayerService.instance.playerManager.pause(),
        const SingleActivator(LogicalKeyboardKey.mediaPlayPause): () =>
            GlobalPlayerService.instance.playerManager.togglePlayPause(),
        const SingleActivator(LogicalKeyboardKey.space): () =>
            GlobalPlayerService.instance.playerManager.togglePlayPause(),
        const SingleActivator(LogicalKeyboardKey.keyR): () => widget.controller.refresh(),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _adjustVolume(0.05),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _adjustVolume(-0.05),
      },
      child: widget.child,
    );
  }
}
