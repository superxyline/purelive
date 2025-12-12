import 'dart:io';
import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'unified_player_interface.dart';
import 'package:media_kit/media_kit.dart';
import 'package:pure_live/player/player_consts.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:pure_live/common/global/platform_utils.dart';
import 'package:pure_live/common/services/settings_service.dart';

class MediaKitPlayerAdapter implements UnifiedPlayer {
  late Player _player;
  late VideoController _controller;
  final SettingsService settings = Get.find<SettingsService>();
  bool _isPlaying = false;
  bool isInitialized = false;
  @override
  Future<void> init() async {
    _isPlaying = false;
    _player = Player();
    isInitialized = false;
    var pp = _player.platform as NativePlayer;
    if (Platform.isAndroid) {
      await pp.setProperty('force-seekable', 'yes');
    }

    _controller = settings.playerCompatMode.value
        ? VideoController(
            _player,
            configuration: VideoControllerConfiguration(vo: 'mediacodec_embed', hwdec: 'mediacodec'),
          )
        : VideoController(
            _player,
            configuration: VideoControllerConfiguration(
              enableHardwareAcceleration: settings.enableCodec.value,
              androidAttachSurfaceAfterVideoParameters: false,
            ),
          );
    _player.stream.playing.listen((playing) {
      _isPlaying = playing;
      if (!isInitialized) {
        isInitialized = true;
        if (PlatformUtils.isDesktop) {
          Future.microtask(() {
            _player.setVolume(settings.volume.value * 100);
          });
        }
      }
    });
  }

  @override
  Future<void> setDataSource(String url, Map<String, String> headers) async {
    await _player.pause();
    await _player.open(Media(url, httpHeaders: headers));
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Widget getVideoWidget(int index, Widget? controls) {
    return Video(
      key: UniqueKey(),
      controller: _controller,
      pauseUponEnteringBackgroundMode: !settings.enableBackgroundPlay.value,
      resumeUponEnteringForegroundMode: !settings.enableBackgroundPlay.value,
      fit: PlayerConsts.videofitList[index],
      controls: NoVideoControls,
    );
  }

  @override
  void dispose() {
    try {
      _player.dispose();
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  @override
  Stream<bool> get onPlaying => _player.stream.playing;

  @override
  Stream<String?> get onError => _player.stream.error.map((e) => e);
  @override
  Stream<bool> get onLoading => _player.stream.buffering;

  @override
  bool get isPlayingNow => _isPlaying;

  @override
  Stream<int?> get height => _player.stream.height;

  @override
  Stream<int?> get width => _player.stream.width;

  @override
  Future<void> setVolume(double value) async {
    await _player.setVolume(value * 100);
  }

  @override
  void stop() {
    _player.stop();
  }

  @override
  void release() {
    _player.dispose();
  }
}
