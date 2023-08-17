import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_barrage/flutter_barrage.dart';
import 'package:get/get_rx/get_rx.dart';
import 'package:get/get_state_manager/src/rx_flutter/rx_obx_widget.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller.dart';

class VideoControllerPanel extends StatefulWidget {
  final VideoController controller;

  const VideoControllerPanel({
    Key? key,
    required this.controller,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _VideoControllerPanelState();
}

class _VideoControllerPanelState extends State<VideoControllerPanel> {
  static const barHeight = 56.0;

  // Video controllers
  VideoController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.enableController();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() => controller.hasError.value
        ? ErrorWidget(controller: controller)
        : MouseRegion(
            onHover: (event) => controller.enableController(),
            onExit: (event) {
              controller.showControllerTimer?.cancel();
              controller.showController.toggle();
            },
            child: Stack(children: [
              DanmakuViewer(controller: controller),
              !controller.isPlaying.value ? Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.5),
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.white,),
                  ),
                ),
              ): Container(),
              GestureDetector(
                onTap: () {
                  if (controller.showSettting.value) {
                    controller.showSettting.toggle();
                  } else {
                    controller.isPlaying.value
                        ? controller.enableController()
                        : controller.togglePlayPause();
                  }
                },
                onDoubleTap: () => controller.isWindowFullscreen.value
                    ? controller.toggleWindowFullScreen()
                    : controller.toggleFullScreen(),
                child: BrightnessVolumnDargArea(controller: controller),
              ),
              SettingsPanel(
                controller: controller,
              ),
              LockButton(controller: controller),
              TopActionBar(
                controller: controller,
                barHeight: barHeight,
              ),
              BottomActionBar(
                controller: controller,
                barHeight: barHeight,
              ),
            ]),
          ));
  }
}

class ErrorWidget extends StatelessWidget {
  const ErrorWidget({
    Key? key,
    required this.controller,
  }) : super(key: key);

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              S.of(context).play_video_failed,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
          ElevatedButton(
            onPressed: () => controller.refresh(),
            style: ElevatedButton.styleFrom(
              elevation: 0,
              backgroundColor: Colors.white.withOpacity(0.2),
            ),
            child: Text(
              S.of(context).retry,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

// Top action bar widgets
class TopActionBar extends StatelessWidget {
  const TopActionBar({
    Key? key,
    required this.controller,
    required this.barHeight,
  }) : super(key: key);

  final VideoController controller;
  final double barHeight;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => AnimatedPositioned(
        top: (!controller.isPipMode.value &&
                !controller.showSettting.value &&
                controller.showController.value &&
                !controller.showLocked.value)
            ? 0
            : -barHeight,
        left: 0,
        right: 0,
        height: barHeight,
        duration: const Duration(milliseconds: 300),
        child: Container(
          height: barHeight,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.transparent, Colors.black45],
            ),
          ),
          child: Row(children: [
            if (controller.fullscreenUI) BackButton(controller: controller),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  controller.room.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ),
            if (controller.fullscreenUI) ...[
              const DatetimeInfo(),
              BatteryInfo(controller: controller),
            ],
            if (!controller.fullscreenUI && controller.supportPip)
              PIPButton(controller: controller),
          ]),
        ),
      ),
    );
  }
}

class DatetimeInfo extends StatefulWidget {
  const DatetimeInfo({Key? key}) : super(key: key);

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
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
    );
  }
}

class BatteryInfo extends StatefulWidget {
  const BatteryInfo({Key? key, required this.controller}) : super(key: key);

  final VideoController controller;

  @override
  State<BatteryInfo> createState() => _BatteryInfoState();
}

class _BatteryInfoState extends State<BatteryInfo> {
  // Battery level control
  final Battery _battery = Battery();

  final batteryLevel = 100.obs;

  void initBattery() {
    _battery.batteryLevel.then((value) => batteryLevel.value = value);
    _battery.onBatteryStateChanged.listen((state) async {
      batteryLevel.value = await _battery.batteryLevel;
    });
  }

  @override
  void initState() {
    super.initState();
    // initBattery();
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
          color: Colors.white.withOpacity(0.4),
          border: Border.all(color: Colors.white),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Obx(() => Text(
                '${batteryLevel.value}',
                style: const TextStyle(color: Colors.white, fontSize: 9),
              )),
        ),
      ),
    );
  }
}

class BackButton extends StatelessWidget {
  const BackButton({Key? key, required this.controller}) : super(key: key);

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => controller.isWindowFullscreen.value
          ? controller.toggleWindowFullScreen()
          : controller.toggleFullScreen(),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.all(12),
        child: const Icon(
          Icons.arrow_back_rounded,
          color: Colors.white,
        ),
      ),
    );
  }
}

class PIPButton extends StatelessWidget {
  const PIPButton({Key? key, required this.controller}) : super(key: key);

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => controller.enterPipMode(context),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.all(12),
        child: const Icon(
          CustomIcons.float_window,
          color: Colors.white,
        ),
      ),
    );
  }
}

// Center widgets
class DanmakuViewer extends StatelessWidget {
  const DanmakuViewer({
    Key? key,
    required this.controller,
  }) : super(key: key);

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraint) => SizedBox(
        width: constraint.maxWidth,
        height: constraint.maxHeight,
        child: Obx(() => Opacity(
              opacity: controller.hideDanmaku.value
                  ? 0
                  : controller.danmakuOpacity.value,
              child: BarrageWall(
                width: constraint.maxWidth,
                height: constraint.maxHeight * controller.danmakuArea.value,
                controller: controller.danmakuController,
                speed: controller.danmakuSpeed.value.toInt(),
                maxBulletHeight: controller.danmakuFontSize * 1.5,
                massiveMode: false, // disabled by default
                child: Container(),
              ),
            )),
      ),
    );
  }
}

class BrightnessVolumnDargArea extends StatefulWidget {
  const BrightnessVolumnDargArea({
    Key? key,
    required this.controller,
  }) : super(key: key);

  final VideoController controller;

  @override
  State<BrightnessVolumnDargArea> createState() =>
      _BrightnessVolumnDargAreaState();
}

class _BrightnessVolumnDargAreaState extends State<BrightnessVolumnDargArea> {
  VideoController get controller => widget.controller;

  // Darg bv ui control
  Timer? _hideBVTimer;
  bool _hideBVStuff = true;
  bool _isDargLeft = true;
  double _updateDargVarVal = 1.0;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _hideBVTimer?.cancel();
    super.dispose();
  }

  void _cancelAndRestartHideBVTimer() {
    _hideBVTimer?.cancel();
    _hideBVTimer = Timer(const Duration(seconds: 1), () {
      setState(() => _hideBVStuff = true);
    });
    setState(() => _hideBVStuff = false);
  }

  void _onVerticalDragUpdate(Offset postion, Offset delta) async {
    if (controller.showLocked.value) return;
    if (delta.distance < 0.2) return;

    // fix darg left change to switch bug
    final width = MediaQuery.of(context).size.width;
    final dargLeft = (postion.dx > (width / 2)) ? false : true;
    // disable windows brightness
    if (Platform.isWindows && dargLeft) return;
    if (_hideBVStuff || _isDargLeft != dargLeft) {
      _isDargLeft = dargLeft;
      if (_isDargLeft) {
        await controller.brightness().then((double v) {
          setState(() => _updateDargVarVal = v);
        });
      } else {
        await controller.volumn().then((double v) {
          setState(() => _updateDargVarVal = v);
        });
      }
    }
    _cancelAndRestartHideBVTimer();

    double dragRange = (delta.direction < 0 || delta.direction > pi)
        ? _updateDargVarVal + 0.01
        : _updateDargVarVal - 0.01;
    // 是否溢出
    dragRange = min(dragRange, 1.0);
    dragRange = max(dragRange, 0.0);
    // 亮度 & 音量
    if (_isDargLeft) {
      controller.setBrightness(dragRange);
    } else {
      controller.setVolumn(dragRange);
    }
    setState(() => _updateDargVarVal = dragRange);
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

    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          _onVerticalDragUpdate(event.localPosition, event.scrollDelta);
        }
      },
      child: GestureDetector(
        onVerticalDragUpdate: (details) =>
            _onVerticalDragUpdate(details.localPosition, details.delta),
        child: Container(
          color: Colors.transparent,
          alignment: Alignment.center,
          child: AnimatedOpacity(
            opacity: !_hideBVStuff ? 0.8 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: Card(
              color: Colors.black,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(iconData, color: Colors.white),
                    Padding(
                      padding: const EdgeInsets.only(left: 8, right: 4),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 100,
                          height: 20,
                          child: LinearProgressIndicator(
                            value: _updateDargVarVal,
                            backgroundColor: Colors.white38,
                            valueColor: AlwaysStoppedAnimation(
                              Theme.of(context).indicatorColor,
                            ),
                          ),
                        ),
                      ),
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
  const LockButton({Key? key, required this.controller}) : super(key: key);

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() => AnimatedOpacity(
          opacity: (!controller.isPipMode.value &&
                  !controller.showSettting.value &&
                  controller.fullscreenUI &&
                  controller.showController.value)
              ? 0.9
              : 0.0,
          duration: const Duration(milliseconds: 300),
          child: Align(
            alignment: Alignment.centerRight,
            child: AbsorbPointer(
              absorbing: !controller.showController.value,
              child: Container(
                margin: const EdgeInsets.only(right: 20.0),
                child: IconButton(
                  onPressed: () => controller.showLocked.toggle(),
                  icon: Icon(
                    controller.showLocked.value
                        ? Icons.lock_rounded
                        : Icons.lock_open_rounded,
                    size: 28,
                  ),
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
        ));
  }
}

// Bottom action bar widgets
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({
    Key? key,
    required this.controller,
    required this.barHeight,
  }) : super(key: key);

  final VideoController controller;
  final double barHeight;

  @override
  Widget build(BuildContext context) {
    return Obx(() => AnimatedPositioned(
          bottom: (!controller.isPipMode.value &&
                  !controller.showSettting.value &&
                  controller.showController.value &&
                  !controller.showLocked.value)
              ? 0
              : -barHeight,
          left: 0,
          right: 0,
          height: barHeight,
          duration: const Duration(milliseconds: 300),
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
            child: Row(
              children: <Widget>[
                PlayPauseButton(controller: controller),
                RefreshButton(controller: controller),
                DanmakuButton(controller: controller),
                if (controller.fullscreenUI)
                  SettingsButton(controller: controller),
                const Spacer(),
                if (controller.supportWindowFull &&
                    !controller.isFullscreen.value)
                  ExpandWindowButton(controller: controller),
                if (!controller.isWindowFullscreen.value)
                  ExpandButton(controller: controller),
              ],
            ),
          ),
        ));
  }
}

class PlayPauseButton extends StatelessWidget {
  const PlayPauseButton({Key? key, required this.controller}) : super(key: key);

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => controller.togglePlayPause(),
      child: Obx(() => Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.all(12),
            child: Icon(
              controller.isPlaying.value
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              color: Colors.white,
            ),
          )),
    );
  }
}

class RefreshButton extends StatelessWidget {
  const RefreshButton({Key? key, required this.controller}) : super(key: key);

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => controller.refresh(),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.all(12),
        child: const Icon(
          Icons.refresh_rounded,
          color: Colors.white,
        ),
      ),
    );
  }
}

class DanmakuButton extends StatelessWidget {
  const DanmakuButton({
    Key? key,
    required this.controller,
  }) : super(key: key);

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => controller.hideDanmaku.toggle(),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.all(12),
        child: Obx(() => Icon(
              controller.hideDanmaku.value
                  ? CustomIcons.danmaku_close
                  : CustomIcons.danmaku_open,
              color: Colors.white,
            )),
      ),
    );
  }
}

class SettingsButton extends StatelessWidget {
  const SettingsButton({Key? key, required this.controller}) : super(key: key);

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => controller.showSettting.toggle(),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.all(12),
        child: const Icon(
          CustomIcons.danmaku_setting,
          color: Colors.white,
        ),
      ),
    );
  }
}

class ExpandWindowButton extends StatelessWidget {
  const ExpandWindowButton({Key? key, required this.controller})
      : super(key: key);

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => controller.toggleWindowFullScreen(),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.all(12),
        child: RotatedBox(
          quarterTurns: 1,
          child: Obx(() => Icon(
                controller.isWindowFullscreen.value
                    ? Icons.unfold_less_rounded
                    : Icons.unfold_more_rounded,
                color: Colors.white,
                size: 26,
              )),
        ),
      ),
    );
  }
}

class ExpandButton extends StatelessWidget {
  const ExpandButton({Key? key, required this.controller}) : super(key: key);

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => controller.toggleFullScreen(),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.all(12),
        child: Obx(() => Icon(
              controller.isFullscreen.value
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded,
              color: Colors.white,
              size: 26,
            )),
      ),
    );
  }
}

// Settings panel widgets
class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    Key? key,
    required this.controller,
  }) : super(key: key);

  final VideoController controller;

  static const double width = 380;

  @override
  Widget build(BuildContext context) {
    return Obx(() => AnimatedPositioned(
          top: 0,
          bottom: 0,
          right: controller.showSettting.value ? 0 : -width,
          width: width,
          duration: const Duration(milliseconds: 500),
          child: Card(
            color: Colors.black.withOpacity(0.8),
            child: SizedBox(
              width: width,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  ShutdownTimerSetting(controller: controller),
                  VideoFitSetting(controller: controller),
                  DanmakuSetting(controller: controller),
                ],
              ),
            ),
          ),
        ));
  }
}

class ShutdownTimerSetting extends StatelessWidget {
  const ShutdownTimerSetting({
    Key? key,
    required this.controller,
  }) : super(key: key);

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            S.of(context).settings_timedclose_title,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.white),
          ),
        ),
        Obx(() => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Slider(
                min: 0,
                max: 120,
                value: controller.shutdownMinute.value.toDouble(),
                onChanged: (value) =>
                    controller.setShutdownTimer(value.toInt()),
              ),
              trailing: Text(
                S.of(context).timedclose_time(
                    controller.shutdownMinute.value.toInt().toString()),
                style: const TextStyle(color: Colors.white),
              ),
            )),
      ],
    );
  }
}

class VideoFitSetting extends StatefulWidget {
  const VideoFitSetting({
    Key? key,
    required this.controller,
  }) : super(key: key);

  final VideoController controller;

  @override
  State<VideoFitSetting> createState() => _VideoFitSettingState();
}

class _VideoFitSettingState extends State<VideoFitSetting> {
  late final fitmodes = {
    S.of(context).videofit_contain: BoxFit.contain,
    S.of(context).videofit_fill: BoxFit.fill,
    S.of(context).videofit_cover: BoxFit.cover,
    S.of(context).videofit_fitwidth: BoxFit.fitWidth,
    S.of(context).videofit_fitheight: BoxFit.fitHeight,
  };
  late int fitIndex = fitmodes.values
      .toList()
      .indexWhere((e) => e == widget.controller.videoFit.value);

  @override
  Widget build(BuildContext context) {
    final Color color = Theme.of(context).colorScheme.primary.withOpacity(0.8);
    final isSelected = [false, false, false, false, false];
    isSelected[fitIndex] = true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            S.of(context).settings_videofit_title,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.white),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: ToggleButtons(
            borderRadius: BorderRadius.circular(10),
            // selectedBorderColor: color,
            // borderColor: color,
            selectedColor: Theme.of(context).colorScheme.primary,
            fillColor: color,
            isSelected: isSelected,
            onPressed: (index) {
              setState(() => fitIndex = index);
              widget.controller.setVideoFit(fitmodes.values.toList()[index]);
            },
            children: fitmodes.keys
                .map<Widget>((e) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(e,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                          )),
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }
}

class DanmakuSetting extends StatelessWidget {
  const DanmakuSetting({
    Key? key,
    required this.controller,
  }) : super(key: key);

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    const TextStyle label = TextStyle(color: Colors.white);
    const TextStyle digit = TextStyle(color: Colors.white);

    return Obx(() => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                S.of(context).settings_danmaku_title,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.white),
              ),
            ),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Text(S.of(context).settings_danmaku_area, style: label),
              title: Slider(
                divisions: 10,
                min: 0.0,
                max: 1.0,
                value: controller.danmakuArea.value,
                onChanged: (val) => controller.danmakuArea.value = val,
              ),
              trailing: Text(
                '${(controller.danmakuArea.value * 100).toInt()}%',
                style: digit,
              ),
            ),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading:
                  Text(S.of(context).settings_danmaku_opacity, style: label),
              title: Slider(
                divisions: 10,
                min: 0.0,
                max: 1.0,
                value: controller.danmakuOpacity.value,
                onChanged: (val) => controller.danmakuOpacity.value = val,
              ),
              trailing: Text(
                '${(controller.danmakuOpacity.value * 100).toInt()}%',
                style: digit,
              ),
            ),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Text(S.of(context).settings_danmaku_speed, style: label),
              title: Slider(
                divisions: 15,
                min: 5.0,
                max: 20.0,
                value: controller.danmakuSpeed.value,
                onChanged: (val) => controller.danmakuSpeed.value = val,
              ),
              trailing: Text(
                controller.danmakuSpeed.value.toInt().toString(),
                style: digit,
              ),
            ),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading:
                  Text(S.of(context).settings_danmaku_fontsize, style: label),
              title: Slider(
                divisions: 20,
                min: 10.0,
                max: 30.0,
                value: controller.danmakuFontSize.value,
                onChanged: (val) => controller.danmakuFontSize.value = val,
              ),
              trailing: Text(
                controller.danmakuFontSize.value.toInt().toString(),
                style: digit,
              ),
            ),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading:
                  Text(S.of(context).settings_danmaku_fontBorder, style: label),
              title: Slider(
                divisions: 25,
                min: 0.0,
                max: 2.5,
                value: controller.danmakuFontBorder.value,
                onChanged: (val) => controller.danmakuFontBorder.value = val,
              ),
              trailing: Text(
                controller.danmakuFontBorder.value.toStringAsFixed(2),
                style: digit,
              ),
            ),
            // ListTile(
            //   dense: true,
            //   contentPadding: EdgeInsets.zero,
            //   leading:
            //       Text(S.of(context).settings_danmaku_amount, style: label),
            //   title: Slider(
            //     divisions: 90,
            //     min: 10,
            //     max: 100,
            //     value: controller.danmakuAmount.value.toDouble(),
            //     onChanged: (val) =>
            //         controller.danmakuAmount.value = val.toInt(),
            //   ),
            //   trailing: Text(
            //     controller.danmakuAmount.value.toString(),
            //     style: digit,
            //   ),
            // ),
          ],
        ));
  }
}
