import 'dart:io';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/fullscreen.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller_panel.dart';

class MediaPlayerFullscreen extends StatefulWidget {
  const MediaPlayerFullscreen({super.key, required this.controller});
  final VideoController controller;

  @override
  State<MediaPlayerFullscreen> createState() => _MediaPlayerFullscreenState();
}

class _MediaPlayerFullscreenState extends State<MediaPlayerFullscreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isAndroid || Platform.isIOS) {
      landScape();
      doEnterFullScreen();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  VideoController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    return widget.controller.globalPlayer.getVideoWidget(VideoControllerPanel(controller: widget.controller));
  }
}
