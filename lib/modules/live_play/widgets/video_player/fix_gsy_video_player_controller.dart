import 'package:gsy_video_player/gsy_video_player.dart';
import 'package:pure_live/core/common/core_log.dart';

class FixGsyVideoPlayerController extends GsyVideoPlayerController {
  FixGsyVideoPlayerController({super.allowBackgroundPlayback, super.player});

  @override
  Future<void> pause() async {
    try {
      await super.pause();
    } catch (e) {
      CoreLog.w(e.toString());
    }
  }

  @override
  playOrPause() async {
    try {
      await super.playOrPause();
    } catch (e) {
      CoreLog.w(e.toString());
    }
  }

  @override
  Future<void> resume() async {
    try {
      await super.resume();
    } catch (e) {
      CoreLog.w(e.toString());
    }
  }
}
