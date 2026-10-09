import 'dart:async';

import 'package:rxdart/rxdart.dart';

import '../models/player_state.dart';
import '../models/player_exception.dart';
import '../models/player_error_type.dart';

import 'package:pure_live/common/index.dart';

import '../interface/unified_player_interface.dart';
import '../utils/shader_utils.dart';

import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:pure_live/common/global/platform_utils.dart';

class MediaKitAdapter implements UnifiedPlayer {
  late final Player _player;

  late final VideoController _controller;

  bool _initialized = false;

  bool _disposed = false;

  bool _listenerBound = false;

  String? _currentUrl;

  bool _isAudioOnly = false;

  // =========================
  // subjects
  // =========================

  final _stateSubject = BehaviorSubject<PlayerState>.seeded(PlayerState.idle);

  final _playingSubject = BehaviorSubject<bool>.seeded(false);

  final _loadingSubject = BehaviorSubject<bool>.seeded(false);

  final _errorSubject = PublishSubject<PlayerException>();

  final _completeSubject = BehaviorSubject<bool>.seeded(false);

  final _widthSubject = BehaviorSubject<int?>.seeded(null);

  final _heightSubject = BehaviorSubject<int?>.seeded(null);

  // =========================
  // subscriptions
  // =========================

  final List<StreamSubscription> _subscriptions = [];

  StreamSubscription? _playingSub;

  StreamSubscription? _bufferingSub;

  StreamSubscription? _widthSub;

  StreamSubscription? _heightSub;

  StreamSubscription? _completeSub;

  StreamSubscription? _errorSub;

  // mpv 启动阶段的可恢复错误（解码器/VO 初始化瞬态失败后内核自动回退继续播）
  // 采用延迟确认：到期仍未恢复播放才真正上报。
  Timer? _transientErrorTimer;

  PlayerException? _pendingTransientError;

  // =========================
  // init
  // =========================

  @override
  Future<void> init({bool audioOnly = false}) async {
    if (_initialized) return;
    _isAudioOnly = audioOnly;
    _disposed = false;

    _listenerBound = false;

    _currentUrl = null;

    try {
      _stateSubject.add(PlayerState.initializing);

      _player = Player();

      if (_player.platform is NativePlayer) {
        final native = _player.platform as dynamic;

        await native.setProperty('force-seekable', 'yes');

        await native.setProperty('protocol_whitelist', 'httpproxy,udp,rtp,tcp,tls,data,file,http,https,crypto');

        await native.setProperty('demuxer-lavf-probsize', '2097152');

        // 恢复 1.1.1 的探测/超时配置：过短的 analyzeduration 对斗鱼 http-flv 流
        // 解析不稳（纯音频偶发重复片段），1.1.1 使用 10s 探测 + 30s 网络超时。
        await native.setProperty('demuxer-lavf-analyzeduration', '10');

        await native.setProperty('network-timeout', '30');

        if (SettingsService.to.player.customPlayerOutput.v) {
          await native.setProperty('ao', SettingsService.to.player.audioOutputDriver.v);
        }

        if (SettingsService.to.proxy.enableProxy.v && SettingsService.to.proxy.proxyHost.v.isNotEmpty) {
          final proxyUrl = "http://${SettingsService.to.proxy.proxyHost.v}:${SettingsService.to.proxy.proxyPort.v}";

          await native.setProperty('http-proxy', proxyUrl);
        }

        if (PlatformUtils.isMacOS) {
          await native.setProperty('hwdec', 'no');
        }
      }

      // 画质增强（直播缓冲 / 音量均衡 / Anime4K 超分），仅 mpv 内核
      await _applyMpvEnhancements();

      _bindEnhancementListeners();

      // =========================
      // controller
      // =========================
      //  根据是否为纯音频，选择不同的控制器配置
      _controller = audioOnly
          ? VideoController(
              _player,
              configuration: const VideoControllerConfiguration(
                vo: 'null',
                hwdec: 'no',
                enableHardwareAcceleration: false,
              ),
            )
          : SettingsService.to.player.playerCompatMode.v
          ? VideoController(
              _player,
              configuration: const VideoControllerConfiguration(vo: 'mediacodec_embed', hwdec: 'mediacodec'),
            )
          : SettingsService.to.player.customPlayerOutput.v
          ? VideoController(
              _player,
              configuration: VideoControllerConfiguration(
                vo: SettingsService.to.player.videoOutputDriver.v,
                hwdec: PlatformUtils.isMacOS ? 'no' : SettingsService.to.player.videoHardwareDecoder.v,
                enableHardwareAcceleration: !PlatformUtils.isMacOS,
              ),
            )
          : VideoController(
              _player,
              configuration: VideoControllerConfiguration(
                enableHardwareAcceleration: PlatformUtils.isMacOS ? false : SettingsService.to.player.enableCodec.v,
                hwdec: PlatformUtils.isMacOS ? 'no' : null,
                androidAttachSurfaceAfterVideoParameters: false,
              ),
            );

      // 2. 下发底层 MPV 内核配置（必须紧跟在 Controller 创建之后）
      if (audioOnly) {
        await applyAudioOnlySettings();
      }

      await _bindListeners();

      _initialized = true;

      _stateSubject.add(PlayerState.initialized);
    } catch (e, s) {
      final exception = PlayerException(
        message: 'MediaKit init failed',
        type: PlayerErrorType.initialization,
        error: e,
        stackTrace: s,
      );

      _safeAddError(exception);

      throw exception;
    }
  }

  // =========================
  // datasource
  // =========================

  @override
  Future<void> setDataSource(
    String url,
    List<String> playUrls,
    Map<String, String> headers, {
    LiveRoom? room,
    bool audioOnly = false,
  }) async {
    if (_disposed) return;

    if (_currentUrl == url && isPlayingNow) {
      return;
    }
    _isAudioOnly = audioOnly;
    _currentUrl = url;

    // 新播放会话开始：上一次会话挂起的瞬态错误不再对本次上报
    _discardTransientError();

    try {
      _loadingSubject.add(true);

      _stateSubject.add(PlayerState.preparing);

      _completeSubject.add(false);

      _widthSubject.add(null);

      _heightSubject.add(null);

      await _player.open(Media(url, httpHeaders: headers), play: true);

      _stateSubject.add(PlayerState.ready);

      if (PlatformUtils.isMobile) {
        await setVolume(1.0);
      } else {
        final targetVolume = room?.getSavedVolume() ?? 1.0;
        await setVolume(targetVolume);
      }
    } catch (e, s) {
      final exception = PlayerException(
        message: 'Media open failed',
        type: PlayerErrorType.source,
        error: e,
        stackTrace: s,
      );

      _safeAddError(exception);

      _stateSubject.add(PlayerState.error);

      throw exception;
    } finally {
      if (!_disposed) {
        _loadingSubject.add(false);
      }
    }
  }

  // =========================
  // listeners
  // =========================

  Future<void> _bindListeners() async {
    if (_listenerBound) return;

    _listenerBound = true;

    await _cancelAllSubscriptions();

    // =========================
    // playing
    // =========================

    _playingSub = _player.stream.playing.listen(
      (playing) {
        if (_disposed) return;

        _playingSubject.add(playing);

        // 播放已实际恢复：启动阶段挂起的瞬态错误不再上报（mpv 内核已自行回退）
        if (playing) {
          _discardTransientError();
        }

        if (!_loadingSubject.value) {
          _stateSubject.add(playing ? PlayerState.playing : PlayerState.paused);
        }
      },
      onError: (e, s) {
        _emitError(e, s, PlayerErrorType.native);
      },
    );

    // =========================
    // buffering
    // =========================

    _bufferingSub = _player.stream.buffering.listen(
      (loading) {
        if (_disposed) return;

        _loadingSubject.add(loading);

        if (loading) {
          _stateSubject.add(PlayerState.buffering);
        } else {
          _stateSubject.add(_playingSubject.value ? PlayerState.playing : PlayerState.paused);
        }
      },
      onError: (e, s) {
        _emitError(e, s, PlayerErrorType.native);
      },
    );

    // =========================
    // width
    // =========================

    _widthSub = _player.stream.width.listen((val) {
      if (_disposed) return;

      _widthSubject.add(val);
    });

    // =========================
    // height
    // =========================

    _heightSub = _player.stream.height.listen((val) {
      if (_disposed) return;

      _heightSubject.add(val);
    });

    // =========================
    // completed
    // =========================

    _completeSub = _player.stream.completed.listen(
      (completed) {
        if (_disposed) return;

        if (!completed) return;

        _completeSubject.add(true);

        _stateSubject.add(PlayerState.completed);
      },
      onError: (e, s) {
        _emitError(e, s, PlayerErrorType.native);
      },
    );

    // =========================
    // error
    // =========================

    _errorSub = _player.stream.error.distinct().listen((error) {
      if (_disposed) return;

      final type = _mapErrorType(error.toString());

      _scheduleTransientError(PlayerException(message: error.toString(), type: type));
    });

    // =========================
    // collect
    // =========================

    _subscriptions.addAll([_playingSub!, _bufferingSub!, _widthSub!, _heightSub!, _completeSub!, _errorSub!]);
  }

  // =========================
  // cancel subscriptions
  // =========================

  Future<void> _cancelAllSubscriptions() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }

    _subscriptions.clear();

    _playingSub = null;
    _bufferingSub = null;
    _widthSub = null;
    _heightSub = null;
    _completeSub = null;
    _errorSub = null;

    for (final sub in _enhancementSubs) {
      await sub.cancel();
    }
    _enhancementSubs.clear();
  }

  // =========================
  // 画质增强（仅 mpv 内核）
  // =========================

  final List<StreamSubscription> _enhancementSubs = [];

  void _bindEnhancementListeners() {
    final player = SettingsService.to.player;
    // 设置变更即时生效：超分/缓冲/音量均衡任一变化都重新下发整组属性
    _enhancementSubs.addAll([
      player.superResolution.listen((_) => _applyMpvEnhancements()),
      player.liveBufferSizeMB.listen((_) => _applyMpvEnhancements()),
      player.enableVolumeNormalization.listen((_) => _applyMpvEnhancements()),
    ]);
  }


  Future<void> _applyMpvEnhancements() async {
    if (_disposed) return;
    if (_player.platform is! NativePlayer) return;
    final native = _player.platform as dynamic;
    try {
      // 直播缓冲：预读缓冲放大抗抖动（越大延迟越高），回退缓冲清零（直播无需回看）
      final bufferMB = SettingsService.to.player.liveBufferSizeMB.v;
      await native.setProperty('demuxer-max-bytes', (bufferMB * 2 * 1024 * 1024).toString());
      await native.setProperty('demuxer-max-back-bytes', '0');

      // 音量均衡：拉平不同直播间之间与直播过程中的音量波动
      final normalize = SettingsService.to.player.enableVolumeNormalization.v;
      await native.setProperty('af', normalize ? 'loudnorm=I=-16:LRA=11:TP=-1.5' : '');

      // Anime4K 超分（纯音频模式无画面，跳过）
      final mode = SettingsService.to.player.superResolution.v;
      if (!_isAudioOnly && (mode == 'quality' || mode == 'efficiency')) {
        final paths = await ShaderUtils.shaderPathsFor(mode);
        if (paths != null && paths.isNotEmpty) {
          await native.command([
            'change-list',
            'glsl-shaders',
            'set',
            paths.join(ShaderUtils.listSeparator),
          ]);
        }
      } else {
        await native.command(['change-list', 'glsl-shaders', 'clr', '']);
      }
    } catch (_) {
      // 属性下发失败不影响播放
    }
  }

  // =========================
  // transient error confirm
  // =========================

  /// mpv 在直播流启动阶段常报可恢复错误（如硬件解码器/VO 初始化瞬态失败，
  /// 内核自动回退软解后声音先出、画面稍后跟上）。立即上报会误弹"解码失败"
  /// 提示并触发无谓的内核回退。这里延迟确认：到期仍未恢复播放才上报。
  void _scheduleTransientError(PlayerException exception) {
    _pendingTransientError = exception;
    _transientErrorTimer?.cancel();
    _transientErrorTimer = Timer(const Duration(milliseconds: 2500), () {
      _transientErrorTimer = null;
      if (_disposed) return;
      final pending = _pendingTransientError;
      _pendingTransientError = null;
      if (pending == null) return;
      _safeAddError(pending);
      _stateSubject.add(PlayerState.error);
    });
  }

  /// 播放已实际恢复，丢弃挂起的瞬态错误
  void _discardTransientError() {
    _pendingTransientError = null;
    _transientErrorTimer?.cancel();
    _transientErrorTimer = null;
  }

  // =========================
  // emit error
  // =========================

  void _emitError(Object error, StackTrace stackTrace, PlayerErrorType type) {
    if (_disposed) return;

    _safeAddError(PlayerException(message: error.toString(), type: type, error: error, stackTrace: stackTrace));

    _stateSubject.add(PlayerState.error);
  }

  void _safeAddError(PlayerException exception) {
    if (_disposed) return;

    if (_errorSubject.isClosed) return;

    _errorSubject.add(exception);
  }

  // =========================
  // error type
  // =========================

  PlayerErrorType _mapErrorType(String error) {
    final lower = error.toLowerCase();

    if (lower.contains('network') || lower.contains('timeout') || lower.contains('io')) {
      return PlayerErrorType.network;
    }

    if (lower.contains('codec') || lower.contains('mediacodec') || lower.contains('decode')) {
      return PlayerErrorType.codec;
    }

    if (lower.contains('404') || lower.contains('source') || lower.contains('open')) {
      return PlayerErrorType.source;
    }

    if (lower.contains('surface') || lower.contains('texture')) {
      return PlayerErrorType.texture;
    }

    return PlayerErrorType.native;
  }

  // =========================
  // widget
  // =========================

  @override
  Widget getVideoWidget() {
    if (_isAudioOnly) {
      return const SizedBox.shrink();
    }
    return RepaintBoundary(
      child: Video(
        controller: _controller,
        controls: NoVideoControls,
        pauseUponEnteringBackgroundMode: !SettingsService.to.app.enableBackgroundPlay.v,
        resumeUponEnteringForegroundMode: !SettingsService.to.app.enableBackgroundPlay.v,
      ),
    );
  }

  // =========================
  // play
  // =========================

  @override
  Future<void> play() async {
    await _player.play();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
  }

  @override
  Future<void> stop() async {
    await _player.pause();

    await _player.seek(Duration.zero);

    _stateSubject.add(PlayerState.stopped);
  }

  @override
  Future<void> softStop() async {
    await _player.setVolume(0.0);

    await _player.pause();
  }

  @override
  Future<void> setVolume(double volume) async {
    final vol = (volume * 100).clamp(0.0, 100.0);

    await _player.setVolume(vol);
  }

  // =========================
  // applyAudioOnlySettings
  // =========================

  Future<void> applyAudioOnlySettings() async {
    final native = _player.platform as dynamic;
    await native.setProperty('vid', 'no');
    await native.setProperty('video', 'no');
    await native.setProperty('vo', 'null');
    await native.setProperty('hwdec', 'no');
    await native.setProperty('audio-display', 'no');
  }

  // =========================
  // dispose
  // =========================

  @override
  Future<void> hardDispose() async {
    if (_disposed) return;

    _disposed = true;

    _discardTransientError();

    _initialized = false;

    _listenerBound = false;

    await _cancelAllSubscriptions();

    try {
      await _player.stop();
    } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 300));

    try {
      await _player.dispose();
    } catch (_) {}

    await Future.wait([
      _stateSubject.close(),
      _playingSubject.close(),
      _loadingSubject.close(),
      _errorSubject.close(),
      _completeSubject.close(),
      _widthSubject.close(),
      _heightSubject.close(),
    ]);
  }

  // =========================
  // getter
  // =========================

  @override
  bool get isInitialized => _initialized;

  @override
  bool get isPlayingNow => _playingSubject.value;

  @override
  int? get videoWidth => _widthSubject.value;

  @override
  int? get videoHeight => _heightSubject.value;

  @override
  int? get audioBitrateKbps => _player.state.audioBitrate?.toInt();

  @override
  bool get isReusable => false;

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
