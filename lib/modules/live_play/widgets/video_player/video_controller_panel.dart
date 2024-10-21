import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/widgets/utils.dart';
import 'package:pure_live/modules/live_play/live_play_controller.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller.dart';
import 'package:pure_live/plugins/barrage.dart';
import 'package:pure_live/plugins/extension/string_extension.dart';

class VideoControllerPanel extends StatefulWidget {
  final VideoController controller;

  const VideoControllerPanel({
    super.key,
    required this.controller,
  });

  @override
  State<StatefulWidget> createState() => _VideoControllerPanelState();
}

class _VideoControllerPanelState extends State<VideoControllerPanel> {
  static const barHeight = 56.0;

  // Video controllers
  VideoController get controller => widget.controller;
  double currentVolume = 1.0;
  bool showVolume = true;
  Timer? _hideVolume;

  void restartTimer() {
    _hideVolume?.cancel();
    _hideVolume = Timer(const Duration(seconds: 1), () {
      setState(() => showVolume = true);
    });
    setState(() => showVolume = false);
  }

  @override
  void dispose() {
    _hideVolume?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.enableController();
    });
  }

  void updateVolumn(double? volume) {
    restartTimer();
    setState(() {
      currentVolume = volume!;
    });
  }

  @override
  Widget build(BuildContext context) {
    IconData iconData;
    iconData = currentVolume <= 0
        ? Icons.volume_mute
        : currentVolume < 0.5
            ? Icons.volume_down
            : Icons.volume_up;
    return Material(
      type: MaterialType.transparency,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.mediaPlay): () =>
              controller.videoPlayer.play(),
          const SingleActivator(LogicalKeyboardKey.mediaPause): () =>
              controller.videoPlayer.pause(),
          const SingleActivator(LogicalKeyboardKey.mediaPlayPause): () =>
              controller.videoPlayer.togglePlayPause(),
          const SingleActivator(LogicalKeyboardKey.space): () =>
              controller.videoPlayer.togglePlayPause(),
          const SingleActivator(LogicalKeyboardKey.keyR): () =>
              controller.refresh(),
          const SingleActivator(LogicalKeyboardKey.arrowUp): () async {
            double? volume = 1.0;
            volume = await controller.getVolume();
            volume = (volume! + 0.05);
            volume = min(volume, 1.0);
            volume = max(volume, 0.0);
            controller.setVolume(volume);
            updateVolumn(volume);
          },
          const SingleActivator(LogicalKeyboardKey.arrowDown): () async {
            double? volume = 1.0;
            volume = await controller.getVolume();
            volume = (volume! - 0.05);
            volume = min(volume, 1.0);
            volume = max(volume, 0.0);
            controller.setVolume(volume);
            updateVolumn(volume);
          },
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              controller.toggleFullScreen(),
        },
        child: Focus(
          autofocus: true,
          child: Obx(() => controller.videoPlayer.hasError.value
              ? ErrorWidget(controller: controller)
              : MouseRegion(
                  onHover: (event) => controller.enableController(),
                  onExit: (event) {
                    controller.showControllerTimer?.cancel();
                    controller.showController.toggle();
                  },
                  child: Stack(children: [
                    Container(
                      color: Colors.transparent,
                      alignment: Alignment.center,
                      child: AnimatedOpacity(
                        opacity: !showVolume ? 0.8 : 0.0,
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
                                  padding:
                                      const EdgeInsets.only(left: 8, right: 4),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: SizedBox(
                                      width: 100,
                                      height: 20,
                                      child: LinearProgressIndicator(
                                        value: currentVolume,
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
                    DanmakuViewer(controller: controller),
                    GestureDetector(
                        onTap: () {
                          if (controller.showSettting.value) {
                            controller.showSettting.toggle();
                          } else {
                            controller.videoPlayer.isPlaying.value
                                ? controller.enableController()
                                : controller.togglePlayPause();
                          }
                        },
                        onDoubleTap: () =>
                            controller.videoPlayer.isWindowFullscreen.value
                                ? controller.toggleWindowFullScreen()
                                : controller.toggleFullScreen(),
                        child: BrightnessVolumeDargArea(
                          controller: controller,
                        )),
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
                )),
        ),
      ),
    );
  }
}

class ErrorWidget extends StatelessWidget {
  const ErrorWidget({
    super.key,
    required this.controller,
  });

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
    super.key,
    required this.controller,
    required this.barHeight,
  });

  final VideoController controller;
  final double barHeight;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => AnimatedPositioned(
        top: (!controller.videoPlayer.isPipMode.value &&
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
            if (controller.videoPlayer.fullscreenUI)
              BackButton(controller: controller),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  controller.room.title!,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      decoration: TextDecoration.none),
                ),
              ),
            ),

            /// 直播中的关注列表
            IconButton(
              onPressed: () {
                // showFavorite(controller);
                showDialogList(
                    controller, Get.find<FavoriteController>().onlineRooms,
                    isReverse: false, title: S.of(context).favorites_title);
              },
              icon: const Icon(
                Icons.featured_play_list_outlined,
                color: Colors.white,
              ),
            ),

            /// 历史记录
            IconButton(
              onPressed: () {
                // showHistory(controller);
                showDialogList(
                    controller, Get.find<SettingsService>().historyRooms,
                    isReverse: true, title: S.of(context).history);
              },
              icon: const Icon(
                Icons.history,
                color: Colors.white,
              ),
            ),

            /// 时间，电池电量信息等
            if (controller.videoPlayer.fullscreenUI) ...[
              const DatetimeInfo(),
              BatteryInfo(controller: controller),
            ],

            /// 画中画
            if (!controller.videoPlayer.fullscreenUI &&
                controller.videoPlayer.supportPip &&
                controller.videoPlayerIndex != 4)
              PIPButton(controller: controller),
          ]),
        ),
      ),
    );
  }
}

/// 历史记录信息
void showFavorite(VideoController controller) {
  // if (controller.isVertical.value) {
  //   // controller.showFollowUserSheet();
  //   return;
  // }

  final FavoriteController favoriteController = Get.find<FavoriteController>();
  const dense = true;
  final rooms = favoriteController.onlineRooms;
  Utils.showRightDialog(
    title: S.of(Get.context!).favorites_title,
    width: 400,
    useSystem: true,
    child: () {
      return LayoutBuilder(builder: (context, constraint) {
        final width = constraint.maxWidth;
        int crossAxisCount =
            width > 1280 ? 4 : (width > 960 ? 3 : (width > 640 ? 2 : 1));
        if (dense) {
          crossAxisCount =
              width > 1280 ? 5 : (width > 960 ? 4 : (width > 640 ? 3 : 2));
        }
        return EasyRefresh(
          child: rooms.isEmpty
              ? EmptyView(
                  icon: Icons.history_rounded,
                  title: S.of(context).empty_history,
                  subtitle: '',
                )
              : MasonryGridView.count(
                  padding: const EdgeInsets.all(5),
                  controller: ScrollController(),
                  crossAxisCount: crossAxisCount,
                  itemCount: rooms.length,
                  itemBuilder: (context, index) => RoomCard(
                    room: rooms[index],
                    dense: dense,
                    onTap: () {
                      resetRoomInDialog(rooms[index]);
                    },
                  ),
                ),
        );
      });
    }(),
  );
}

void resetRoomInDialog(LiveRoom item, {isBottomSheet = false}) {
  if (isBottomSheet) {
    var curContext = Get.context!;
    Navigator.pop(curContext);
  } else {
    Utils.hideRightDialog();
  }

  if (item.platform.isNullOrEmpty || item.roomId.isNullOrEmpty) {
    return;
  }

  var controller = Get.find<LivePlayController>();
  var currentPlayRoom = controller.currentPlayRoom;
  if (item.platform == currentPlayRoom.value.platform &&
      item.roomId == currentPlayRoom.value.roomId) {
    return;
  }
  controller.videoController?.exitFull();
  controller.resetRoom(
    Sites.of(item.platform!),
    item.roomId!,
  );
}

/// 历史记录信息
void showHistory(VideoController controller) {
  if (controller.isVertical.value) {
    // controller.showFollowUserSheet();
    return;
  }

  final SettingsService settings = Get.find<SettingsService>();
  const dense = true;
  final rooms = settings.historyRooms;
  Utils.showRightDialog(
    title: S.of(Get.context!).history,
    width: 400,
    useSystem: true,
    child: () {
      return LayoutBuilder(builder: (context, constraint) {
        final width = constraint.maxWidth;
        int crossAxisCount =
            width > 1280 ? 4 : (width > 960 ? 3 : (width > 640 ? 2 : 1));
        if (dense) {
          crossAxisCount =
              width > 1280 ? 5 : (width > 960 ? 4 : (width > 640 ? 3 : 2));
        }
        return EasyRefresh(
          child: rooms.isEmpty
              ? EmptyView(
                  icon: Icons.history_rounded,
                  title: S.of(context).empty_history,
                  subtitle: '',
                )
              : MasonryGridView.count(
                  padding: const EdgeInsets.all(5),
                  controller: ScrollController(),
                  crossAxisCount: crossAxisCount,
                  itemCount: rooms.length,
                  itemBuilder: (context, index) => RoomCard(
                    room: rooms[rooms.length - 1 - index],
                    dense: dense,
                    onTap: () {
                      resetRoomInDialog(rooms[rooms.length - 1 - index]);
                    },
                  ),
                ),
        );
      });
    }(),
  );
}

/// 显示列表
void showDialogList(VideoController controller, RxList<LiveRoom> rooms,
    {var isReverse = false, String title = ""}) {
  var livePlayController = Get.find<LivePlayController>();
  const dense = true;
  if (controller.isVertical.value || !livePlayController.isFullscreen.value) {
    // controller.showFollowUserSheet();
    Utils.showBottomSheet(
      title: title,
      child: showDialogListBody(rooms, isReverse: isReverse, isBottomSheet: true),
    );
    return;
  }

  Utils.showRightDialog(
    title: S.of(Get.context!).history,
    width: 400,
    useSystem: true,
    child: showDialogListBody(rooms, isReverse: isReverse),
  );
}

Widget showDialogListBody(RxList<LiveRoom> rooms,
    {isReverse = false, isBottomSheet = false}) {
  return LayoutBuilder(builder: (context, constraint) {
    final width = constraint.maxWidth;
    var dense = true;
    int crossAxisCount =
        width > 1280 ? 4 : (width > 960 ? 3 : (width > 640 ? 2 : 1));
    if (dense) {
      crossAxisCount =
          width > 1280 ? 5 : (width > 960 ? 4 : (width > 640 ? 3 : 2));
    }
    return Obx(
      () => rooms.isEmpty
          ? EmptyView(
              icon: Icons.history_rounded,
              title: S.of(context).empty_history,
              subtitle: '',
            )
          : MasonryGridView.count(
              padding: const EdgeInsets.all(5),
              controller: ScrollController(),
              crossAxisCount: crossAxisCount,
              itemCount: rooms.length,
              itemBuilder: (context, index) => RoomCard(
                room:
                    isReverse ? rooms[rooms.length - 1 - index] : rooms[index],
                dense: dense,
                onTap: () {
                  resetRoomInDialog(
                      isReverse
                          ? rooms[rooms.length - 1 - index]
                          : rooms[index],
                      isBottomSheet: isBottomSheet);
                },
              ),
            ),
    );
  });
}

/// 时间信息
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
        style: const TextStyle(
            color: Colors.white, fontSize: 14, decoration: TextDecoration.none),
      ),
    );
  }
}

/// 电池信息
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
          color: Colors.white.withOpacity(0.4),
          border: Border.all(color: Colors.white),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Obx(() => Text(
                '${widget.controller.batteryLevel.value}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    decoration: TextDecoration.none),
              )),
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
      onTap: () => controller.videoPlayer.isWindowFullscreen.value
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
  const PIPButton({super.key, required this.controller});

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
// Center widgets
class DanmakuViewer extends StatelessWidget {
  const DanmakuViewer({
    super.key,
    required this.controller,
  });

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() => Opacity(
          opacity: controller.hideDanmaku.value
              ? 0
              : controller.danmakuOpacity.value,
          child: controller.danmakuArea.value == 0.0
              ? Container()
              : BarrageWall(
                  width: MediaQuery.of(context).size.width,
                  height: MediaQuery.of(context).size.height *
                      controller.danmakuArea.value,
                  controller: controller.danmakuController,
                  speed: controller.danmakuSpeed.value.toInt(),
                  maxBulletHeight: controller.danmakuFontSize * 1.5,
                  massiveMode: false,
                  // disabled by default
                  child: Container(),
                ),
        ));
  }
}

class BrightnessVolumeDargArea extends StatefulWidget {
  const BrightnessVolumeDargArea({
    super.key,
    required this.controller,
  });

  final VideoController controller;

  @override
  State<BrightnessVolumeDargArea> createState() =>
      BrightnessVolumeDargAreaState();
}

class BrightnessVolumeDargAreaState extends State<BrightnessVolumeDargArea> {
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

  void updateVolume(double? volume) {
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
    if (delta.distance < 0.2) return;

    // fix darg left change to switch bug
    final width = MediaQuery.of(context).size.width;
    final dargLeft = (position.dx > (width / 2)) ? false : true;
    // disable windows brightness
    if (Platform.isWindows && dargLeft) return;
    if (_hideBVStuff || _isDargLeft != dargLeft) {
      _isDargLeft = dargLeft;
      if (_isDargLeft) {
        await controller.brightness().then((double v) {
          setState(() => _updateDargVarVal = v);
        });
      } else {
        await controller.getVolume().then((double? v) {
          setState(() => _updateDargVarVal = v!);
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
      controller.setVolume(dragRange);
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
  const LockButton({super.key, required this.controller});

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() => AnimatedOpacity(
          opacity: (!controller.videoPlayer.isPipMode.value &&
                  !controller.showSettting.value &&
                  controller.videoPlayer.fullscreenUI &&
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
                  onPressed: () => {
                    controller.showLocked.toggle(),
                    if (Platform.isAndroid)
                      {
                        if (controller.showLocked.value)
                          {controller.videoPlayer.disableRotation()}
                        else
                          {controller.videoPlayer.enableRotation()}
                      }
                  },
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
    super.key,
    required this.controller,
    required this.barHeight,
  });

  final VideoController controller;
  final double barHeight;

  @override
  Widget build(BuildContext context) {
    return Obx(() => AnimatedPositioned(
          bottom: (!controller.videoPlayer.isPipMode.value &&
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
                FavoriteButton(controller: controller),
                if (controller.videoPlayer.isFullscreen.value)
                  SettingsButton(controller: controller),
                const Spacer(),
                if (controller.videoPlayer.supportWindowFull &&
                    !controller.videoPlayer.isFullscreen.value)
                  ExpandWindowButton(controller: controller),
                if (!controller.videoPlayer.isWindowFullscreen.value)
                  ExpandButton(controller: controller),
              ],
            ),
          ),
        ));
  }
}

class PlayPauseButton extends StatelessWidget {
  const PlayPauseButton({super.key, required this.controller});

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => controller.togglePlayPause(),
      child: Obx(() => Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.all(12),
            child: Icon(
              controller.videoPlayer.isPlaying.value
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              color: Colors.white,
            ),
          )),
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
        padding: const EdgeInsets.all(12),
        child: const Icon(
          Icons.refresh_rounded,
          color: Colors.white,
        ),
      ),
    );
  }
}

class ScreenToggleButton extends StatelessWidget {
  const ScreenToggleButton({super.key, required this.controller});

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() => GestureDetector(
          onTap: () => controller.isVertical.value
              ? controller.setLandscapeOrientation()
              : controller.setPortraitOrientation(),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.all(12),
            child: Icon(
              controller.isVertical.value
                  ? Icons.crop_landscape
                  : Icons.crop_portrait,
              color: Colors.white,
            ),
          ),
        ));
  }
}

class DanmakuButton extends StatelessWidget {
  const DanmakuButton({
    super.key,
    required this.controller,
  });

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
  const SettingsButton({super.key, required this.controller});

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
  const ExpandWindowButton({super.key, required this.controller});

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
                controller.videoPlayer.isWindowFullscreen.value
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
  const ExpandButton({super.key, required this.controller});

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => controller.toggleFullScreen(),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.all(12),
        child: Obx(() => Icon(
              controller.videoPlayer.isFullscreen.value
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded,
              color: Colors.white,
              size: 26,
            )),
      ),
    );
  }
}

class FavoriteButton extends StatefulWidget {
  const FavoriteButton({
    super.key,
    required this.controller,
  });

  final VideoController controller;

  @override
  State<FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<FavoriteButton> {
  final settings = Get.find<SettingsService>();
  final LivePlayController controller = Get.find<LivePlayController>();
  late var isFavorite = controller.isFavorite;

  @override
  Widget build(BuildContext context) {
    return Obx(() => GestureDetector(
          onTap: () {
            if (isFavorite.value) {
              settings.removeRoom(widget.controller.room);
            } else {
              settings.addRoom(widget.controller.room);
            }
            controller.isFavorite.value = !controller.isFavorite.value;
            // setState(() => isFavorite.toggle);
          },
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.all(12),
            child: Icon(
              !isFavorite.value
                  ? Icons.favorite_outline_outlined
                  : Icons.favorite_rounded,
              color: Colors.white,
            ),
          ),
        ));
  }
}

// Settings panel widgets
class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    super.key,
    required this.controller,
  });

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
                  VideoFitSetting(controller: controller),
                  DanmakuSetting(controller: controller),
                ],
              ),
            ),
          ),
        ));
  }
}

class VideoFitSetting extends StatefulWidget {
  const VideoFitSetting({
    super.key,
    required this.controller,
  });

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
    int fitIndex = widget.controller.videoFitIndex.value;
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
              setState(() {
                fitIndex = index;
                widget.controller.videoFitIndex.value = index;
                widget.controller.setVideoFit(fitmodes.values.toList()[index]);
              });
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
    super.key,
    required this.controller,
  });

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
              leading: const Text('弹幕合并', style: label),
              subtitle: Text(
                  '相似度:${controller.mergeDanmuRating.value * 100}%的弹幕会被合并',
                  style: label),
              title: Slider(
                divisions: 10,
                min: 0.0,
                max: 1.0,
                value: controller.mergeDanmuRating.value,
                onChanged: (val) => controller.mergeDanmuRating.value = val,
              ),
              trailing: Text(
                '${(controller.mergeDanmuRating.value * 100).toInt()}%',
                style: digit,
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
          ],
        ));
  }
}
