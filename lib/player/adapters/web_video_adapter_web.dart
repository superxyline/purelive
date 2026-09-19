import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/player/interface/unified_player_interface.dart';
import 'package:pure_live/player/models/player_error_type.dart';
import 'package:pure_live/player/models/player_exception.dart';
import 'package:pure_live/player/models/player_state.dart';
import 'package:rxdart/rxdart.dart';
import 'package:web/web.dart' as web;

/// Flutter Web 播放器：浏览器 <video> 元素 + hls.js（HLS）+ mpegts.js（flv）。
///
/// 浏览器无法自定义请求头，因此忽略 [setDataSource] 的 headers：
/// 直连失败时自动改走 NAS 后端的 /api/stream/proxy 回退一次，
/// 仍失败则向上抛 PlayerException，交给 PlayerManager 换线。
class WebVideoAdapter implements UnifiedPlayer {
  static const String _viewTypePrefix = 'purelive-web-player';

  web.HTMLVideoElement? _video;
  _PlayerHandle? _handle;
  String? _currentUrl;
  bool _usedProxyRetry = false;
  String _viewType = '';
  bool _initialized = false;
  bool _playing = false;
  double _volume = 1.0;

  final _stateSubject = BehaviorSubject<PlayerState>.seeded(PlayerState.idle);
  final _playingSubject = BehaviorSubject<bool>.seeded(false);
  final _errorSubject = PublishSubject<PlayerException>();
  final _loadingSubject = BehaviorSubject<bool>.seeded(false);
  final _completeSubject = PublishSubject<bool>();
  final _widthSubject = BehaviorSubject<int?>.seeded(null);
  final _heightSubject = BehaviorSubject<int?>.seeded(null);

  @override
  Future<void> init({bool audioOnly = false}) async {
    if (_initialized) return;
    _viewType = '${_viewTypePrefix}_${DateTime.now().microsecondsSinceEpoch}';
    final video = web.document.createElement('video') as web.HTMLVideoElement
      ..autoplay = true
      ..setAttribute('playsinline', '')
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'contain'
      ..style.backgroundColor = '#000';
    video.volume = _volume;
    _video = video;
    _bindEvents(video);
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) => video);
    _initialized = true;
    _stateSubject.add(PlayerState.initialized);
  }

  void _bindEvents(web.HTMLVideoElement video) {
    video.addEventListener('playing', ((web.Event e) {
      _playing = true;
      _playingSubject.add(true);
      _loadingSubject.add(false);
      _stateSubject.add(PlayerState.playing);
    }).toJS);
    video.addEventListener('pause', ((web.Event e) {
      _playing = false;
      _playingSubject.add(false);
      _stateSubject.add(PlayerState.paused);
    }).toJS);
    video.addEventListener('waiting', ((web.Event e) {
      _loadingSubject.add(true);
      _stateSubject.add(PlayerState.buffering);
    }).toJS);
    video.addEventListener('canplay', ((web.Event e) {
      _loadingSubject.add(false);
      _stateSubject.add(PlayerState.ready);
    }).toJS);
    video.addEventListener('loadedmetadata', ((web.Event e) {
      _widthSubject.add(video.videoWidth > 0 ? video.videoWidth : null);
      _heightSubject.add(video.videoHeight > 0 ? video.videoHeight : null);
    }).toJS);
    video.addEventListener('ended', ((web.Event e) {
      _completeSubject.add(true);
      _stateSubject.add(PlayerState.completed);
    }).toJS);
    video.addEventListener('error', ((web.Event e) {
      _handleLoadFailure();
    }).toJS);
  }

  @override
  Future<void> setDataSource(
    String url,
    List<String> playUrls,
    Map<String, String> headers, {
    LiveRoom? room,
    bool audioOnly = false,
  }) async {
    if (!_initialized) await init();
    final video = _video;
    if (video == null) return;

    await _detachCurrent();
    _currentUrl = url;
    _usedProxyRetry = false;
    _stateSubject.add(PlayerState.preparing);
    _loadingSubject.add(true);
    _handle = _binding.attach(video as JSObject, url.toJS);
  }

  /// 加载失败：直连失败先走后端流代理重试一次；代理也失败才上报错误。
  void _handleLoadFailure() {
    final url = _currentUrl;
    final video = _video;
    if (url == null || video == null) return;
    if (!_usedProxyRetry && !url.contains('/api/stream/proxy')) {
      _usedProxyRetry = true;
      final proxied =
          '${WebPlayerApi.base}/api/stream/proxy?url=${Uri.encodeComponent(url)}';
      _currentUrl = proxied;
      _detachCurrent().then((_) {
        _handle = _binding.attach(video as JSObject, proxied.toJS);
      });
      return;
    }
    _errorSubject.add(
      PlayerException(message: 'web video load failed: $url', type: PlayerErrorType.network),
    );
  }

  Future<void> _detachCurrent() async {
    try {
      _handle?.destroy();
    } catch (_) {}
    _handle = null;
    final video = _video;
    if (video != null) {
      video.removeAttribute('src');
      try {
        video.load();
      } catch (_) {}
    }
  }

  @override
  Future<void> play() async {
    try {
      await _video?.play().toDart;
    } catch (_) {}
  }

  @override
  Future<void> pause() async {
    _video?.pause();
  }

  @override
  Future<void> stop() => softStop();

  @override
  Future<void> softStop() async {
    _playing = false;
    _playingSubject.add(false);
    await _detachCurrent();
    _currentUrl = null;
    _stateSubject.add(PlayerState.stopped);
  }

  @override
  Future<void> hardDispose() async {
    await _detachCurrent();
    _video = null;
    _initialized = false;
    _playing = false;
    _stateSubject.add(PlayerState.disposed);
    await _stateSubject.close();
    await _playingSubject.close();
    await _errorSubject.close();
    await _loadingSubject.close();
    await _completeSubject.close();
    await _widthSubject.close();
    await _heightSubject.close();
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    _video?.volume = _volume;
  }

  @override
  Widget getVideoWidget() {
    return HtmlElementView(viewType: _viewType);
  }

  @override
  bool get isInitialized => _initialized;

  @override
  bool get isPlayingNow => _playing;

  @override
  bool get isReusable => true;

  @override
  int? get videoWidth {
    final w = _video?.videoWidth ?? 0;
    return w > 0 ? w : null;
  }

  @override
  int? get videoHeight {
    final h = _video?.videoHeight ?? 0;
    return h > 0 ? h : null;
  }

  @override
  int? get audioBitrateKbps => null;

  @override
  Stream<PlayerState> get onStateChanged => _stateSubject.stream;

  @override
  Stream<bool> get onPlaying => _playingSubject.stream;

  @override
  Stream<PlayerException> get onError => _errorSubject.stream;

  @override
  Stream<bool> get onLoading => _loadingSubject.stream;

  @override
  Stream<bool> get onComplete => _completeSubject.stream;

  @override
  Stream<int?> get width => _widthSubject.stream;

  @override
  Stream<int?> get height => _heightSubject.stream;
}

/// web/index.html 中的播放 helper（按 URL 类型选择 hls.js / mpegts.js / 原生 video）。
@JS('pureLivePlayer')
external _PureLivePlayerBinding get _binding;

@JS()
@staticInterop
class _PureLivePlayerBinding {
  external factory _PureLivePlayerBinding();
}

extension _PureLivePlayerBindingExt on _PureLivePlayerBinding {
  external _PlayerHandle attach(JSObject video, JSString url);
}

/// window.pureLivePlayer.attach() 返回的句柄（带 destroy）。
extension type _PlayerHandle._(JSObject _) implements JSObject {
  external void destroy();
}

/// Web 端 API 基址：同源部署为空串；独立调试时页面 URL 带 ?api=http://nas:port。
class WebPlayerApi {
  static String get base {
    final apiParam = Uri.base.queryParameters['api'];
    return (apiParam != null && apiParam.isNotEmpty) ? apiParam : '';
  }
}
