import 'dart:async';
import 'dart:math' as math;

import 'player_pool.dart';
import 'line_fallback_manager.dart';
import '../models/player_state.dart';
import 'preload_player_manager.dart';
import '../models/player_engine.dart';
import 'engine_fallback_manager.dart';

import 'package:floating/floating.dart';
import 'package:flutter/scheduler.dart';

import '../models/player_exception.dart';

import 'package:remixicon/remixicon.dart';

import '../models/player_error_type.dart';

import 'package:rxdart/rxdart.dart' hide Rx;
import 'package:pure_live/common/index.dart';

import '../interface/unified_player_interface.dart';

import 'package:pure_live/routes/app_navigation.dart';
import 'package:flutter_floating/flutter_floating.dart';
import 'package:pure_live/player/utils/player_consts.dart';
import 'package:pure_live/common/global/platform_utils.dart';
import 'package:pure_live/player/core/live_audio_service.dart';
import 'package:pure_live/modules/live_play/controllers/player_state.dart';
import 'package:pure_live/modules/live_play/controllers/live_play_controller.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/compact_danmaku_overlay.dart';

/// release 构建下 dart:developer 的 log 不输出到 logcat——改走 debugPrint，
/// 保证换线/降级/卡死等关键诊断日志在 logcat（I/flutter）里可见。
void log(String message, {String? name, DateTime? time, Object? error, StackTrace? stackTrace}) {
  final prefix = name != null ? '[$name] ' : '';
  final err = error != null ? ' | error=$error' : '';
  debugPrint('$prefix$message$err', wrapWidth: 160);
}

class PlayerManager {
  final PlayerPool playerPool;
  final EngineFallbackManager fallbackManager;
  final PreloadPlayerManager preloadManager;
  final LineFallbackManager lineManager;

  int _sessionId = 0;
  bool _isClosing = false;

  PlayerManager({
    required this.playerPool,
    required this.fallbackManager,
    required this.preloadManager,
    required this.lineManager,
  }) {
    _pipStateSubscription = isInPip.listen((value) {
      GlobalPlayerState.to.isPipMode.value = value;
      if (!value && !isFloating.value && !_appFloatingPrepared) {
        _videoController?.clearPipDanmaku();
      }
    });
  }

  bool _isSessionValid(int id) => !_disposed && !_isClosing && _sessionId == id;

  UnifiedPlayer? _currentPlayer;
  PlayerEngine? _runtimeEngine;
  PlayerEngine? _defaultEngine;
  bool _runtimeAudioOnly = false;

  /// "有声音没画面"看门狗：开播后观察这段时间，若已经在播却始终没有有效的
  /// 视频宽高，就按解码失败处理（换下一条线路）。
  ///
  /// 实测 B站部分线路（HEVC 的 flv）能正常出声但**根本解析不出视频轨**
  /// （mpv 的 video-params 恒为空），而且不会触发 error 事件，只靠错误回调
  /// 无法自动换线——用户当时只能手动切线路才恢复。这里补上这种"静默无画面"
  /// 的检测，换线动作与手动切换一致；取流侧也已把这类线路排到后面。
  static const Duration _videoFrameWatchdogDelay = Duration(seconds: 7);

  /// 连续换线仍无画面的次数上限，避免在全部线路都异常时无限换下去
  static const int _maxNoVideoSwitches = 4;

  Timer? _videoWatchdogTimer;
  bool _videoFrameSeen = false;
  int _noVideoSwitches = 0;

  /// "播放中卡死"看门狗：起播成功后流断（CDN 断流/网络抖动）时 mpv 常常
  /// 停在 buffering 且**不报 error**——此前只有起播期看门狗，播放中卡死
  /// 无人检测，用户只能返回重进。这里对持续 buffering 超时按网络错误走
  /// 既有换线机制自愈；期间点击暂停恢复无效的兜底见 [resumeWithWatchdog]。
  static const Duration _stallWatchdogDelay = Duration(seconds: 12);

  /// 连续卡缓冲换线的上限，全部线路都卡时停下报错（避免无限换线耗流量）
  static const int _maxStallSwitches = 4;

  Timer? _stallWatchdogTimer;
  int _stallSwitches = 0;

  /// "播放中停摆"看门狗：mpv 可能在**不报 error、不报 buffering、也没被业务
  /// 暂停**的情况下直接停止播放（2026-10-10 18:18:00 实测复现：playing→false，
  /// 而 buffering 只在 1ms 内 true→false 闪了一下）。这种状态下卡缓冲看门狗
  /// 会因缓冲结束被撤销、首帧看门狗早已出画面而永久失效，画面就永久冻住。
  /// 检测口径：非主动暂停地停摆 N 秒 → 按网络错误走既有换线自愈。
  static const Duration _stoppedWatchdogDelay = Duration(seconds: 8);

  /// 连续停摆换线的上限，全部线路都停摆时停下报错（避免无限换线耗流量）
  static const int _maxStoppedSwitches = 4;

  Timer? _stoppedWatchdogTimer;
  int _stoppedSwitches = 0;

  /// 是否为业务主动暂停（点击/键盘/生命周期/定时器），停摆检测必须跳过它们
  bool _pausedIntentionally = false;

  /// 本会话是否**已经播放成功过**：冷启动/刚开流时会先收到一次
  /// `onPlaying=false`（实测 18:40:37 有一例），若此时就起停摆检测，
  /// 播放器根本还没开始播放就会被判"停摆"并误换线，必须先播起来过。
  bool _playedInSession = false;

  String? _currentUrl;
  List<String> _currentPlayUrls = [];
  Map<String, String> _currentHeaders = {};

  final RxBool isInitialized = false.obs;
  final RxBool hasError = false.obs;
  final RxBool isVerticalVideo = false.obs;
  final RxBool isInPip = false.obs;
  final RxBool isPipPreparing = false.obs;
  final RxBool isFloating = false.obs;
  final RxBool isHovered = false.obs;
  final RxInt videoFitIndex = 0.obs;
  Rx<ValueKey> videoKey = Rx<ValueKey>(const ValueKey("video_0"));

  /// 全屏双指缩放画面的变换（B站客户端效果）。
  /// 仅作用于视频画面层（控件面板不缩放），identity 表示原始画面。
  /// 参见 [resetPinchZoom]；手势处理在 VideoControllerPanel 的
  /// BrightnessVolumnDargArea（双指捏合缩放、单指保留亮度/音量拖动）。
  final TransformationController pinchTransform = TransformationController();
  Ticker? _pinchResetTicker;

  /// 是否处于缩放状态（非原始画面）
  bool get isPinchZoomed => !MatrixUtils.isIdentity(pinchTransform.value);

  /// 还原画面到原始大小。默认带 180ms 缓动动画。
  void resetPinchZoom({bool animated = true}) {
    final from = pinchTransform.value;
    if (MatrixUtils.isIdentity(from)) return;
    _pinchResetTicker?.stop();
    _pinchResetTicker = null;
    if (!animated) {
      pinchTransform.value = Matrix4.identity();
      return;
    }
    final begin = from.clone();
    final target = Matrix4.identity();
    final tween = Matrix4Tween(begin: begin, end: target);
    _pinchResetTicker = Ticker((elapsed) {
      const duration = Duration(milliseconds: 180);
      final t = (elapsed.inMicroseconds / duration.inMicroseconds).clamp(0.0, 1.0);
      pinchTransform.value = tween.transform(Curves.easeOutCubic.transform(t));
      if (t >= 1.0) {
        _pinchResetTicker?.stop();
        _pinchResetTicker = null;
        pinchTransform.value = target;
      }
    })
      ..start();
  }

  final _stateSubject = BehaviorSubject<PlayerState>.seeded(PlayerState.idle);
  final _playingSubject = BehaviorSubject<bool>.seeded(false);
  final _loadingSubject = BehaviorSubject<bool>.seeded(false);
  final _completeSubject = BehaviorSubject<bool>.seeded(false);
  final _errorSubject = PublishSubject<PlayerException>();
  final _widthSubject = BehaviorSubject<int?>.seeded(null);
  final _heightSubject = BehaviorSubject<int?>.seeded(null);

  final List<StreamSubscription> _subscriptions = [];
  StreamSubscription<PiPStatus>? _pipSubscription;
  StreamSubscription<bool>? _pipStateSubscription;

  bool _disposed = false;
  bool _isSwitchingDueToFallback = false;
  bool _isHandlingError = false;
  static const String _floatTag = "global_video_player";
  Timer? _hideTimer;
  late Floating floating;
  LiveRoom? currentFloatRoom;
  VideoController? _videoController;
  VoidCallback? _floatingDanmakuDisposer;
  bool _appFloatingPrepared = false;
  bool _pipTransitionInFlight = false;
  final GlobalKey _pipSourceKey = GlobalKey(debugLabel: 'pip-video-source');

  UnifiedPlayer? get currentPlayer => _currentPlayer;
  PlayerEngine get currentEngine => _runtimeEngine ?? _defaultEngine ?? PlayerEngine.mediaKit;
  Stream<PlayerState> get onStateChanged => _stateSubject.stream;
  Stream<bool> get onPlaying => _playingSubject.stream;
  Stream<bool> get onLoading => _loadingSubject.stream;
  Stream<bool> get onComplete => _completeSubject.stream;
  Stream<PlayerException> get onError => _errorSubject.stream;
  Stream<int?> get width => _widthSubject.stream;
  Stream<int?> get height => _heightSubject.stream;
  bool get isPlayingNow => _playingSubject.value;
  bool get shouldKeepDanmakuForAppFloating => _appFloatingPrepared || isFloating.value;
  bool get isCompactModeActive => isInPip.value || isPipPreparing.value || isFloating.value || _appFloatingPrepared;

  void attachVideoController(VideoController controller) {
    _videoController = controller;
  }

  void detachVideoController(VideoController controller) {
    if (identical(_videoController, controller)) {
      _videoController = null;
    }
  }

  void prepareAppFloating({required VoidCallback onClose}) {
    _floatingDanmakuDisposer?.call();
    _floatingDanmakuDisposer = onClose;
    _appFloatingPrepared = true;
  }

  Widget _buildCompactDanmaku() {
    final controller = _videoController;
    return controller == null ? const SizedBox.shrink() : CompactDanmakuOverlay(controller: controller);
  }

  void _releaseAppFloatingResources() {
    _appFloatingPrepared = false;
    final disposer = _floatingDanmakuDisposer;
    _floatingDanmakuDisposer = null;
    disposer?.call();
    if (!isInPip.value && !isFloating.value) {
      _videoController?.clearPipDanmaku();
    }
  }

  double get currentVideoRatio {
    final w = _widthSubject.value?.toDouble() ?? 1920;
    final h = _heightSubject.value?.toDouble() ?? 1080;
    if (w <= 0 || h <= 0) return 16 / 9;
    return w / h;
  }

  Future<void> initialize({PlayerEngine engine = PlayerEngine.mediaKit, bool audioOnly = false}) async {
    if (_disposed) return;
    _stateSubject.add(PlayerState.initializing);
    try {
      _defaultEngine = engine;
      _runtimeEngine = engine;
      _currentPlayer = await playerPool.getPlayer(engine, audioOnly: audioOnly);
      _runtimeAudioOnly = audioOnly;
      await _bindPlayerStreams(_currentPlayer!);
      LiveAudioService.setPlayer(_currentPlayer!);
      if (PlatformUtils.isAndroid) {
        floating = Floating();
        _pipSubscription?.cancel();
        _pipSubscription = floating.pipStatusStream.listen((status) {
          isInPip.value = status == PiPStatus.enabled;
        });
      }
      isInitialized.value = true;
      _stateSubject.add(PlayerState.initialized);
    } catch (e, s) {
      hasError.value = true;
      final exception = PlayerException(
        message: 'Initialize player failed',
        type: PlayerErrorType.initialization,
        error: e,
        stackTrace: s,
      );
      _errorSubject.add(exception);
      _stateSubject.add(PlayerState.error);
      throw exception;
    }
  }

  Future<void> play(
    String url,
    List<String> playUrls,
    Map<String, String> headers, {
    LiveRoom? room,
    bool audioOnly = false,
  }) async {
    if (_disposed || _isClosing) return;
    final mySessionId = ++_sessionId;
    // 新一轮开流（含错误换线后重开）：把上一轮的"主动暂停"标记清掉，
    // 否则新会话在 playing=false 时会被旧标记挡住停摆检测
    _pausedIntentionally = false;
    _playedInSession = false;

    if (room?.roomId != currentFloatRoom?.roomId) {
      lineManager.reset();
    }
    if (_currentPlayer == null || _runtimeEngine == null) {
      final String savedKey = SettingsService.to.player.videoPlayerKey.v;
      final String validKey = PlayerConsts.engines.containsKey(savedKey) ? savedKey : PlayerConsts.defaultKey;
      _defaultEngine = PlayerConsts.engines[validKey]!;
      _runtimeEngine = _defaultEngine;
      log('No current player, initializing with default engine: $_defaultEngine', name: 'PlayerManager');
      await initialize(engine: _defaultEngine!, audioOnly: audioOnly);
    } else if (_runtimeEngine != _defaultEngine && !_isSwitchingDueToFallback) {
      await switchEngine(_defaultEngine!, isManual: false, audioOnly: audioOnly);
    } else if (_runtimeAudioOnly != audioOnly) {
      await _recreateForAudioMode(audioOnly);
    }

    if (!_isSessionValid(mySessionId)) return;

    final player = _currentPlayer;
    if (player == null) {
      throw PlayerException(message: 'Current player is null', type: PlayerErrorType.lifecycle);
    }

    // Every bundled player has a native audio-only path.  Opening the original
    // live URL directly avoids a second FFmpeg decode pipeline and removes the
    // previous fixed two-second wait / 30-second pipe timeout.
    final String targetUrl = url;
    final List<String> targetPlayUrls = List.from(playUrls);

    _currentUrl = targetUrl;
    _currentPlayUrls = targetPlayUrls;
    _currentHeaders = headers;
    currentFloatRoom = room;
    hasError.value = false;
    // 新的一次打开：重新观察是否出画面（宽高会由适配器重新上报）
    _videoFrameSeen = false;
    _videoWatchdogTimer?.cancel();
    _videoWatchdogTimer = null;

    try {
      _stateSubject.add(PlayerState.preparing);
      await player.setDataSource(targetUrl, targetPlayUrls, headers, room: room, audioOnly: audioOnly);
      if (!_isSessionValid(mySessionId)) return;

      // Desktop player adapters do not all restore the per-room volume in
      // setDataSource. Apply it centrally so every engine starts consistently.
      if (PlatformUtils.isDesktop && room != null) {
        await player.setVolume(room.getSavedVolume().clamp(0.0, 1.0));
      }
      if (!_isSessionValid(mySessionId)) return;

      LiveAudioService.setPlayer(player);
      LiveAudioService.start(room!.roomId!, room.nick ?? "", room.title ?? "", room.avatar);
      videoKey.value = ValueKey("video_${DateTime.now().millisecondsSinceEpoch}");
      _stateSubject.add(PlayerState.ready);
      _armVideoWatchdog(mySessionId);
    } on PlayerException catch (e) {
      if (!_isHandlingError && _isSessionValid(mySessionId)) {
        await _handleError(e, sessionId: mySessionId);
      }
    } catch (e, s) {
      log(e.toString());
      if (!_isHandlingError && _isSessionValid(mySessionId)) {
        final exception = PlayerException(
          message: 'Play failed',
          type: PlayerErrorType.unknown,
          error: e,
          stackTrace: s,
        );
        await _handleError(exception, sessionId: mySessionId);
      }
    } finally {
      _isSwitchingDueToFallback = false;
    }
  }

  Future<void> replay() async {
    if (_currentUrl == null) return;
    await play(_currentUrl!, _currentPlayUrls, _currentHeaders, room: currentFloatRoom);
  }

  Future<void> _recreateForAudioMode(bool audioOnly) async {
    final engine = _runtimeEngine;
    if (engine == null || _runtimeAudioOnly == audioOnly) return;
    final oldPlayer = _currentPlayer;
    await _clearSubscriptions();
    if (oldPlayer != null) {
      await playerPool.removeFromCache(engine);
    }
    final newPlayer = await playerPool.getPlayer(engine, audioOnly: audioOnly);
    _currentPlayer = newPlayer;
    _runtimeAudioOnly = audioOnly;
    await _bindPlayerStreams(newPlayer);
    LiveAudioService.setPlayer(newPlayer);
    videoKey.value = ValueKey("video_${DateTime.now().millisecondsSinceEpoch}");
  }

  Future<void> switchEngine(PlayerEngine engine, {bool isManual = false, bool? audioOnly}) async {
    if (_disposed || _isClosing) return;
    if (_runtimeEngine == engine && _currentPlayer != null) return;
    try {
      final oldPlayer = _currentPlayer;
      final oldEngine = _runtimeEngine;
      await _clearSubscriptions();
      final targetAudioOnly = audioOnly ?? _runtimeAudioOnly;
      final newPlayer = await playerPool.getPlayer(engine, audioOnly: targetAudioOnly);
      _currentPlayer = newPlayer;
      _runtimeEngine = engine;
      _runtimeAudioOnly = targetAudioOnly;
      if (isManual) _defaultEngine = engine;
      log('Switch engine to $engine', name: 'PlayerManager');
      await _bindPlayerStreams(newPlayer);
      LiveAudioService.setPlayer(_currentPlayer!);
      if (oldPlayer != null && oldEngine != null) {
        await _safeDestroyPlayer(oldPlayer, oldEngine);
      }
      videoKey.value = ValueKey("video_${DateTime.now().millisecondsSinceEpoch}");
    } catch (e, s) {
      final exception = PlayerException(
        message: 'Switch engine failed',
        type: PlayerErrorType.lifecycle,
        error: e,
        stackTrace: s,
      );
      _errorSubject.add(exception);
      rethrow;
    }
  }

  Future<void> _safeDestroyPlayer(UnifiedPlayer player, PlayerEngine engine) async {
    try {
      await player.hardDispose();
      await playerPool.removeFromCache(engine);
    } catch (e, s) {
      log("destroy player error: $e", stackTrace: s);
    }
  }

  Future<void> preload(String url, List<String> playUrls, Map<String, String> headers) async {
    if (_disposed || _isClosing) return;
    final standby = await playerPool.getPlayer(_runtimeEngine!);
    await preloadManager.preload(standby, url, playUrls, headers);
  }

  Future<void> seamlessSwitch() async {
    if (_disposed || _isClosing) return;
    await preloadManager.switchToStandby();
    final player = preloadManager.current;
    if (player == null) return;
    await _clearSubscriptions();
    _currentPlayer = player;
    await _bindPlayerStreams(player);
  }

  /// [source] 仅用于排障：直播出现"画面冻住但状态正常"时，需要确认是谁暂停了播放。
  Future<void> togglePlayPause({String source = 'unspecified'}) async {
    if (_currentPlayer == null) return;
    log('[PauseTrace] togglePlayPause src=$source isPlaying=$isPlayingNow'
        ' -> ${isPlayingNow ? 'pause' : 'resume'}');
    if (isPlayingNow) {
      await pause(source: source);
    } else {
      await resume(source: source);
    }
  }

  Future<void> pause({String source = 'unspecified'}) async {
    _pausedIntentionally = true;
    _disarmStoppedWatchdog();
    log('[PauseTrace] pause() src=$source engine=${_runtimeEngine?.name}'
        ' session=$_sessionId playing=$isPlayingNow');
    await _currentPlayer?.pause();
  }

  Future<void> resume({String source = 'unspecified'}) async {
    _pausedIntentionally = false;
    log('[PauseTrace] resume() src=$source engine=${_runtimeEngine?.name}'
        ' session=$_sessionId playing=$isPlayingNow');
    await _currentPlayer?.play();
  }

  Future<void> stop() async {
    await close();
    closeAppFloating();
  }

  Future<void> setVolume(double volume) async {
    await _currentPlayer?.setVolume(volume.clamp(0.0, 1.0));
  }

  void changeVideoFit(int index) => videoFitIndex.value = index;

  Future<void> enablePip() async {
    if (PlatformUtils.isAndroid) {
      if (_pipTransitionInFlight) return;
      _pipTransitionInFlight = true;
      try {
        final status = await floating.pipStatus;
        if (status != PiPStatus.disabled) return;

        // Android captures the Activity at the start of the PiP animation.
        // Build the compact video-only surface first, then enter PiP after a
        // rendered frame so Texture/PlatformView players do not show an app
        // icon or a black placeholder while being reattached.
        final sourceRectHint = _currentPipSourceRect();
        isPipPreparing.value = true;
        await SchedulerBinding.instance.endOfFrame;

        final rational = isVerticalVideo.value ? const Rational.vertical() : const Rational.landscape();
        final result = await floating.enable(ImmediatePiP(aspectRatio: rational, sourceRectHint: sourceRectHint));
        if (result == PiPStatus.enabled) isInPip.value = true;
      } finally {
        isPipPreparing.value = false;
        _pipTransitionInFlight = false;
      }
    }
  }

  math.Rectangle<int>? _currentPipSourceRect() {
    final context = _pipSourceKey.currentContext;
    final renderObject = context?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    final origin = renderObject.localToGlobal(Offset.zero);
    final ratio = View.of(context!).devicePixelRatio;
    final left = (origin.dx * ratio).round();
    final top = (origin.dy * ratio).round();
    final width = (renderObject.size.width * ratio).round();
    final height = (renderObject.size.height * ratio).round();
    if (width <= 0 || height <= 0) return null;
    return math.Rectangle<int>(left, top, width, height);
  }

  Future<void> exitPip() async {
    if (PlatformUtils.isWindows) {
      GlobalPlayerState.to.reset();
    }
    // isInPip 由 pipStatusStream 驱动，但流可能丢事件导致标志卡在 true
    // （之后返回键会被 escape 处理器按画中画状态静默吞掉）。主动退出时
    // 强制复位，让状态自愈；若真仍在画中画，后续流事件会纠正回来。
    isInPip.value = false;
  }

  void showAppFloating() {
    if (!_appFloatingPrepared) return;
    floatingManager.disposeFloating(_floatTag);
    _hideTimer?.cancel();
    double maxSide = PlatformUtils.isWindows ? 350 : 220;
    double ratio = currentVideoRatio;
    double floatWidth;
    double floatHeight;
    if (ratio >= 1) {
      floatWidth = maxSide;
      floatHeight = maxSide / ratio;
    } else {
      floatHeight = maxSide * 1.2;
      floatWidth = floatHeight * ratio;
      if (floatWidth < 120) {
        floatWidth = 120;
        floatHeight = floatWidth / ratio;
      }
    }

    void resetHideTimer() {
      if (PlatformUtils.isAndroid || PlatformUtils.isIOS) {
        _hideTimer?.cancel();
        _hideTimer = Timer(const Duration(seconds: 3), () {
          isHovered.value = false;
        });
      }
    }

    floatingManager.createFloating(
      _floatTag,
      FloatingOverlay(
        MouseRegion(
          onEnter: (_) {
            if (PlatformUtils.isWindows || PlatformUtils.isMacOS) isHovered.value = true;
          },
          onExit: (_) {
            if (PlatformUtils.isWindows || PlatformUtils.isMacOS) isHovered.value = false;
          },
          child: Container(
            width: floatWidth,
            height: floatHeight,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: Colors.black),
            child: Stack(
              children: [
                Positioned.fill(
                  child: getVideoWidget(videoFitIndex.value, fitList: SettingsService.to.player.videoFitArray),
                ),
                Positioned.fill(child: _buildCompactDanmaku()),
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      closeAppFloating();
                      if (currentFloatRoom != null) {
                        AppNavigator.toLiveRoomDetail(liveRoom: currentFloatRoom!);
                      }
                    },
                    child: const SizedBox.expand(),
                  ),
                ),
                Center(
                  child: AnimatedOpacity(
                    opacity: isHovered.value ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer(
                      ignoring: !isHovered.value,
                      child: StreamBuilder<bool>(
                        stream: onPlaying,
                        initialData: isPlayingNow,
                        builder: (context, snapshot) {
                          var isPlay = snapshot.data ?? true;
                          return IconButton(
                            iconSize: 42,
                            style: IconButton.styleFrom(backgroundColor: Colors.black45),
                            icon: Icon(
                              isPlay ? Icons.pause_circle_filled : Icons.play_circle_filled,
                              color: Colors.white,
                            ),
                            onPressed: () {
                              togglePlayPause(source: 'ui.floatingCenterButton');
                              resetHideTimer();
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 4,
                  top: 4,
                  child: Obx(
                    () => AnimatedOpacity(
                      opacity: isHovered.value ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: IgnorePointer(
                        ignoring: !isHovered.value,
                        child: IconButton(
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(4),
                          style: IconButton.styleFrom(backgroundColor: Colors.black45),
                          icon: const Icon(Icons.close, color: Colors.white, size: 20),
                          onPressed: () async {
                            await stop();
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        right: 50,
        top: 100,
        slideType: FloatingEdgeType.onRightAndTop,
        params: FloatingParams(isSnapToEdge: false, snapToEdgeSpace: 10, dragOpacity: 0.8),
      ),
    );
    floatingManager.getFloating(_floatTag).open(Get.context!);
    isFloating.value = true;
    if (PlatformUtils.isAndroid || PlatformUtils.isIOS) {
      isHovered.value = true;
      resetHideTimer();
    }
  }

  void closeAppFloating() {
    if (isFloating.value) {
      floatingManager.disposeFloating(_floatTag);
    }
    isFloating.value = false;
    _releaseAppFloatingResources();
    if (!isInPip.value) {
      _videoController?.clearPipDanmaku();
    }
  }

  Widget buildPiPOverlay() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: MouseRegion(
        onEnter: (_) => isHovered.value = true,
        onExit: (_) => isHovered.value = false,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(color: Colors.black),
          child: Stack(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) {},
                onDoubleTap: () async {
                  await exitPip();
                },
                child: getVideoWidget(videoFitIndex.value, fitList: SettingsService.to.player.videoFitArray),
              ),
              Positioned.fill(child: _buildCompactDanmaku()),
              Center(
                child: Obx(
                  () => AnimatedOpacity(
                    opacity: isHovered.value ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: StreamBuilder<bool>(
                      stream: onPlaying,
                      initialData: isPlayingNow,
                      builder: (context, snapshot) {
                        var isPlay = snapshot.data ?? true;
                        return IconButton(
                          iconSize: 42,
                          style: IconButton.styleFrom(backgroundColor: Colors.black45),
                          icon: Icon(
                            isPlay ? Icons.pause_circle_filled : Icons.play_circle_filled,
                            color: Colors.white,
                          ),
                          onPressed: () {
                            togglePlayPause(source: 'ui.pipCenterButton');
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: Obx(
                  () => AnimatedOpacity(
                    opacity: isHovered.value ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () async {
                        await exitPip();
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildAudioOnlyUI(BuildContext context, LivePlayController livePlayController) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final maxHeight = constraints.maxHeight;
        final compact = maxHeight < 500;
        final avatarSize = compact ? (maxHeight * 0.22).clamp(50.0, 76.0) : 100.0;
        final titleSize = compact ? 14.0 : 22.0;
        final nickSize = compact ? 11.0 : 13.0;
        final badgeTextSize = compact ? 11.0 : 13.0;
        final gapLarge = compact ? 10.0 : 24.0;
        final gapMedium = compact ? 8.0 : 16.0;
        final gapSmall = compact ? 4.0 : 8.0;

        return Obx(() {
          final state = livePlayController.state.value;
          final detail = state.room.detail;
          final avatar = detail?.avatar ?? '';
          final title = detail?.title ?? '';
          final nick = detail?.nick ?? '';

          return Container(
            width: maxWidth,
            height: maxHeight,
            alignment: Alignment.center,
            color: Colors.transparent,
            child: SingleChildScrollView(
              physics: compact ? const ClampingScrollPhysics() : const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 24, vertical: compact ? 4 : 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: compact ? maxWidth : 460),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.95, end: 1.05),
                      duration: const Duration(milliseconds: 1500),
                      curve: Curves.easeInOut,
                      builder: (context, scale, child) {
                        return Transform.scale(scale: scale, child: child);
                      },
                      child: Container(
                        width: avatarSize,
                        height: avatarSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.04),
                              blurRadius: compact ? 10 : 20,
                              spreadRadius: compact ? 4 : 8,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: avatar.isNotEmpty
                              ? Image.network(
                                  avatar,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Icon(Remix.user_3_line, color: Colors.white24),
                                )
                              : const Icon(Remix.user_3_line, color: Colors.white24),
                        ),
                      ),
                    ),
                    SizedBox(height: gapLarge),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 24),
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        maxLines: compact ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: titleSize,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    SizedBox(height: gapSmall),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 14, vertical: compact ? 2 : 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: Text(
                        nick,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: nickSize,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    SizedBox(height: gapMedium),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 16, vertical: compact ? 5 : 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        color: Colors.white.withValues(alpha: 0.08),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Remix.headphone_line,
                            color: Colors.white.withValues(alpha: 0.85),
                            size: compact ? 12 : 16,
                          ),
                          SizedBox(width: compact ? 4 : 8),
                          Text(
                            i18n("audio_only_mode"),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: badgeTextSize,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
  }

  Widget getVideoWidget(int fitIndex, {Widget? controls, required List<BoxFit> fitList}) {
    final LivePlayController livePlayController = Get.find<LivePlayController>();
    return RepaintBoundary(
      key: _pipSourceKey,
      child: Container(
          color: Colors.black,
          padding: const EdgeInsets.all(0),
          child: StreamBuilder<bool>(
            stream: onPlaying,
            initialData: isPlayingNow,
            builder: (context, snapshot) {
              if (_currentPlayer == null) {
                return _buildPlaceholder();
              }
              final boxFit = fitList[fitIndex];
              final content = KeyedSubtree(
                key: videoKey.value,
                child: Container(
                  color: Colors.black,
                  width: double.infinity,
                  height: double.infinity,
                  child: Stack(
                    children: [
                      if (livePlayController.state.value.player.isCurrentRoomAudioOnly)
                        buildAudioOnlyUI(context, livePlayController)
                      else
                        Positioned.fill(
                          child: Container(
                            color: Colors.black,
                            child: ValueListenableBuilder<Matrix4>(
                              valueListenable: pinchTransform,
                              // ClipRect：缩放/平移矩阵残留时把溢出部分裁在视频窗口内，
                              // 避免画面绘制到相邻布局（如弹幕列表）上方。
                              builder: (context, transform, videoChild) => ClipRect(
                                child: Transform(transform: transform, child: videoChild),
                              ),
                              child: FittedBox(
                                fit: boxFit,
                                clipBehavior: Clip.hardEdge,
                                child: StreamBuilder<List<int?>>(
                                  stream: CombineLatestStream.list([width, height]),
                                  builder: (context, snapshot) {
                                    final vW = snapshot.data?[0]?.toDouble() ?? 1920.0;
                                    final vH = snapshot.data?[1]?.toDouble() ?? 1080.0;
                                    return SizedBox(width: vW, height: vH, child: _currentPlayer!.getVideoWidget());
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (controls != null) Positioned.fill(child: controls),
                    ],
                  ),
                ),
              );
              // The same player surface is used in and out of PiP. Wrapping
              // identical children in PiPSwitcher rebuilt an AnimatedSwitcher
              // exactly when Android started its resize animation, adding a
              // needless transition on the hottest frame.
              return content;
            },
          ),
        ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.black,
      child: AppStatusView(type: AppStatusType.loading, title: "", subtitle: "", iconColor: Colors.white),
    );
  }

  Future<void> close() async {
    _sessionId++;
    // 关房时播放器会异步再发一次 playing=false，这里先标记"本会话已不再播放"，
    // 避免那一次迟到的事件把停摆看门狗起在已经关掉的房间上
    _playedInSession = false;
    _isClosing = true;
    _pinchResetTicker?.stop();
    _pinchResetTicker = null;
    pinchTransform.value = Matrix4.identity();
    await LiveAudioService.stop();
    SettingsService.to.player.useHardStopOnExit.v ? await hardDispose() : await softStop();
    _isClosing = false;
  }

  Future<void> softStop() async {
    lineManager.reset();
    try {
      if (_stateSubject.value == PlayerState.error) {
        await hardDispose();
        return;
      }
      await _currentPlayer?.softStop();
      _stateSubject.add(PlayerState.idle);
      _playingSubject.add(false);
    } catch (e) {
      await hardDispose();
    }
  }

  Future<void> hardDispose() async {
    lineManager.reset();
    _videoFrameSeen = false;
    _noVideoSwitches = 0;
    _stoppedSwitches = 0;
    _pausedIntentionally = false;
    _playedInSession = false;
    await _clearSubscriptions();
    if (_runtimeEngine != null) {
      await playerPool.removeFromCache(_runtimeEngine!);
    }
    _currentPlayer = null;
    _runtimeEngine = null;
    _runtimeAudioOnly = false;
    isInitialized.value = false;
  }

  Future<void> retry() async {
    await replay();
  }

  Future<void> _handleError(PlayerException error, {int? sessionId}) async {
    if (_disposed || _isClosing) return;
    if (_isHandlingError) {
      log("skip duplicated error handling: ${error.message}");
      return;
    }
    final mySessionId = sessionId ?? _sessionId;
    if (!_isSessionValid(mySessionId)) return;

    _isHandlingError = true;
    try {
      hasError.value = true;
      _stateSubject.add(PlayerState.error);

      // 解码失败也先换线路：同一清晰度下的多条线路编码/封装组合不同，
      // 首条可能视频轨解不出来（只剩声音），换一条即可恢复——这正是用户
      // 手动切线路能修好的原因。所以先自动换线，换线成功就不再弹提示。
      final failedUrl = _currentUrl;
      final switchableErrorType =
          error.type == PlayerErrorType.network ||
          error.type == PlayerErrorType.source ||
          error.type == PlayerErrorType.codec;

      bool lineSwitched = false;
      if (failedUrl != null && switchableErrorType && _currentPlayUrls.length > 1) {
        lineManager.markFailed(failedUrl);
        if (!lineManager.hasAvailable(_currentPlayUrls)) {
          log("no available lines, fallback engine");
        } else {
          final nextLine = lineManager.next(_currentPlayUrls);
          if (nextLine != failedUrl) {
            lineSwitched = true;
            log("switch line => $nextLine");
            // 解码失败是确定性的，不必像网络错误那样等 2 秒观察
            await Future.delayed(
              error.type == PlayerErrorType.codec
                  ? const Duration(milliseconds: 200)
                  : const Duration(seconds: 2),
            );
            if (!_isSessionValid(mySessionId)) return;
            await play(nextLine, _currentPlayUrls, _currentHeaders, room: currentFloatRoom);
            return;
          }
        }
      }

      // 换线路无法恢复时才上报错误，避免能自动恢复的场合白弹一次提示
      _errorSubject.add(error);
      log(error.type.toString());
      if (!lineSwitched && fallbackManager.shouldFallback(error)) {
        final nextEngine = await fallbackManager.fallback(_runtimeEngine!, error);
        if (nextEngine == _runtimeEngine) {
          log("skip fallback: nextEngine(${nextEngine.name}) == currentEngine(${_runtimeEngine?.name})");
          return;
        }
        log(
          "fallback engine: "
          "${_runtimeEngine?.name} -> ${nextEngine.name}",
        );
        _isSwitchingDueToFallback = true;
        await Future.delayed(const Duration(milliseconds: 1200));
        if (!_isSessionValid(mySessionId)) return;
        await switchEngine(nextEngine, isManual: false);
        await Future.delayed(const Duration(milliseconds: 500));
        if (!_isSessionValid(mySessionId)) return;
        await replay();
        return;
      }
    } catch (e, s) {
      log("_handleError failed: $e", stackTrace: s);
    } finally {
      _isHandlingError = false;
    }
  }

  Future<void> _bindPlayerStreams(UnifiedPlayer player) async {
    await _clearSubscriptions();
    _subscriptions.add(
      player.onPlaying.listen((event) async {
        _playingSubject.add(event);
        if (event) {
          hasError.value = false;
          _stateSubject.add(PlayerState.playing);
          // 恢复播放：撤销卡死看门狗并清零换线计数
          _disarmStallWatchdog();
          _stallSwitches = 0;
          // 恢复播放同样意味着"停摆"结束：撤销停摆看门狗
          _disarmStoppedWatchdog();
          _stoppedSwitches = 0;
          _pausedIntentionally = false;
          _playedInSession = true;
          if (_isSwitchingDueToFallback) {
            _isSwitchingDueToFallback = false;
          }
        } else {
          _stateSubject.add(PlayerState.paused);
          // 播放中突然停止：起停摆计时（主动暂停、关房等由下方守卫跳过）
          _armStoppedWatchdog(_sessionId);
        }
      }),
    );
    _subscriptions.add(
      player.onLoading.listen((event) {
        _loadingSubject.add(event);
        if (event && _stateSubject.value != PlayerState.buffering) {
          _stateSubject.add(PlayerState.buffering);
        }
        // 持续缓冲视为潜在卡死：起计时。
        // 注意：缓冲结束**不等于**恢复播放——实测 buffering 会在 1ms 内
        // true→false 闪一下而 playing 一直是 false，若此刻就撤销，12 秒计时
        // 根本跑不完（这正是 2026-10-10 卡死时看门狗没触发的原因）。
        // 只有真正回到 playing（onPlaying 分支）才撤销。
        if (event) {
          _armStallWatchdog(_sessionId);
        } else if (isPlayingNow) {
          _disarmStallWatchdog();
        }
      }),
    );
    _subscriptions.add(
      player.onComplete.listen((event) {
        log('[PauseTrace] onComplete -> $event session=$_sessionId');
        _completeSubject.add(event);
      }),
    );
    _subscriptions.add(
      player.onStateChanged.listen((event) {
        log('[PauseTrace] onStateChanged -> $event');
        _stateSubject.add(event);
      }),
    );
    _subscriptions.add(
      player.onError.listen((error) {
        log('[PauseTrace] onError -> ${error.message} type=${error.type}');
        if (!_isHandlingError) {
          unawaited(_handleError(error));
        }
      }),
    );
    _subscriptions.add(
      player.width.listen((event) {
        _widthSubject.add(event);
      }),
    );
    _subscriptions.add(
      player.height.listen((event) {
        _heightSubject.add(event);
      }),
    );
    _subscriptions.add(
      CombineLatestStream.combine2<int?, int?, bool>(
        width.where((w) => w != null && w > 0),
        height.where((h) => h != null && h > 0),
        (w, h) => h! >= w!,
      ).distinct().listen((event) {
        isVerticalVideo.value = event;
        // 收到有效宽高说明视频轨确实出画面了：撤掉看门狗并清零换线计数
        _onVideoFrameSeen();
      }),
    );
  }

  /// 视频轨已出画面：撤销"有声音没画面"看门狗。
  void _onVideoFrameSeen() {
    _videoFrameSeen = true;
    _noVideoSwitches = 0;
    _videoWatchdogTimer?.cancel();
    _videoWatchdogTimer = null;
  }

  /// 进入缓冲：起一个"卡死"计时。缓冲结束（恢复 playing）即撤销。
  /// 超时仍卡在 buffering → 按网络错误触发换线自愈。
  void _armStallWatchdog(int sessionId) {
    _stallWatchdogTimer?.cancel();
    log('[PauseTrace] stallWatchdog armed (${_stallWatchdogDelay.inSeconds}s) session=$sessionId');
    _stallWatchdogTimer = Timer(_stallWatchdogDelay, () {
      if (!_isSessionValid(sessionId)) return;
      if (isPlayingNow || !_loadingSubject.value) {
        // "画面冻住但没报 buffering" 时自愈不会触发，这里留下判据
        log('[PauseTrace] stallWatchdog fired but skipped:'
            ' playing=$isPlayingNow buffering=${_loadingSubject.value}');
        return;
      }
      if (_stallSwitches >= _maxStallSwitches) {
        log('stream stalled after $_maxStallSwitches line switches, report error');
        _stallSwitches = 0;
        unawaited(
          _handleError(
            PlayerException(message: 'stream stalled on all lines', type: PlayerErrorType.network),
            sessionId: sessionId,
          ),
        );
        return;
      }
      _stallSwitches++;
      log('stream stalled in buffering ${_stallWatchdogDelay.inSeconds}s, switch line (attempt $_stallSwitches)');
      unawaited(
        _handleError(
          PlayerException(message: 'stream stalled (buffering timeout)', type: PlayerErrorType.network),
          sessionId: sessionId,
        ),
      );
    });
  }

  void _disarmStallWatchdog() {
    if (_stallWatchdogTimer != null) {
      log('[PauseTrace] stallWatchdog disarmed');
    }
    _stallWatchdogTimer?.cancel();
    _stallWatchdogTimer = null;
  }

  /// "播放中停摆"看门狗（字段处有成因说明）：playing 变 false 且既没被业务
  /// 暂停、也不在缓冲时，起 N 秒计时；超时仍未恢复就按网络错误走既有换线。
  void _armStoppedWatchdog(int sessionId) {
    // 业务主动暂停、销毁/关房中、没有播放器实例 → 都不归停摆检测管
    if (_pausedIntentionally || _disposed || _isClosing || _currentPlayer == null) {
      return;
    }
    // 还没真正播放起来过（冷启动初始化也会先来一次 onPlaying=false）→ 不算停摆
    if (!_playedInSession) return;
    // 关房后 state 已回到 idle/stopped/error，不能在空闲态起自愈
    final state = _stateSubject.value;
    if (state == PlayerState.idle ||
        state == PlayerState.stopped ||
        state == PlayerState.error ||
        state == PlayerState.disposed) {
      return;
    }
    _stoppedWatchdogTimer?.cancel();
    log('[PauseTrace] stoppedWatchdog armed (${_stoppedWatchdogDelay.inSeconds}s) session=$sessionId'
        ' buffering=${_loadingSubject.value}');
    _stoppedWatchdogTimer = Timer(_stoppedWatchdogDelay, () {
      if (!_isSessionValid(sessionId)) return;
      // 只在前台自愈：切后台时 media_kit 的 Video 组件会自行暂停播放，
      // 后台换线既浪费流量也容易误判，交回给 lifecycle 恢复逻辑
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        log('[PauseTrace] stoppedWatchdog skipped: app lifecycle=${WidgetsBinding.instance.lifecycleState}');
        return;
      }
      if (isPlayingNow || _pausedIntentionally) return;
      if (_loadingSubject.value) return; // 仍在缓冲 → 归卡缓冲看门狗管
      if (_stoppedSwitches >= _maxStoppedSwitches) {
        log('[PauseTrace] playback stopped after $_maxStoppedSwitches switches, report error');
        _stoppedSwitches = 0;
        unawaited(
          _handleError(
            PlayerException(message: 'playback stopped on all lines', type: PlayerErrorType.network),
            sessionId: sessionId,
          ),
        );
        return;
      }
      _stoppedSwitches++;
      log('[PauseTrace] playback stopped ${_stoppedWatchdogDelay.inSeconds}s'
          ' with neither pause source nor buffering, switch line (attempt $_stoppedSwitches)');
      unawaited(
        _handleError(
          PlayerException(message: 'playback stopped (no buffering, no error)', type: PlayerErrorType.network),
          sessionId: sessionId,
        ),
      );
    });
  }

  void _disarmStoppedWatchdog() {
    if (_stoppedWatchdogTimer != null) {
      log('[PauseTrace] stoppedWatchdog disarmed');
    }
    _stoppedWatchdogTimer?.cancel();
    _stoppedWatchdogTimer = null;
  }

  /// 恢复播放兜底：直播流/播放器实例已死时 mpv 的 play() 会静默无效果，
  /// 用户视角就是"点了屏幕没任何反应"。这里恢复后给 1.2s 观察期——
  /// 仍未进入 playing 且不在缓冲（缓冲说明有进展）就按网络错误换线重连。
  Future<void> resumeWithWatchdog() async {
    if (_currentPlayer == null) return;
    final mySession = _sessionId;
    _pausedIntentionally = false;
    log('[PauseTrace] resumeWithWatchdog() session=$mySession playing=$isPlayingNow');
    await _currentPlayer!.play();
    await Future.delayed(const Duration(milliseconds: 1200));
    if (_disposed || _isClosing || !_isSessionValid(mySession)) return;
    if (isPlayingNow || _loadingSubject.value) return;
    log('resume had no effect, treat as dead stream and reconnect');
    unawaited(
      _handleError(
        PlayerException(message: 'resume had no effect (player stalled)', type: PlayerErrorType.network),
        sessionId: mySession,
      ),
    );
  }

  /// 开播后观察是否出画面；一直不出就按解码失败换下一条线路。
  void _armVideoWatchdog(int sessionId) {
    _videoWatchdogTimer?.cancel();
    _videoWatchdogTimer = null;
    // 纯音频模式本来就没有画面，不参与判断
    if (_runtimeAudioOnly || _videoFrameSeen) return;
    _videoWatchdogTimer = Timer(_videoFrameWatchdogDelay, () {
      if (!_isSessionValid(sessionId)) return;
      if (_videoFrameSeen) return;
      final w = _widthSubject.value ?? 0;
      final h = _heightSubject.value ?? 0;
      if (w > 0 && h > 0) {
        _videoFrameSeen = true;
        return;
      }
      // 还没播起来（网络卡住/缓冲）时交给既有的错误与重连逻辑处理
      if (!_playingSubject.value) {
        log('no video frame yet but not playing, skip watchdog');
        return;
      }
      if (_noVideoSwitches >= _maxNoVideoSwitches) {
        log('no video frames after $_maxNoVideoSwitches line switches, report error');
        unawaited(
          _handleError(
            PlayerException(message: 'no video frames on any line', type: PlayerErrorType.codec),
            sessionId: sessionId,
          ),
        );
        return;
      }
      _noVideoSwitches++;
      log('no video frames while playing, switch line (attempt $_noVideoSwitches)');
      unawaited(
        _handleError(
          PlayerException(message: 'no video frames while playing', type: PlayerErrorType.codec),
          sessionId: sessionId,
        ),
      );
    });
  }

  Future<void> _clearSubscriptions() async {
    _videoWatchdogTimer?.cancel();
    _videoWatchdogTimer = null;
    _disarmStallWatchdog();
    _disarmStoppedWatchdog();
    if (_subscriptions.isEmpty) return;
    for (final item in _subscriptions.toList()) {
      await item.cancel();
    }
    _subscriptions.clear();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _sessionId++;
    _isClosing = true;
    _hideTimer?.cancel();
    closeAppFloating();
    await _pipSubscription?.cancel();
    await _pipStateSubscription?.cancel();
    await _clearSubscriptions();
    await playerPool.disposeAll();
    await Future.wait([
      _stateSubject.close(),
      _playingSubject.close(),
      _loadingSubject.close(),
      _completeSubject.close(),
      _errorSubject.close(),
      _widthSubject.close(),
      _heightSubject.close(),
    ]);
  }
}
