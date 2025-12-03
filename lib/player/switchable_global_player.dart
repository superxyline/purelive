import 'dart:async';
import 'fijk_adapter.dart';
import 'package:get/get.dart';
import 'media_kit_adapter.dart';
import 'package:rxdart/rxdart.dart';
import 'package:flutter/material.dart';
import 'unified_player_interface.dart';
import 'package:pure_live/common/services/settings_service.dart';

// switchable_global_player.dart

enum PlayerEngine { mediaKit, fijk }

class SwitchableGlobalPlayer {
  static final SwitchableGlobalPlayer _instance = SwitchableGlobalPlayer._internal();
  factory SwitchableGlobalPlayer() => _instance;
  SwitchableGlobalPlayer._internal();

  UnifiedPlayer? _currentPlayer;
  PlayerEngine _currentEngine = PlayerEngine.mediaKit;
  final SettingsService settings = Get.find<SettingsService>();

  ValueKey<String> videoKey = ValueKey('video_0');

  StreamSubscription<bool>? _orientationSubscription;
  StreamSubscription<bool>? _isPlayingSubscription;
  StreamSubscription<String?>? _errorSubscription;
  StreamSubscription<double?>? _volumeSubscription;

  final isVerticalVideo = false.obs;

  final isPlaying = false.obs;

  final hasError = false.obs;

  final currentVolume = 0.5.obs;

  Stream<bool> get onLoading => _currentPlayer?.onLoading ?? Stream.value(false);

  Stream<bool> get onPlaying => _currentPlayer?.onPlaying ?? Stream.value(false);

  Stream<String?> get onError => _currentPlayer?.onError ?? Stream.value(null);

  Stream<int?> get width => _currentPlayer?.width ?? Stream.value(null);

  Stream<int?> get height => _currentPlayer?.height ?? Stream.value(null);

  Stream<double?> get volume => _currentPlayer?.volume ?? Stream.value(null);

  void _subscribeToPlayerEvents() {
    // 先取消旧订阅
    _isPlayingSubscription?.cancel();
    _errorSubscription?.cancel();
    _volumeSubscription?.cancel();
    _orientationSubscription?.cancel();
    final orientationStream = CombineLatestStream.combine2<int?, int?, bool>(width, height, (w, h) {
      if (w == null || h == null) return false;
      return h > w; // 竖屏：高度 > 宽度
    });

    // 订阅并更新 isVerticalVideo
    _orientationSubscription = orientationStream.listen((isVertical) {
      isVerticalVideo.value = isVertical;
    });
    // 订阅新 player
    _isPlayingSubscription = onPlaying.listen((playing) {
      isPlaying.value = playing;
    });

    _errorSubscription = onError.listen((error) {
      hasError.value = error != null;
    });

    _volumeSubscription = volume.listen((v) {
      currentVolume.value = v!;
    });
  }

  Future<void> init(PlayerEngine engine) async {
    if (_currentPlayer != null) return; // 已初始化
    _currentPlayer = _createPlayer(engine);
    await _currentPlayer!.init();
    _currentEngine = engine;
    _subscribeToPlayerEvents();
  }

  UnifiedPlayer _createPlayer(PlayerEngine engine) {
    switch (engine) {
      case PlayerEngine.mediaKit:
        return MediaKitPlayerAdapter();
      case PlayerEngine.fijk:
        return FijkPlayerAdapter();
    }
  }

  // 动态切换播放引擎（会重建播放器）
  Future<void> switchEngine(PlayerEngine newEngine) async {
    if (newEngine == _currentEngine) return;
    _currentPlayer?.dispose();
    _currentPlayer = _createPlayer(newEngine);
    await _currentPlayer!.init();
    _currentEngine = newEngine;
    videoKey = ValueKey('video_${DateTime.now().millisecondsSinceEpoch}');
    _subscribeToPlayerEvents();
  }

  Future<void> setVolume(double volume) async {
    _currentPlayer?.setVolume(volume);
  }

  void changeVideoFit(int index) {
    settings.videoFitIndex.value = index;
    videoKey = ValueKey('video_${DateTime.now().millisecondsSinceEpoch}');
  }

  Future<void> setDataSource(String url, Map<String, String> headers) async {
    isPlaying.value = false;
    hasError.value = false;
    isVerticalVideo.value = false;
    await _currentPlayer?.setDataSource(url, headers);
  }

  // 控制方法透传
  Future<void> play() => _currentPlayer?.play() ?? Future.value();

  Future<void> pause() => _currentPlayer?.pause() ?? Future.value();

  Future<void> togglePlayPause() async {
    if (_currentPlayer!.isPlayingNow) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> stop() async {
    _currentPlayer?.stop();
  }

  // 获取当前视频 Widget（带唯一 key 避免复用问题）
  Widget getVideoWidget(Widget? child) {
    return KeyedSubtree(
      key: videoKey,
      child: Material(
        key: ValueKey(settings.videoFitIndex.value),
        child: Scaffold(
          body: Stack(
            fit: StackFit.passthrough,
            children: [
              Container(
                color: Colors.black, // 设置你想要的背景色
              ),
              _currentPlayer?.getVideoWidget(settings.videoFitIndex.value, child) ?? SizedBox(),
              child ?? SizedBox(),
            ],
          ),
          resizeToAvoidBottomInset: true,
        ),
      ),
    );
  }

  void dispose() {
    _currentPlayer?.dispose();
    _orientationSubscription?.cancel();
    _isPlayingSubscription?.cancel();
    _errorSubscription?.cancel();
    _volumeSubscription?.cancel();
  }

  PlayerEngine get currentEngine => _currentEngine;

  UnifiedPlayer? get currentPlayer => _currentPlayer;
}
