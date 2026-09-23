import 'dart:ui' as ui;

import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/live_play/controllers/player_state.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller_panel.dart';
import 'package:pure_live/player/core/live_audio_service.dart';
import 'package:pure_live/player/utils/orientation_policy.dart';

/// 竖屏全屏的沉浸模糊背景：房间封面静态模糊 + 轻蒙层（不启动第二路播放器、不截视频帧）。
class _AmbientBackdrop extends StatelessWidget {
  const _AmbientBackdrop({required this.controller});
  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    final room = controller.livePlayController.state.value.room.detail;
    final cover = room?.cover ?? '';
    // 封面缺失/加载失败时的暗色兜底
    const fallback = ColoredBox(color: Color(0xFF101016));
    final Widget base = cover.isEmpty
        ? fallback
        : Image.network(
            cover,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => fallback,
          );
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: base,
          ),
          Container(color: Colors.black.withValues(alpha: 0.15)),
        ],
      ),
    );
  }
}

class VideoPlayer extends StatefulWidget {
  final VideoController controller;
  const VideoPlayer({super.key, required this.controller});

  @override
  State<VideoPlayer> createState() => _VideoPlayerState();
}

class _VideoPlayerState extends State<VideoPlayer> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // 注册监听
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // 销毁监听
    super.dispose();
  }

  VideoController get controller => widget.controller;
  Widget _buildVideo() {
    return Obx(
      () {
        final video = GlobalPlayerService.instance.playerManager.getVideoWidget(
          SettingsService.to.player.videoFitIndex.v,
          fitList: SettingsService.to.player.videoFitArray,
          controls: VideoControllerPanel(controller: controller),
        );
        // 竖屏全屏 + contain（默认适配）：上下留白用封面模糊填充
        //（上游 PortraitFullscreenDisplayMode.ambient，蒙层 45%→15% 的现观感）
        if (SettingsService.to.player.portraitAmbientBackdrop.v &&
            SettingsService.to.player.videoFitIndex.v == 0 &&
            OrientationPolicy.systemIsPortrait() &&
            GlobalPlayerState.to.isFullscreen.value) {
          return Stack(
            children: [
              Positioned.fill(child: _AmbientBackdrop(controller: controller)),
              Positioned.fill(child: video),
            ],
          );
        }
        return video;
      },
    );
  }

  bool _isPausedByLifecycle = false;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final player = GlobalPlayerService.instance.playerManager;

    if (state == AppLifecycleState.paused) {
      if (!LiveAudioService.shouldContinueInBackground) {
        if (player.isPlayingNow) {
          _isPausedByLifecycle = true;
          player.pause();
        }
      } else {
        player.resume();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_isPausedByLifecycle) {
        player.resume();
        _isPausedByLifecycle = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _buildVideo();
  }
}
