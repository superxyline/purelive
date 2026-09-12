import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_svg/svg.dart';
import 'package:flutter/gestures.dart';
import 'package:remixicon/remixicon.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/plugins/event_bus.dart';
import 'package:flame_barrage/flame_barrage.dart';
import 'package:pure_live/common/consts/app_consts.dart';
import 'package:syncfusion_flutter_sliders/sliders.dart';
import 'package:pure_live/common/utils/live_url_tool.dart';
import 'package:pure_live/common/widgets/count_button.dart';
import 'package:pure_live/common/global/platform_utils.dart';
import 'package:pure_live/modules/live_play/states/load_type.dart';
import 'package:pure_live/modules/live_play/widgets/play_other.dart';
import 'package:pure_live/modules/live_play/controllers/player_state.dart';
import 'package:pure_live/modules/live_play/controllers/live_play_controller.dart';
import 'package:pure_live/player/core/player_manager.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/volume_control.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller.dart';
import 'package:pure_live/modules/live_play/widgets/danmaku_composer.dart';
import 'package:pure_live/modules/live_play/widgets/danmaku_list_view.dart';

class VideoControllerPanel extends StatefulWidget {
  final VideoController controller;

  const VideoControllerPanel({super.key, required this.controller});

  @override
  State<StatefulWidget> createState() => _VideoControllerPanelState();
}

class _VideoControllerPanelState extends State<VideoControllerPanel> {
  static const barHeight = 56.0;

  /// SC 卡片在左下角堆叠布局中预留的高度估计值（SC 卡片实际高度随内容变化）。
  static const double _scCardSpaceEstimate = 180.0;

  /// 全屏左下角卡片（SC / 礼物）的统一宽度。
  static double _fullscreenCardWidth(BuildContext context) =>
      (MediaQuery.of(context).size.width * 0.6).clamp(260.0, 360.0);

  Offset? _lastTapPosition;

  VideoController get controller => widget.controller;

  /// 当前焦点是否在真正的文本输入框上（弹幕输入条等）。
  ///
  /// 播放器面板根节点带 Focus(autofocus: true) 用于接收键盘快捷键，
  /// 它也会长期持有 primaryFocus，但不能据此吞掉普通点击。
  bool _isTextInputFocused() {
    final primaryFocus = FocusManager.instance.primaryFocus;
    if (primaryFocus == null || !primaryFocus.hasFocus || primaryFocus.context == null) {
      return false;
    }
    return primaryFocus.context!.widget is EditableText;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.enableController();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Focus(
        autofocus: true,
        child: Obx(() {
          final double currentVolume = controller.currentVolume.value;
          final int percentage = (currentVolume * 100).round();

          final IconData iconData = currentVolume <= 0
              ? Icons.volume_mute
              : currentVolume < 0.5
              ? Icons.volume_down
              : Icons.volume_up;

          return MouseRegion(
            onHover: (_) => controller.onMouseHoverPlayer(),
            onExit: (_) => controller.onMouseExitPlayer(),
            cursor: !controller.showController.value ? SystemMouseCursors.none : SystemMouseCursors.basic,
            child: Stack(
              children: [
                Container(
                  color: Colors.transparent,
                  alignment: Alignment.center,
                  child: AnimatedOpacity(
                    opacity: controller.showVolume.value ? 0.8 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: Card(
                      color: Colors.black,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(iconData, color: Colors.white),
                            Padding(
                              padding: const EdgeInsets.only(left: 8, right: 8),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(
                                  width: 100,
                                  height: 20,
                                  child: LinearProgressIndicator(
                                    value: currentVolume,
                                    backgroundColor: Colors.white38,
                                    valueColor: const AlwaysStoppedAnimation(Colors.white),
                                  ),
                                ),
                              ),
                            ),
                            Text(
                              "$percentage%",
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Obx(
                  () => Offstage(
                    offstage: controller.hideDanmaku.value,
                    child: DanmakuViewer(key: controller.danmuKey, controller: controller),
                  ),
                ),
                GestureDetector(
                  onTapDown: (details) => _lastTapPosition = details.globalPosition,
                  onTap: () {
                    // 仅当真正的弹幕输入框（EditableText）聚焦时，点击空白才收键盘；
                    // 播放器自身的 Focus(autofocus:true) 也会持有焦点，不能让它
                    // 吞掉普通点击（否则点空白不唤出控制条、点弹幕不弹菜单）。
                    if (_isTextInputFocused()) {
                      FocusManager.instance.primaryFocus?.unfocus();
                      return;
                    }
                    final position = _lastTapPosition;
                    if (position != null && controller.handleDanmakuPointer(position, longPress: false)) return;
                    GlobalPlayerService.instance.playerManager.isPlayingNow
                        ? controller.toggleController()
                        : GlobalPlayerService.instance.playerManager.togglePlayPause();
                  },
                  onLongPressStart: (details) {
                    controller.handleDanmakuPointer(details.globalPosition, longPress: true);
                  },
                  onDoubleTap: () {
                    if (!controller.showLocked.value) {
                      GlobalPlayerState.to.isWindowFullscreen.value
                          ? controller.toggleWindowFullScreen()
                          : controller.toggleFullScreen();
                    }
                  },
                  child: BrightnessVolumnDargArea(controller: controller),
                ),
                LockButton(controller: controller),
                TopActionBar(controller: controller, barHeight: barHeight),
                BottomActionBar(controller: controller, barHeight: barHeight),
                Obx(() {
                  final liveCtr = controller.livePlayController;
                  final sc = liveCtr.fsSC.value;
                  if (!GlobalPlayerState.to.fullscreenUI || sc == null) {
                    return const SizedBox.shrink();
                  }
                  final width = _fullscreenCardWidth(context);
                  return Positioned(
                    left: 16 + MediaQuery.of(context).padding.left,
                    bottom: (controller.showController.value && !controller.showLocked.value) ? barHeight + 16 : 24,
                    width: width,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: SuperChatCard(key: ValueKey(sc.id), sc: sc),
                    ),
                  );
                }),
                // 全屏礼物卡片堆叠显示（同屏最多3个）
                Obx(() {
                  final liveCtr = controller.livePlayController;
                  final gifts = liveCtr.fsGifts;
                  if (!GlobalPlayerState.to.fullscreenUI ||
                      gifts.isEmpty ||
                      !SettingsService.to.danmaku.showFullscreenGiftCard.v) {
                    return const SizedBox.shrink();
                  }
                  final width = _fullscreenCardWidth(context);
                  // 计算基础底部位置：SC卡片下方（如果有SC则在SC下方，否则在控制栏上方）
                  final sc = liveCtr.fsSC.value;
                  final double baseBottom;
                  if (controller.showController.value && !controller.showLocked.value) {
                    baseBottom = sc != null ? barHeight + _scCardSpaceEstimate : barHeight + 16;
                  } else {
                    baseBottom = sc != null ? _scCardSpaceEstimate : 24;
                  }
                  // 构建堆叠的礼物卡片列表
                  final List<Widget> giftCards = [];
                  for (int i = 0; i < gifts.length; i++) {
                    final gift = gifts[i];
                    // 每个卡片向上偏移（最新的在最下面）；
                    // AnimatedPositioned 让新卡片加入时旧卡片平滑上移。
                    final offset = (gifts.length - 1 - i) * LivePlayController.giftCardHeight;
                    giftCards.add(
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        left: 16 + MediaQuery.of(context).padding.left,
                        bottom: baseBottom + offset,
                        width: width,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          transitionBuilder: (Widget child, Animation<double> animation) {
                            return SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 1),
                                end: Offset.zero,
                              ).animate(CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOutCubic,
                              )),
                              // 隔离每张卡片的重绘：任一卡片进场/合并数量时
                              // 不再连带整层（含其它卡片）重新绘制，避免多卡
                              // 堆叠时拖累视频渲染。
                              child: RepaintBoundary(child: child),
                            );
                          },
                          child: GiftCard(
                            // 控制器保证 fsGifts 中的卡片均带 sentAt（缺失时已补当前时间）
                            key: ValueKey(gift.sentAt!.millisecondsSinceEpoch),
                            message: gift,
                            glassEffect: true,
                            onTap: () => onGiftCardTap(context, gift),
                          ),
                        ),
                      ),
                    );
                  }
                  return Stack(children: giftCards);
                }),
                // 双指缩放后的“还原画面”按钮（仅全屏且画面非原始比例时显示）
                ValueListenableBuilder<Matrix4>(
                  valueListenable: GlobalPlayerService.instance.playerManager.pinchTransform,
                  builder: (context, transform, _) => Obx(() {
                    // 与松手自动弹回的阈值保持一致：超过 1.02 倍即视为已缩放
                    final zoomed = transform.getMaxScaleOnAxis() > 1.02;
                    if (!GlobalPlayerState.to.fullscreenUI || !zoomed || controller.showLocked.value) {
                      return const SizedBox.shrink();
                    }
                    return Positioned(
                      top: barHeight + 20,
                      right: 16 + MediaQuery.of(context).padding.right,
                      child: AnimatedOpacity(
                        opacity: controller.showController.value ? 1.0 : 0.35,
                        duration: const Duration(milliseconds: 200),
                        child: Material(
                          color: Colors.black38,
                          shape: const CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => GlobalPlayerService.instance.playerManager.resetPinchZoom(),
                            child: const Padding(
                              padding: EdgeInsets.all(10),
                              child: Icon(Icons.close_fullscreen, color: Colors.white, size: 22),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class ErrorWidget extends StatelessWidget {
  const ErrorWidget({super.key, required this.controller});

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(i18n("play_video_failed"), style: AppTextStyles.t14.copyWith(color: Colors.white)),
          ),
          ElevatedButton(
            onPressed: () => controller.refresh(),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.2)),
            child: Text(i18n("retry"), style: AppTextStyles.t15.copyWith(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// Top action bar widgets
class TopActionBar extends StatelessWidget {
  const TopActionBar({super.key, required this.controller, required this.barHeight});

  final VideoController controller;
  final double barHeight;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => AnimatedPositioned(
        top: (controller.showController.value && !controller.showLocked.value) ? 0 : -barHeight,
        left: 0,
        right: 0,
        height: barHeight,
        duration: const Duration(milliseconds: 300),
        child: SafeArea(
          // 刘海屏适配：横屏沉浸时画面延伸进刘海/挖孔区，控制栏按钮避让挖孔
          child: Container(
            height: barHeight,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            // 渐变衬底仅全屏需要（标题文字压在画面上）；
            // 非全屏没有标题，整条黑45渐变横在明亮画面上像一条白雾长条，
            // 图标可读性由 LabeledIconAction 的文字/图标投影保证。
            decoration: GlobalPlayerState.to.fullscreenUI
                ? const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.transparent, Colors.black45],
                    ),
                  )
                : null,
          child: Row(
            children: [
              if (GlobalPlayerState.to.fullscreenUI) BackButton(controller: controller),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        controller.room.title!,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.t16.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      if (controller.room.currentProgramme != null && controller.room.currentProgramme!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          "${i18n('now_playing')}: ${controller.room.currentProgramme!}",
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              if (GlobalPlayerState.to.fullscreenUI) ...[
                IconButton(
                  icon: const Icon(Icons.swap_horiz_outlined),
                  tooltip: i18n('switch_live_room'),
                  color: Colors.white,
                  onPressed: () {
                    Get.dialog(PlayOther(controller: Get.find<LivePlayController>()));
                  },
                ),
                const DatetimeInfo(),
                BatteryInfo(controller: controller),
              ],
              TempMuteButton(controller: controller),
              AudioOnlyButton(controller: controller),
              if (PlatformUtils.isAndroid) CastButton(controller: controller),
              if (!GlobalPlayerState.to.fullscreenUI && PlatformUtils.isAndroid) PIPButton(controller: controller),
              if (PlatformUtils.isWindows) PIPButton(controller: controller),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

class DatetimeInfo extends StatefulWidget {
  const DatetimeInfo({super.key});

  @override
  State<DatetimeInfo> createState() => _DatetimeInfoState();
}

class _DatetimeInfoState extends State<DatetimeInfo> {
  DateTime dateTime = DateTime.now();
  Timer? refreshDateTimer;

  @override
  void initState() {
    super.initState();
    refreshDateTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      setState(() => dateTime = DateTime.now());
    });
  }

  @override
  void dispose() {
    super.dispose();
    refreshDateTimer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    // get system time and format
    var hour = dateTime.hour.toString();
    if (hour.length < 2) hour = '0$hour';
    var minute = dateTime.minute.toString();
    if (minute.length < 2) minute = '0$minute';

    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      child: Text(
        '$hour:$minute',
        style: const TextStyle(color: Colors.white, decoration: TextDecoration.none),
      ),
    );
  }
}

class BatteryInfo extends StatefulWidget {
  const BatteryInfo({super.key, required this.controller});

  final VideoController controller;

  @override
  State<BatteryInfo> createState() => _BatteryInfoState();
}

class _BatteryInfoState extends State<BatteryInfo> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      child: Container(
        width: 35,
        height: 15,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.4),
          border: Border.all(color: Colors.white),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Obx(
            () => Text(
              '${widget.controller.batteryLevel.value}',
              style: const TextStyle(color: Colors.white, fontSize: 9, decoration: TextDecoration.none),
            ),
          ),
        ),
      ),
    );
  }
}

class BackButton extends StatelessWidget {
  const BackButton({super.key, required this.controller});

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => GlobalPlayerState.to.isWindowFullscreen.value
          ? controller.toggleWindowFullScreen()
          : controller.toggleFullScreen(),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.all(12),
        child: const Icon(Icons.arrow_back_rounded, color: Colors.white),
      ),
    );
  }
}

class PIPButton extends StatelessWidget {
  const PIPButton({super.key, required this.controller});

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return LabeledIconAction(
      icon: CustomIcons.float_window,
      label: i18n('bar_pip'),
      onPressed: () {
        GlobalPlayerService.instance.playerManager.enablePip();
      },
    );
  }
}

// Center widgets
class DanmakuViewer extends StatelessWidget {
  const DanmakuViewer({super.key, required this.controller});

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final settings = SettingsService.to.danmaku;
      return FlameBarrageWidget(
        controller: controller.danmakuController,
        // Video gestures own the full surface and forward only hits on actual
        // barrage bounds, so volume/brightness/double-tap remain responsive.
        enablePointerEvents: false,
        config: BarrageConfig(
          fontSize: controller.danmakuFontSize.value,
          topAreaDistance: controller.danmakuTopArea.value,
          area: controller.danmakuArea.value,
          bottomAreaDistance: controller.danmakuBottomArea.value,
          baseSpeed: controller.danmakuSpeed.value,
          opacity: controller.danmakuOpacity.value,
          fontWeight: FontWeight(controller.danmakuFontWeight.value),
          strokeWidth: controller.danmakuFontBorder.value,
          showStroke: controller.enableDanmakuStroke.value,
          noEmojiMode: controller.noEmojiMode.value,
          fps: settings.resolvedDanmakuFps(),
          maxPendingCount: 120,
          maxPendingAge: const Duration(seconds: 5),
          fontFamily: controller.danmakuFontFamilyName.value,
          trackHeight: (controller.danmakuFontSize.value * 1.55).clamp(24.0, 64.0).toDouble(),
          emojiSize: (controller.danmakuFontSize.value * 1.3).clamp(16.0, 48.0).toDouble(),
          pictureCacheMaxSize: 600,
          barragePoolMaxSize: 1000,
        ),
        emojiAtlas: EmojiAtlas.instance,
      );
    });
  }
}

class BrightnessVolumnDargArea extends StatefulWidget {
  const BrightnessVolumnDargArea({super.key, required this.controller});

  final VideoController controller;

  @override
  State<BrightnessVolumnDargArea> createState() => BrightnessVolumnDargAreaState();
}

class BrightnessVolumnDargAreaState extends State<BrightnessVolumnDargArea> {
  VideoController get controller => widget.controller;

  Timer? _hideBVTimer;
  bool _hideBVStuff = true;
  bool _isDargLeft = true;
  double _updateDargVarVal = 1.0;

  // ---- 全屏双指缩放画面（B站客户端效果）----
  /// 双指手势进行中（从第二指按下到全部抬起；期间剩余单指继续平移画面）
  bool _pinchActive = false;
  /// 上一帧手势的累计缩放值（用于计算本帧的缩放增量）
  double _lastGestureScale = 1.0;
  static const double _minPinchScale = 1.0;
  static const double _maxPinchScale = 4.0;

  PlayerManager get _playerManager => GlobalPlayerService.instance.playerManager;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _hideBVTimer?.cancel();
    super.dispose();
  }

  void updateVolumn(double? volume) {
    _isDargLeft = false;
    _cancelAndRestartHideBVTimer();
    setState(() {
      _updateDargVarVal = volume!;
    });
  }

  void _cancelAndRestartHideBVTimer() {
    _hideBVTimer?.cancel();
    _hideBVTimer = Timer(const Duration(seconds: 1), () {
      setState(() => _hideBVStuff = true);
    });
    setState(() => _hideBVStuff = false);
  }

  void _onVerticalDragUpdate(Offset position, Offset delta) async {
    if (controller.showLocked.value) return;

    if (delta.distance < 0.5) return;

    // 用手势区域自身尺寸划分左右半区：非全屏时该区域只是视频窗口，
    // 比整屏小，用 MediaQuery 的屏幕尺寸会把右半区误判成左侧。
    final size = MediaQuery.of(context).size;
    final RenderObject? renderObject = context.findRenderObject();
    final boxSize = renderObject is RenderBox && renderObject.hasSize ? renderObject.size : size;
    final width = boxSize.width;
    final height = boxSize.height;

    final dargLeft = (position.dx > (width / 2)) ? false : true;

    if (Platform.isWindows && dargLeft) return;

    if (_hideBVStuff || _isDargLeft != dargLeft) {
      _isDargLeft = dargLeft;
      if (_isDargLeft) {
        if (PlatformUtils.isMobile) {
          double v = await controller.brightness();
          setState(() => _updateDargVarVal = v);
        }
      } else {
        double? v = await controller.volume();
        setState(() => _updateDargVarVal = v ?? 1.0);
      }
    }

    _cancelAndRestartHideBVTimer();

    double sensitivity = 0.25;
    double deltaValue = -(delta.dy / (height / 2)) * sensitivity;

    double dragRange = _updateDargVarVal + deltaValue;

    dragRange = dragRange.clamp(0.0, 1.0);

    if ((dragRange - _updateDargVarVal).abs() > 0.001) {
      if (_isDargLeft) {
        controller.setBrightness(dragRange);
      } else {
        controller.setVolume(dragRange);
      }
      setState(() => _updateDargVarVal = dragRange);
    }
  }

  /// 双指缩放/平移（增量式，每帧在当前变换上叠加）：
  /// 1. 焦点位移 [ScaleUpdateDetails.focalPointDelta] —— 双指（或激活后剩余单指）
  ///    滑动时拖动画面位置；
  /// 2. 围绕当前焦点的缩放增量 —— 捏合放大/缩小。
  /// 缩放范围 [_minPinchScale, _maxPinchScale]，平移按放大后的画面边界裁剪。
  void _updatePinchTransform(ScaleUpdateDetails details) {
    final current = _playerManager.pinchTransform.value;
    final currentScale = current.getMaxScaleOnAxis();

    // 本帧目标缩放（钳制到允许范围），换算成本帧缩放增量
    final targetScale = (currentScale * details.scale / _lastGestureScale)
        .clamp(_minPinchScale, _maxPinchScale);
    _lastGestureScale = details.scale;
    if (targetScale <= _minPinchScale) {
      _playerManager.pinchTransform.value = Matrix4.identity();
      return;
    }
    final scaleStep = targetScale / currentScale;

    final focal = details.localFocalPoint;
    // 1. 平移：焦点位移
    Matrix4 next = current.clone()
      ..translateByDouble(details.focalPointDelta.dx, details.focalPointDelta.dy, 0, 1);
    // 2. 缩放：围绕当前焦点
    next = Matrix4.identity()
      ..translateByDouble(focal.dx, focal.dy, 0, 1)
      ..scaleByDouble(scaleStep, scaleStep, 1, 1)
      ..translateByDouble(-focal.dx, -focal.dy, 0, 1)
      ..multiply(next);
    next = _clampPinchPan(next, targetScale, MediaQuery.of(context).size);
    _playerManager.pinchTransform.value = next;
  }

  /// 把平移量限制在放大后的画面范围内，避免画面被拖离屏幕。
  Matrix4 _clampPinchPan(Matrix4 matrix, double scale, Size areaSize) {
    if (scale <= _minPinchScale) return Matrix4.identity();
    final minOffset = Offset(areaSize.width - areaSize.width * scale, areaSize.height - areaSize.height * scale);
    final translation = matrix.getTranslation();
    return matrix.clone()
      ..setTranslationRaw(
        translation.x.clamp(minOffset.dx, 0.0),
        translation.y.clamp(minOffset.dy, 0.0),
        0,
      );
  }

  /// 双指全部抬起：缩放回落到接近 1 倍时自动还原画面。
  void _onPinchEnd() {
    _pinchActive = false;
    _lastGestureScale = 1.0;
    final scale = _playerManager.pinchTransform.value.getMaxScaleOnAxis();
    if (scale <= _minPinchScale + 0.05) {
      _playerManager.resetPinchZoom();
    }
  }

  /// 双指手势入口：仅在移动端全屏时启用缩放。
  void _onScaleStart(ScaleStartDetails details) {
    if (!PlatformUtils.isMobile || controller.showLocked.value) return;
    if (!GlobalPlayerState.to.fullscreenUI) return;
    if (details.pointerCount >= 2) {
      _activatePinch();
    }
  }

  /// 激活缩放状态，手势累计缩放从 1 开始。
  void _activatePinch() {
    if (_pinchActive) return;
    _pinchActive = true;
    _lastGestureScale = 1.0;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (!PlatformUtils.isMobile || controller.showLocked.value) return;
    if (details.pointerCount >= 2) {
      // 双指缩放仅在全屏启用；注意全屏判断必须放在双指分支内，
      // 否则会连带拦截非全屏的单指亮度/音量拖动。
      if (!GlobalPlayerState.to.fullscreenUI) return;
      // 双指（及以上）：激活缩放。不依赖 onScaleStart——不同框架版本对
      // "指针数量变化是否重发 onScaleStart"行为不一致，在 update 里兜底。
      _activatePinch();
      _updatePinchTransform(details);
      return;
    }
    if (!_pinchActive) {
      // 单指垂直拖动：左侧亮度 / 右侧音量（原有行为）
      _onVerticalDragUpdate(details.localFocalPoint, details.focalPointDelta);
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_pinchActive) {
      _onPinchEnd();
    }
  }

  @override
  Widget build(BuildContext context) {
    IconData iconData;
    if (_isDargLeft) {
      iconData = _updateDargVarVal <= 0
          ? Icons.brightness_low
          : _updateDargVarVal < 0.5
          ? Icons.brightness_medium
          : Icons.brightness_high;
    } else {
      iconData = _updateDargVarVal <= 0
          ? Icons.volume_mute
          : _updateDargVarVal < 0.5
          ? Icons.volume_down
          : Icons.volume_up;
    }

    final int percentage = (_updateDargVarVal * 100).round();

    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          _onVerticalDragUpdate(event.localPosition, event.scrollDelta);
        }
      },
      child: GestureDetector(
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        child: Container(
          color: Colors.transparent,
          alignment: Alignment.center,
          child: AnimatedOpacity(
            opacity: !_hideBVStuff ? 0.8 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: Card(
              color: Colors.black,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(iconData, color: Colors.white),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 100,
                          height: 20,
                          child: LinearProgressIndicator(
                            value: _updateDargVarVal,
                            backgroundColor: Colors.white38,
                            valueColor: const AlwaysStoppedAnimation(Colors.white),
                          ),
                        ),
                      ),
                    ),
                    Text(
                      "$percentage%",
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LockButton extends StatelessWidget {
  const LockButton({super.key, required this.controller});

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => AnimatedOpacity(
        opacity: (GlobalPlayerState.to.fullscreenUI && controller.showController.value) ? 0.9 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: Align(
          alignment: Alignment.centerRight,
          child: AbsorbPointer(
            absorbing: !controller.showController.value,
            child: Container(
              margin: const EdgeInsets.only(right: 20.0),
              child: IconButton(
                onPressed: () => {controller.showLocked.toggle()},
                icon: Icon(controller.showLocked.value ? Icons.lock_rounded : Icons.lock_open_rounded, size: 28),
                color: Colors.white,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black38,
                  shape: const StadiumBorder(),
                  minimumSize: const Size(50, 50),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LineSelectorButton extends StatelessWidget {
  const LineSelectorButton({super.key, required this.controller});

  final VideoController controller;

  void _showMobileDialog(BuildContext context) {
    controller.isMenuOpen.value = true;
    controller.stopHideController();

    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16.0),
        clipBehavior: Clip.hardEdge,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 300),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 10, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(i18n("select_line"), style: Theme.of(context).textTheme.titleMedium),
                    IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => Navigator.of(context).pop()),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Obx(
                  () => ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    itemCount: controller.livePlayController.state.value.player.playUrls.length,
                    itemBuilder: (context, index) {
                      final isSelected = index == controller.livePlayController.state.value.player.currentLineIndex;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6.0),
                        child: Center(
                          child: InkWell(
                            onTap: () {
                              controller.livePlayController.setResolution(
                                ReloadDataType.changeLine,
                                controller.livePlayController.state.value.player.currentQuality,
                                index,
                              );
                              Navigator.of(context).pop();
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Container(
                                width: double.infinity, // 璁惧畾鎸夐挳鍥哄畾瀹藉害
                                height: 38, // 璁惧畾鎸夐挳楂樺害
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Get.theme.colorScheme.primary
                                      : Get.theme.colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  i18n("toolbox_line", args: {"index": (index + 1).toString()}),
                                  style: AppTextStyles.t15.copyWith(color: isSelected ? Colors.white : null),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(i18n('cancel')))],
                ),
              ),
            ],
          ),
        ),
      ),
    ).then((_) {
      controller.isMenuOpen.value = false;
      controller.enableController();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.livePlayController.state.value.player.playUrls.isEmpty) return const SizedBox.shrink();
      final bool isMobile =
          Theme.of(context).platform == TargetPlatform.android || Theme.of(context).platform == TargetPlatform.iOS;

      if (isMobile) {
        return GestureDetector(onTap: () => _showMobileDialog(context), child: _buildButtonChild());
      }

      const double itemHeight = 40.0;
      final double totalMenuHeight =
          (controller.livePlayController.state.value.player.playUrls.length * itemHeight) + 32;
      return PopupMenuButton<int>(
        position: PopupMenuPosition.over,
        offset: Offset(30, -totalMenuHeight),
        constraints: const BoxConstraints(minWidth: 110, maxWidth: 110),
        onOpened: () {
          controller.isMenuOpen.value = true;
          controller.stopHideController();
        },
        onSelected: (index) {
          controller.isMenuOpen.value = false;
          controller.livePlayController.setResolution(
            ReloadDataType.changeLine,
            controller.livePlayController.state.value.player.currentQuality,
            index,
          );
          controller.enableController();
        },
        onCanceled: () {
          controller.isMenuOpen.value = false;
          controller.enableController();
        },
        color: Colors.black.withValues(alpha: 0.85),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Colors.white10),
        ),
        child: _buildButtonChild(),
        itemBuilder: (context) =>
            List.generate(controller.livePlayController.state.value.player.playUrls.length, (index) {
              final isSelected = index == controller.livePlayController.state.value.player.currentLineIndex;
              return PopupMenuItem(
                value: index,
                height: itemHeight,
                child: Center(
                  child: Text(
                    i18n("toolbox_line", args: {"index": (index + 1).toString()}),
                    style: AppTextStyles.t13.copyWith(color: isSelected ? Get.theme.colorScheme.primary : Colors.white),
                  ),
                ),
              );
            }),
      );
    });
  }

  Widget _buildButtonChild() {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
      child: Text(
        i18n(
          "toolbox_line",
          args: {"index": (controller.livePlayController.state.value.player.currentLineIndex + 1).toString()},
        ),
        style: AppTextStyles.t13.copyWith(color: Colors.white),
      ),
    );
  }
}

class ResolutionSelectorButton extends StatelessWidget {
  const ResolutionSelectorButton({super.key, required this.controller});

  final VideoController controller;

  void _showMobileDialog(BuildContext context) {
    controller.isMenuOpen.value = true;
    controller.stopHideController();

    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16.0),
        clipBehavior: Clip.hardEdge,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 10, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(i18n("select_quality"), style: Theme.of(context).textTheme.titleMedium),
                    IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => Navigator.of(context).pop()),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Obx(
                  () => ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    itemCount: controller.livePlayController.state.value.player.qualites.length,
                    itemBuilder: (context, index) {
                      final isSelected = index == controller.livePlayController.state.value.player.currentQuality;
                      final qualityName = controller.livePlayController.state.value.player.qualites[index].quality;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6.0),
                        child: Center(
                          child: InkWell(
                            onTap: () {
                              controller.livePlayController.setResolution(
                                ReloadDataType.changeQuality,
                                index,
                                controller.livePlayController.state.value.player.currentLineIndex,
                              );
                              Navigator.of(context).pop();
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Container(
                                width: double.infinity, // 鐙崰涓€琛屽搴?                                height: 38,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Get.theme.colorScheme.primary
                                      : Get.theme.colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  qualityName,
                                  style: AppTextStyles.t15.copyWith(color: isSelected ? Colors.white : null),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(i18n('cancel')))],
                ),
              ),
            ],
          ),
        ),
      ),
    ).then((_) {
      controller.isMenuOpen.value = false;
      controller.enableController();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.livePlayController.state.value.player.qualites.isEmpty) return const SizedBox.shrink();

      final bool isMobile =
          Theme.of(context).platform == TargetPlatform.android || Theme.of(context).platform == TargetPlatform.iOS;

      if (isMobile) {
        return GestureDetector(onTap: () => _showMobileDialog(context), child: _buildButtonChild());
      }

      // Windows 桌面端样式
      final qualityCount = controller.livePlayController.state.value.player.qualites.length;
      const double itemHeight = 40.0;
      final double totalMenuHeight = (qualityCount * itemHeight) + 32;

      return PopupMenuButton<int>(
        tooltip: i18n('toolbox_select_quality'),
        position: PopupMenuPosition.over,
        offset: Offset(15, -totalMenuHeight),
        padding: EdgeInsets.zero,
        onOpened: () {
          controller.isMenuOpen.value = true;
          controller.stopHideController();
        },
        onCanceled: () {
          controller.isMenuOpen.value = false;
          controller.enableController();
        },
        onSelected: (index) {
          controller.isMenuOpen.value = false;
          controller.livePlayController.setResolution(
            ReloadDataType.changeQuality,
            index,
            controller.livePlayController.state.value.player.currentLineIndex,
          );
          controller.enableController();
        },
        color: Colors.black.withValues(alpha: 0.85),

        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Colors.white10),
        ),
        child: _buildButtonChild(),
        itemBuilder: (context) => List.generate(qualityCount, (index) {
          final isSelected = index == controller.livePlayController.state.value.player.currentQuality;
          return PopupMenuItem(
            value: index,
            height: itemHeight,
            child: Center(
              child: Text(
                controller.livePlayController.state.value.player.qualites[index].quality,
                style: AppTextStyles.t13.copyWith(color: isSelected ? Get.theme.colorScheme.primary : Colors.white),
              ),
            ),
          );
        }),
      );
    });
  }

  Widget _buildButtonChild() {
    final currentIndex = controller.livePlayController.state.value.player.currentQuality;
    final qualityName = controller.livePlayController.state.value.player.qualites[currentIndex].quality;
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
      child: Text(qualityName, style: AppTextStyles.t13.copyWith(color: Colors.white)),
    );
  }
}

// Bottom action bar widgets
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({super.key, required this.controller, required this.barHeight});

  final VideoController controller;
  final double barHeight;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      bool shouldShow =
          (controller.showController.value || controller.isMenuOpen.value) && !controller.showLocked.value;
      return AnimatedPositioned(
        bottom: shouldShow ? 0 : -barHeight,
        left: 0,
        right: 0,
        height: barHeight,
        duration: const Duration(milliseconds: 300),
        child: SafeArea(
          // 刘海屏适配：横屏沉浸时画面延伸进刘海/挖孔区，控制栏按钮避让挖孔
          child: Container(
          height: barHeight,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black45],
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const PureLiveScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        // 左侧组
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PlayPauseButton(controller: controller),
                            RefreshButton(controller: controller),
                            FavoriteButton(controller: controller),
                            if (SettingsService.to.danmaku.enableDanmakuDisplay.v) ...[
                              DanmakuButton(controller: controller),
                              SettingsButton(controller: controller),
                            ],
                            GiftCardButton(controller: controller),
                          ],
                        ),

                        // 全屏时在正下方控制条嵌入弹幕输入条（与弹幕开关同一水平线），
                        // 输入聚焦期间保持控制条常显，失焦后 4 秒自动隐藏。
                        if (GlobalPlayerState.to.fullscreenUI &&
                            (controller.livePlayController.localInteractionController.enabled.v ||
                                (controller.livePlayController.site == Sites.bilibiliSite &&
                                    SettingsService.to.cookieManager.bilibiliCookie.v.trim().isNotEmpty)))
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: DanmakuComposer(
                              controller: controller.livePlayController,
                              videoController: controller,
                              dark: true,
                            ),
                          ),

                        Obx(
                          () => Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (GlobalPlayerState.to.isWindowFullscreen.value ||
                                  GlobalPlayerState.to.isFullscreen.value) ...[
                                if (!GlobalPlayerService.instance.playerManager.isVerticalVideo.value)
                                  ResolutionSelectorButton(controller: controller),
                                if (!GlobalPlayerService.instance.playerManager.isVerticalVideo.value)
                                  LineSelectorButton(controller: controller),
                              ],
                              VideoFitSetting(controller: controller),
                              if (Platform.isWindows) OverlayVolumeControl(controller: controller),
                              if (Platform.isWindows)
                                Obx(() {
                                  return Row(
                                    children: [
                                      if (controller.supportWindowFull && !GlobalPlayerState.to.isFullscreen.value) ...[
                                        ExpandWindowButton(controller: controller),
                                      ],
                                    ],
                                  );
                                }),
                              if (!GlobalPlayerState.to.isWindowFullscreen.value) ExpandButton(controller: controller),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        ),
      );
    });
  }
}

class PlayPauseButton extends StatelessWidget {
  const PlayPauseButton({super.key, required this.controller});

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    final playerManager = GlobalPlayerService.instance.playerManager;

    return GestureDetector(
      onTap: () => playerManager.togglePlayPause(),
      child: StreamBuilder<bool>(
        stream: playerManager.onPlaying.distinct(),
        initialData: playerManager.isPlayingNow,
        builder: (context, snapshot) {
          final isPlaying = snapshot.data ?? playerManager.isPlayingNow;
          return Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.only(right: 6),
            child: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 28),
          );
        },
      ),
    );
  }
}

class RefreshButton extends StatelessWidget {
  const RefreshButton({super.key, required this.controller});

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => controller.refresh(),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.only(right: 6),
        child: const Icon(Icons.refresh_rounded, color: Colors.white),
      ),
    );
  }
}

class DanmakuButton extends StatelessWidget {
  const DanmakuButton({super.key, required this.controller});

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => controller.hideDanmaku.toggle(),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.only(right: 6, left: 6),
        child: Obx(
          () => controller.hideDanmaku.value
              ? SvgPicture.asset(
                  'assets/images/video/danmu_close.svg',
                  // ignore: deprecated_member_use
                  color: Colors.white,
                )
              : SvgPicture.asset(
                  'assets/images/video/danmu_open.svg',
                  // ignore: deprecated_member_use
                  color: Colors.white,
                ),
        ),
      ),
    );
  }
}

class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key, required this.controller});

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Get.dialog(SettingsPanel(controller: controller));
      },
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.only(right: 6, left: 6),
        child: SvgPicture.asset(
          'assets/images/video/danmu_setting.svg',
          // ignore: deprecated_member_use
          color: Colors.white,
        ),
      ),
    );
  }
}

/// 全屏礼物卡片快捷开关：切换后立即生效——关闭时清空当前已显示的卡片，
/// 打开时后续礼物按正常时序弹出（与弹幕设置页的全屏礼物卡片开关同一数据源）。
class GiftCardButton extends StatelessWidget {
  const GiftCardButton({super.key, required this.controller});

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        final settings = SettingsService.to.danmaku;
        settings.showFullscreenGiftCard.v = !settings.showFullscreenGiftCard.v;
        if (!settings.showFullscreenGiftCard.v) {
          controller.livePlayController.hideFullscreenGift();
        }
      },
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.only(right: 6, left: 6),
        child: Obx(
          () => Icon(
            SettingsService.to.danmaku.showFullscreenGiftCard.v ? Remix.gift_fill : Remix.gift_line,
            color: Colors.white,
            size: 21,
          ),
        ),
      ),
    );
  }
}

class ExpandWindowButton extends StatelessWidget {
  const ExpandWindowButton({super.key, required this.controller});

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => controller.toggleWindowFullScreen(),
      child: Container(
        alignment: Alignment.center,
        child: RotatedBox(
          quarterTurns: 1,
          child: Obx(
            () => Icon(
              GlobalPlayerState.to.isWindowFullscreen.value ? Icons.unfold_less_rounded : Icons.unfold_more_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
        ),
      ),
    );
  }
}

class ExpandButton extends StatelessWidget {
  const ExpandButton({super.key, required this.controller});

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => controller.toggleFullScreen(),
      child: Container(
        alignment: Alignment.center,
        child: Obx(
          () => Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Icon(
              GlobalPlayerState.to.isFullscreen.value ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
        ),
      ),
    );
  }
}

/// 右上角一键静音：仅静音播放器（内核音量置 0），不影响系统媒体音量。
/// 再次点击、滑动调音量、音量键、退出直播间均会恢复声音。
class TempMuteButton extends StatelessWidget {
  const TempMuteButton({super.key, required this.controller});

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => LabeledIconAction(
        icon: controller.tempMuted.value ? Icons.volume_off_rounded : Icons.volume_up_rounded,
        color: controller.tempMuted.value ? const Color(0xFFFFD166) : Colors.white,
        label: i18n('bar_mute'),
        onPressed: () {
          controller.enableController();
          controller.toggleTempMute();
        },
      ),
    );
  }
}

/// 图标下方带常显小字标签的控制条按钮。触屏设备没有 hover tooltip，
/// 静音/音频/投屏/小窗这类图标语义模糊，常显标签比长按提示更直接。
class LabeledIconAction extends StatelessWidget {
  const LabeledIconAction({
    super.key,
    required this.icon,
    required this.label,
    this.color = Colors.white,
    this.iconSize = 21,
    this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final double iconSize;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    // 无渐变衬底时（非全屏）图标/文字压在任意亮度的画面上，
    // 用轻投影保证可读性。
    final shadows = [Shadow(color: Colors.black.withValues(alpha: 0.55), blurRadius: 4)];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: iconSize, shadows: shadows),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 9,
                height: 1.0,
                decoration: TextDecoration.none,
                fontWeight: FontWeight.w500,
                shadows: shadows,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AudioOnlyButton extends StatelessWidget {
  const AudioOnlyButton({super.key, required this.controller});

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => LabeledIconAction(
        icon: controller.isAudioOnly ? Remix.headphone_fill : Remix.headphone_line,
        color: controller.isAudioOnly ? const Color(0xFFFFD166) : Colors.white,
        label: i18n('bar_audio'),
        onPressed: () {
          controller.enableController();
          controller.toggleAudioOnly();
        },
      ),
    );
  }
}

class CastButton extends StatelessWidget {
  const CastButton({super.key, required this.controller});

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return LabeledIconAction(
      icon: Remix.tv_2_line,
      label: i18n('bar_cast'),
      onPressed: () {
        controller.enableController();
        LiveUrlTool.castPlayUrlByRoomId(roomId: controller.room.roomId ?? '', platform: controller.room.platform ?? '');
      },
    );
  }
}

class FavoriteButton extends StatefulWidget {
  const FavoriteButton({super.key, required this.controller});

  final VideoController controller;

  @override
  State<FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<FavoriteButton> {
  StreamSubscription<dynamic>? subscription;
  late bool isFavorite = SettingsService.to.fav.isFavorite(widget.controller.room);

  @override
  void initState() {
    super.initState();
    listenFavorite();
  }

  void listenFavorite() {
    subscription = EventBus.instance.listen('changeFavorite', (data) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        widget.controller.enableController();
        if (isFavorite) {
          SettingsService.to.fav.removeRoom(widget.controller.room);
        } else {
          SettingsService.to.fav.addRoom(widget.controller.room);
        }
        setState(() => isFavorite = !isFavorite);
        EventBus.instance.emit('changeFavorite', true);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 0, horizontal: 6),
        alignment: Alignment.center,
        height: 25,
        child: Icon(
          isFavorite ? Icons.favorite : Icons.favorite_border,
          color: isFavorite ? const Color(0xFFFF5B7F) : Colors.white,
          size: 20,
        ),
      ),
    );
  }
}

// Settings panel widgets

class VideoFitSetting extends StatefulWidget {
  const VideoFitSetting({super.key, required this.controller});
  final VideoController controller;
  @override
  State<VideoFitSetting> createState() => _VideoFitSettingState();
}

class _VideoFitSettingState extends State<VideoFitSetting> {
  VideoController get controller => widget.controller;
  @override
  Widget build(BuildContext context) {
    final descs = AppConsts().videoFitType.map((e) => i18n(e['desc'])).toList();
    final attrs = AppConsts().videoFitList;
    final player = SettingsService.to.player;

    return GestureDetector(
      onTap: () {
        controller.enableController();
        int currentIndex = player.videoFitIndex.v + 1;
        if (currentIndex >= attrs.length) {
          currentIndex = 0;
        }
        player.videoFitIndex.v = currentIndex;
        controller.setVideoFit(currentIndex);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 0, horizontal: 2),
        alignment: Alignment.center,
        height: 25,
        child: Obx(() => Text(descs[player.videoFitIndex.v], style: AppTextStyles.t15.copyWith(color: Colors.white))),
      ),
    );
  }
}

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({super.key, required this.controller});

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxWidth = constraints.maxWidth;
        final double targetWidth = maxWidth > 600.0 ? 520.0 : maxWidth * 0.88;

        return AlertDialog(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.black54,
          elevation: 24.0,
          insetPadding: EdgeInsets.symmetric(horizontal: maxWidth > 600.0 ? 40.0 : 16.0, vertical: 24.0),
          contentPadding: EdgeInsets.zero,
          content: Container(
            width: targetWidth,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E).withValues(alpha: 0.98),
              borderRadius: BorderRadius.circular(16.0),
              border: Border.all(color: Colors.white10, width: 0.8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20.0, 18.0, 20.0, 14.0),
                  child: Row(
                    children: [
                      Container(
                        width: 3.5,
                        height: 16.0,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(2.0),
                        ),
                      ),
                      const SizedBox(width: 10.0),
                      Text(i18n("settings_danmaku_title"), style: AppTextStyles.t16Bold.copyWith(color: Colors.white)),
                    ],
                  ),
                ),
                const Divider(color: Colors.white10, height: 1.0, thickness: 0.8),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                    children: [DanmakuSetting(controller: controller, isWide: maxWidth > 600.0)],
                  ),
                ),
                const Divider(color: Colors.white10, height: 1.0, thickness: 0.8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.black,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(i18n("close"), style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class DanmakuSetting extends StatelessWidget {
  const DanmakuSetting({super.key, required this.controller, required this.isWide});

  final VideoController controller;
  final bool isWide;

  Widget _buildRowContainer({required String labelText, required Widget valueWidget, Widget? trailingWidget}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: isWide ? 10.0 : 6.0),
      child: Row(
        children: [
          SizedBox(
            width: isWide ? 110.0 : 85.0,
            child: Text(
              labelText,
              style: TextStyle(color: Colors.white70, fontSize: isWide ? 14.0 : 13.0, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: SizedBox(
              height: isWide ? 44.0 : 38.0,
              child: Align(alignment: Alignment.center, child: valueWidget),
            ),
          ),
          if (trailingWidget != null) ...[
            const SizedBox(width: 10.0),
            SizedBox(
              width: 65.0,
              child: Align(alignment: Alignment.centerRight, child: trailingWidget),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    final TextStyle digitStyle = TextStyle(
      color: Colors.white,
      fontSize: isWide ? 15.0 : 13.0,
      fontWeight: FontWeight.w600,

      fontFeatures: const [ui.FontFeature.tabularFigures()],
    );

    return Obx(
      () => SizedBox(
        height: isWide ? 350.0 : 280.0,
        child: SingleChildScrollView(
          physics: const PureLiveScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildRowContainer(
                labelText: i18n('display_area'),
                valueWidget: SfSlider(
                  min: 0.0,
                  max: 1.0,
                  value: controller.danmakuArea.value,
                  activeColor: primaryColor,
                  inactiveColor: Colors.white12,
                  onChanged: (dynamic val) => controller.danmakuArea.value = val as double,
                ),
                trailingWidget: Text('${(controller.danmakuArea.value * 100).toInt()}%', style: digitStyle),
              ),
              _buildRowContainer(
                labelText: i18n('margin_top'),
                valueWidget: CountButton(
                  maxValue: 300,
                  minValue: 0,
                  selectedValue: controller.danmakuTopArea.value.toInt(),
                  onChanged: (val) => controller.danmakuTopArea.value = val.toDouble(),
                ),
              ),
              _buildRowContainer(
                labelText: i18n('margin_bottom'),
                valueWidget: CountButton(
                  maxValue: 300,
                  minValue: 0,
                  selectedValue: controller.danmakuBottomArea.value.toInt(),
                  onChanged: (val) => controller.danmakuBottomArea.value = val.toDouble(),
                ),
              ),
              _buildRowContainer(
                labelText: i18n("settings_danmaku_opacity"),
                valueWidget: SfSlider(
                  min: 0.0,
                  max: 1.0,
                  value: controller.danmakuOpacity.value,
                  activeColor: primaryColor,
                  inactiveColor: Colors.white12,
                  onChanged: (dynamic val) => controller.danmakuOpacity.value = val as double,
                ),
                trailingWidget: Text('${(controller.danmakuOpacity.value * 100).toInt()}%', style: digitStyle),
              ),
              _buildRowContainer(
                labelText: i18n("settings_danmaku_speed"),
                valueWidget: SfSlider(
                  min: 5.0,
                  max: 400.0,
                  value: controller.danmakuSpeed.value,
                  activeColor: primaryColor,
                  inactiveColor: Colors.white12,
                  onChanged: (dynamic val) => controller.danmakuSpeed.value = val as double,
                ),
                trailingWidget: Text(controller.danmakuSpeed.value.toInt().toString(), style: digitStyle),
              ),
              _buildRowContainer(
                labelText: i18n("settings_danmaku_fontsize"),
                valueWidget: SfSlider(
                  min: 10.0,
                  max: 30.0,
                  value: controller.danmakuFontSize.value,
                  activeColor: primaryColor,
                  inactiveColor: Colors.white12,
                  onChanged: (dynamic val) => controller.danmakuFontSize.value = val as double,
                ),
                trailingWidget: Text(controller.danmakuFontSize.value.toInt().toString(), style: digitStyle),
              ),
              _buildRowContainer(
                labelText: i18n("danmaku_stroke"),
                valueWidget: Align(
                  alignment: Alignment.centerRight,
                  child: Switch(
                    value: controller.enableDanmakuStroke.value,
                    activeThumbColor: primaryColor,
                    onChanged: (val) => controller.enableDanmakuStroke.value = val,
                  ),
                ),
              ),
              _buildRowContainer(
                labelText: i18n("settings_danmaku_fontBorder"),
                valueWidget: SfSlider(
                  min: 0.0,
                  max: 4.0,
                  value: controller.danmakuFontBorder.value,
                  activeColor: primaryColor,
                  inactiveColor: Colors.white12,
                  onChanged: (dynamic val) => controller.danmakuFontBorder.value = val as double,
                ),
                trailingWidget: Text(controller.danmakuFontBorder.value.toStringAsFixed(2), style: digitStyle),
              ),
              _buildRowContainer(
                labelText: i18n("danmaku_fps"),
                valueWidget: SfSlider(
                  min: 30.0,
                  max: 240.0,
                  value: controller.danmakuFps.value.toDouble(),
                  activeColor: primaryColor,
                  inactiveColor: Colors.white12,
                  onChanged: (dynamic val) => controller.danmakuFps.value = (val as double).toInt(),
                ),
                trailingWidget: Text('${controller.danmakuFps.value.toInt()} FPS', style: digitStyle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
