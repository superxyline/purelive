import 'package:flutter/material.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/player/models/player_exception.dart';
import 'package:pure_live/player/models/player_state.dart';
import 'package:pure_live/player/interface/unified_player_interface.dart';

/// io 平台占位实现：Web 播放器只在浏览器端可用。
/// 挂到 [PlayerEngine.web] 的工厂里，安卓/桌面端永远不会走到。
class WebVideoAdapter implements UnifiedPlayer {
  Never _unsupported() => throw UnsupportedError('WebVideoAdapter is only available on Flutter Web');

  @override
  Future<void> init({bool audioOnly = false}) => _unsupported();

  @override
  Future<void> setDataSource(String url, List<String> playUrls, Map<String, String> headers,
          {LiveRoom? room, bool audioOnly = false}) =>
      _unsupported();

  @override
  Future<void> play() => _unsupported();

  @override
  Future<void> pause() => _unsupported();

  @override
  Future<void> stop() => _unsupported();

  @override
  Future<void> softStop() => _unsupported();

  @override
  Future<void> hardDispose() => _unsupported();

  @override
  Future<void> setVolume(double volume) => _unsupported();

  @override
  Widget getVideoWidget() => _unsupported();

  @override
  bool get isInitialized => throw _unsupported();

  @override
  bool get isPlayingNow => throw _unsupported();

  @override
  bool get isReusable => true;

  @override
  int? get videoWidth => null;

  @override
  int? get videoHeight => null;

  @override
  int? get audioBitrateKbps => null;

  @override
  Stream<PlayerState> get onStateChanged => const Stream.empty();

  @override
  Stream<bool> get onPlaying => const Stream.empty();

  @override
  Stream<PlayerException> get onError => const Stream.empty();

  @override
  Stream<bool> get onLoading => const Stream.empty();

  @override
  Stream<bool> get onComplete => const Stream.empty();

  @override
  Stream<int?> get width => const Stream.empty();

  @override
  Stream<int?> get height => const Stream.empty();
}
