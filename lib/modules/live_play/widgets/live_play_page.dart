import 'dart:io';
import 'dart:async';

import 'index.dart';

import 'package:remixicon/remixicon.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/plugins/event_bus.dart';
import 'package:pure_live/common/utils/live_url_tool.dart';
import 'package:pure_live/common/global/platform_utils.dart';
import 'package:pure_live/common/index.dart' hide BackButton;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:pure_live/modules/live_play/states/ui_state.dart';
import 'package:pure_live/modules/live_play/states/load_type.dart';
import 'package:pure_live/common/utils/share_command_handler.dart';
import 'package:pure_live/modules/live_play/widgets/play_other.dart';
import 'package:pure_live/modules/live_play/widgets/danmaku_tab.dart';
import 'package:pure_live/modules/live_play/widgets/video_keyboard.dart';
import 'package:pure_live/modules/live_play/local_interaction_sheet.dart';
import 'package:pure_live/modules/live_play/widgets/local_gift_effect.dart';
import 'package:pure_live/modules/live_play/controllers/player_state.dart';
import 'package:pure_live/common/services/settings/app_settings_controller.dart';
import 'package:pure_live/modules/live_play/controllers/live_play_controller.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller_panel.dart';
import 'package:pure_live/routes/app_navigation.dart';
import 'package:pure_live/player/core/secondary_player_service.dart';
import 'package:pure_live/modules/live_play/widgets/dual_view/dual_view_picker_sheet.dart';
import 'package:pure_live/modules/live_play/widgets/dual_view/secondary_window.dart';

class LivePlayPage extends GetView<LivePlayController> {
  const LivePlayPage({super.key});

  @override
  Widget build(BuildContext context) {
    // 构建时解析一次控制器实例：路由弹出、GetX 注销控制器后页面在退出动画期间仍可能
    // 重建 Obx，直接使用 GetView.controller（内部 Get.find）会抛 "LivePlayController not
    // found" 导致灰屏，因此这里缓存引用供后续闭包使用。
    final ctrl = controller;
    return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) {
            // 判定是否在全屏状态下被绕过 canPop 直接弹出（例如滑动返回连发事件
            // 或 GetX 手势直 pop），是则兜底重新进入直播间，保证“退出全屏”而不是“退出直播间”。
            final wasFullscreenOnPop = ctrl.isFullscreenActive;
            // 系统原生返回已完成，做兜底清理。
            ctrl.onPagePopCleanup();
            if (wasFullscreenOnPop) {
              final room = ctrl.room;
              // 等当前弹出手续完成后再打开新的直播间（默认普通模式）。
              WidgetsBinding.instance.addPostFrameCallback((_) {
                unawaited(AppNavigator.toLiveRoomDetail(liveRoom: room));
              });
            }
            return;
          }
          // canPop=false：先处理全屏/半屏/PiP，处理完成后才允许退出页面。
          // 注意不要在 isTransitioningFullScreen 时直接吞掉事件：该标志依赖平台
          // 通道调用完成后复位，一旦卡住会把后续所有返回事件无声吞掉（表现为
          // 滑动返回失效）。handleBackPress 自身幂等且有 600ms 连发保护。
          if (!ctrl.handleBackPress()) {
            // 走 GetX 路由退出：由 RouterDelegate 移除页面，保持与 Navigator 路由栈一致。
            Get.back();
          }
        },
        child: Container(
          color: Colors.black,
          width: double.infinity,
          height: double.infinity,
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              fit: StackFit.expand,
              children: [
                Obx(() {
                  // 兜底：控制器已被 GetX 注销（页面正在退出）时不再渲染直播间内容，
                  // 避免退出动画期间重建抛异常导致灰屏；极端竞态下也一律回退为空。
                  try {
                    if (!Get.isRegistered<LivePlayController>()) {
                      return const SizedBox.shrink();
                    }
                    final manager = GlobalPlayerService.instance.playerManager;
                    final isInPip = manager.isInPip.value || manager.isPipPreparing.value;
                    final state = ctrl.state.value;
                    final mode = state.ui.screenMode;
                    final videoController = state.player.videoController;

                    final child = _withLocalGiftEffect(_buildConstrainedChild(isInPip, mode, context));

                    if (videoController == null) {
                      return child;
                    }

                    return VideoKeyboardShortcuts(controller: videoController, child: child);
                  } catch (_) {
                    return const SizedBox.shrink();
                  }
                }),
                // 直播间信息 OSD：菜单开关控制，显示平台/房间/清晰度/分辨率/音频码率
                Positioned(
                  top: 70,
                  left: 10,
                  child: Obx(() {
                    if (!SettingsService.to.app.showRoomInfoOsd.v) return const SizedBox.shrink();
                    if (!Get.isRegistered<LivePlayController>()) return const SizedBox.shrink();
                    return _RoomInfoOsd(controller: ctrl);
                  }),
                ),
                // 双开小窗提升到页面顶层，支持在整个直播页范围内拖动
                Obx(() {
                  final manager = GlobalPlayerService.instance.playerManager;
                  final isInPip = manager.isInPip.value || manager.isPipPreparing.value;
                  if (isInPip) return const SizedBox.shrink();
                  return DraggableSecondaryWindow(maxWidth: constraints.maxWidth, maxHeight: constraints.maxHeight);
                }),
              ],
            ),
          ),
        ),
    );
  }

  Widget _withLocalGiftEffect(Widget child) {
    final message = controller.localGiftEffect.value;
    if (message == null) return child;
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        IgnorePointer(
          child: LocalGiftEffectView(key: ValueKey(message), message: message),
        ),
      ],
    );
  }

  Widget _buildConstrainedChild(bool isInPip, VideoMode mode, BuildContext context) {
    final manager = GlobalPlayerService.instance.playerManager;
    if (isInPip) {
      return Theme(
        data: ThemeData.dark(),
        child: Container(key: const ValueKey('pip'), color: Colors.transparent, child: manager.buildPiPOverlay()),
      );
    }

    if (mode == VideoMode.normal) {
      return Container(key: const ValueKey('normal'), color: Colors.black, child: buildNormalPlayerView(context));
    }

    return Container(key: const ValueKey('widescreen'), color: Colors.black, child: buildVideoPlayer());
  }

  Widget buildNormalPlayerView(BuildContext context) {
    final compactHeader = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            Obx(() {
              final avatar = controller.state.value.room.detail?.avatar;
              return CircleAvatar(
                foregroundImage: avatar != null && avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null,
                radius: 16,
                backgroundColor: Theme.of(context).disabledColor,
              );
            }),
            const SizedBox(width: 8),
            Expanded(
              child: Obx(() {
                final detail = controller.state.value.room.detail;
                if (detail == null) return const SizedBox.shrink();
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      detail.nick ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    Text(
                      (detail.area == null || detail.area!.isEmpty)
                          ? (detail.platform?.toUpperCase() ?? '')
                          : "${detail.platform?.toUpperCase()} / ${detail.area}",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                );
              }),
            ),
          ],
        ),
        actions: [
          Obx(() {
            final detail = controller.state.value.room.detail;
            if (detail == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: FavoriteFloatingButton(
                key: ValueKey('${detail.platform}:${detail.roomId}'),
                room: detail,
                compact: compactHeader,
              ),
            );
          }),
          PopupMenuButton(
            tooltip: i18n("menu"),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            offset: const Offset(12, 0),
            position: PopupMenuPosition.under,
            icon: const Icon(Remix.apps_2_line),
            onOpened: () {
              controller.updateUI(isMenuOpen: true);
            },
            onCanceled: () {
              controller.updateUI(isMenuOpen: false);
            },
            onSelected: (int index) {
              if (index == 0) {
                controller.openNaviteAPP();
              } else if (index == 1) {
                Get.dialog(PlayOther(controller: controller));
              } else if (index == 2) {
                showDlnaCastDialog();
              } else if (index == 3) {
                showTimerDialog(context);
              } else if (index == 4) {
                showVolumeSettingsDialog(context);
              } else if (index == 5) {
                final detail = controller.state.value.room.detail;
                if (detail != null) {
                  LiveUrlTool.getPlayUrlByRoomId(roomId: detail.roomId ?? '', platform: detail.platform ?? '');
                }
              } else if (index == 6) {
                final detail = controller.state.value.room.detail;
                if (detail != null) {
                  ShareCommandHandler.instance.onShareRoomPressed(detail);
                }
              } else if (index == 7) {
                if (!controller.localInteractionController.enabled.v) return;
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => LocalInteractionSheet(
                    controller: controller.localInteractionController,
                    platform: controller.state.value.room.detail?.platform ?? controller.site,
                    onMessage: (message, showAsDanmaku) =>
                        controller.emitLocalMessage(message, showAsDanmaku: showAsDanmaku),
                  ),
                );
              } else if (index == 8) {
                _openDualViewPicker(context);
              } else if (index == 9) {
                final osd = SettingsService.to.app.showRoomInfoOsd;
                osd.v = !osd.v;
                ToastUtil.show(osd.v ? i18n('room_info_osd_on') : i18n('room_info_osd_off'));
              } else if (index >= 10 && index < 10 + VideoMaskService.maxSlots) {
                final slot = index - 10;
                final maskRoom = controller.state.value.room.detail ?? controller.room;
                // 该槽位第一次设遮罩时才提示操作方式；关掉再打开会沿用上次
                // 调好的位置，不需要再提示一次。
                final isNew =
                    !VideoMaskService.instance.hasStoredMask(maskRoom.platform, maskRoom.roomId, slot);
                final visible =
                    VideoMaskService.instance.toggleMask(maskRoom.platform, maskRoom.roomId, slot);
                if (visible && isNew) ToastUtil.show(i18n('video_mask_created_hint'));
              }
              controller.updateUI(isMenuOpen: false);
            },
            itemBuilder: (BuildContext context) {
              return [
                PopupMenuItem(
                  value: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: MenuListTile(
                    leading: const Icon(Icons.open_in_new_rounded, size: 20),
                    text: i18n("open_live_room"),
                  ),
                ),
                PopupMenuItem(
                  value: 1,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: MenuListTile(
                    leading: Icon(Icons.swap_horiz_outlined, size: 20),
                    text: i18n("switch_live_room"),
                  ),
                ),
                PopupMenuItem(
                  value: 2,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: MenuListTile(leading: const Icon(Remix.tv_2_line, size: 20), text: i18n("cast_screen")),
                ),
                PopupMenuItem(
                  value: 3,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: MenuListTile(leading: const Icon(Remix.time_line, size: 20), text: i18n("sleep_timer")),
                ),
                PopupMenuItem(
                  value: 4,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: MenuListTile(leading: const Icon(Remix.volume_up_line, size: 20), text: i18n("room_volume")),
                ),
                PopupMenuItem(
                  value: 5,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: MenuListTile(
                    leading: const Icon(Remix.link_m, size: 20),
                    text: i18n("toolbox_get_direct_link"),
                  ),
                ),
                PopupMenuItem(
                  value: 6,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: MenuListTile(
                    leading: const Icon(RemixIcons.share_forward_line, size: 20),
                    text: i18n("share"),
                  ),
                ),
                if (controller.localInteractionController.enabled.v)
                  PopupMenuItem(
                    value: 7,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: MenuListTile(
                      leading: const Icon(Icons.auto_awesome_rounded, size: 20),
                      text: i18n('local_interaction_title'),
                    ),
                  ),
                PopupMenuItem(
                  value: 8,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: MenuListTile(
                    leading: const Icon(Icons.picture_in_picture_alt_rounded, size: 20),
                    text: i18n("dual_view_title"),
                  ),
                ),
                PopupMenuItem(
                  value: 9,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: MenuListTile(
                    leading: const Icon(Icons.info_outline_rounded, size: 20),
                    text: i18n('room_info_osd'),
                    trailing: Obx(() {
                      final on = SettingsService.to.app.showRoomInfoOsd.v;
                      return Text(
                        on ? i18n('room_info_osd_on') : i18n('room_info_osd_off'),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: on ? Theme.of(context).colorScheme.primary : Theme.of(context).hintColor,
                            ),
                      );
                    }),
                  ),
                ),
                // 画面遮挡块（模糊框）：每个直播间最多三个，逐个开关；
                // 关掉只是隐藏，位置会记住，下次打开原样恢复。
                for (int slot = 0; slot < VideoMaskService.maxSlots; slot++)
                  PopupMenuItem(
                    value: 10 + slot,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Builder(
                      builder: (context) {
                        final maskRoom =
                            controller.state.value.room.detail ?? controller.room;
                        final on = VideoMaskService.instance.isVisible(
                          maskRoom.platform,
                          maskRoom.roomId,
                          slot,
                        );
                        return MenuListTile(
                          leading: Icon(
                            on ? Icons.blur_on_rounded : Icons.blur_linear_rounded,
                            size: 20,
                          ),
                          text: i18n('video_mask_slot', args: {'n': '${slot + 1}'}),
                          trailing: Text(
                            on ? i18n('video_mask_on') : i18n('video_mask_off'),
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: on ? Theme.of(context).colorScheme.primary : Theme.of(context).hintColor,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ];
            },
          ),
        ],
      ),
      body: Builder(
        builder: (BuildContext context) {
          return LayoutBuilder(
            builder: (context, constraint) {
              final width = Get.width;
              return SafeArea(
                child: width <= 680
                    ? Column(
                        children: <Widget>[
                          buildVideoPlayer(),
                          const ResolutionsRow(),
                          const Divider(height: 1),
                          Obx(() {
                            final state = controller.state.value;
                            if (!state.room.success) {
                              return const SizedBox.shrink();
                            }
                            final globalState = GlobalPlayerState.to;
                            if (globalState.isFullscreen.value || globalState.isWindowFullscreen.value) {
                              return const SizedBox.shrink();
                            }
                            return Expanded(child: DanmakuTabView(key: ValueKey(globalState.isFullscreen.value)));
                          }),
                        ],
                      )
                    : Row(
                        children: <Widget>[
                          Expanded(child: buildVideoPlayer()),
                          Obx(() {
                            final state = controller.state.value;
                            final detail = state.room.detail;
                            if (detail == null) {
                              return Container();
                            }

                            return SizedBox(
                              width: 400,
                              child: Column(
                                children: [
                                  const ResolutionsRow(),
                                  const Divider(height: 1),
                                  if (state.room.success) ...[
                                    Obx(() {
                                      final globalState = GlobalPlayerState.to;
                                      if (globalState.isFullscreen.value || globalState.isWindowFullscreen.value) {
                                        return const SizedBox.shrink();
                                      }
                                      return Expanded(
                                        child: DanmakuTabView(key: ValueKey(globalState.isFullscreen.value)),
                                      );
                                    }),
                                  ],
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
              );
            },
          );
        },
      ),
    );
  }

  void showDlnaCastDialog() {
    final detail = controller.state.value.room.detail;
    LiveUrlTool.castPlayUrlByRoomId(roomId: detail?.roomId ?? '', platform: detail?.platform ?? '');
  }

  /// 打开"双开/副窗口"的选择面板：挑一个房间作为副直播间显示在小窗中。
  void _openDualViewPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DualViewPickerSheet(
        onPicked: (room) {
          Navigator.of(ctx).pop();
          SecondaryPlayerService.instance.loadRoom(room);
        },
      ),
    );
  }

  Widget buildVideoPlayer() {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: Colors.black,
                child: Obx(() {
                  final state = controller.state.value;
                  final videoController = state.player.videoController;
                  if (state.room.success && videoController != null) {
                    return VideoPlayer(controller: videoController);
                  }
                  if (state.room.isLoading || state.room.isLiving) {
                    return buildLoading();
                  }
                  return NotLivingVideoWidget(controller: controller);
                }),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget buildLoading() {
    return const Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: Colors.black),
        AppStatusView(type: AppStatusType.loading, title: "", subtitle: "", iconColor: Colors.white, isMini: true),
      ],
    );
  }

  void showVolumeSettingsDialog(BuildContext context) {
    final RxBool tempMute = SettingsService.to.vol.globalVolumeMute.v.obs;
    final RxDouble tempMobileVol = SettingsService.to.vol.defaultMobileVolume.v.obs;
    final RxDouble tempDesktopVol = SettingsService.to.vol.defaultDesktopVolume.v.obs;

    showDialog(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: Text(i18n("room_volume")),
          content: Container(
            constraints: BoxConstraints(minWidth: PlatformUtils.isMobile ? Get.mediaQuery.size.width * 0.8 : 500),
            child: Obx(
              () => SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      title: Text(i18n("global_mute")),
                      secondary: Icon(
                        tempMute.value ? Icons.volume_off : Icons.volume_up,
                        color: tempMute.value ? theme.colorScheme.error : theme.colorScheme.primary,
                      ),
                      value: tempMute.value,
                      activeThumbColor: theme.colorScheme.primary,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (val) => tempMute.value = val,
                    ),
                    const Divider(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.phone_android, size: 20),
                            const SizedBox(width: 8),
                            Text(i18n("mobile_default_volume")),
                          ],
                        ),
                        Text(
                          "${(tempMobileVol.value * 100).toInt()}%",
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: tempMute.value ? theme.disabledColor : theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: tempMobileVol.value.clamp(0.0, 1.0),
                      min: 0.0,
                      max: 1.0,
                      onChanged: tempMute.value ? null : (val) => tempMobileVol.value = val,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.computer, size: 20),
                            const SizedBox(width: 8),
                            Text(i18n("desktop_default_volume")),
                          ],
                        ),
                        Text(
                          "${(tempDesktopVol.value * 100).toInt()}%",
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: tempMute.value ? theme.disabledColor : theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: tempDesktopVol.value.clamp(0.0, 1.0),
                      min: 0.0,
                      max: 1.0,
                      onChanged: tempMute.value ? null : (val) => tempDesktopVol.value = val,
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () {
                          tempMute.value = false;
                          tempMobileVol.value = 0.5;
                          tempDesktopVol.value = 1.0;
                        },
                        icon: const Icon(Icons.refresh, size: 18),
                        label: Text(i18n("reset_default")),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(i18n("cancel"))),
            FilledButton(
              onPressed: () {
                SettingsService.to.vol.globalVolumeMute.v = tempMute.value;
                SettingsService.to.vol.defaultMobileVolume.v = tempMobileVol.value.clamp(0.0, 1.0);
                SettingsService.to.vol.defaultDesktopVolume.v = tempDesktopVol.value.clamp(0.0, 1.0);
                final videoController = controller.state.value.player.videoController;
                if (tempMute.value) {
                  videoController?.setVolume(0.0);
                } else {
                  if (PlatformUtils.isMobile) {
                    videoController?.setVolume(tempMobileVol.value);
                  } else {
                    videoController?.setVolume(tempDesktopVol.value);
                  }
                }
                Navigator.pop(context);
              },
              child: Text(i18n("confirm")),
            ),
          ],
        );
      },
    );
  }

  void showTimerDialog(BuildContext context) {
    final durationController = TextEditingController(text: controller.state.value.ui.closeTimes.toString());
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(i18n('room_playback_timer')),
        content: Obx(() {
          final uiState = controller.state.value.ui;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                title: Text(i18n('room_playback_timer_enable')),
                subtitle: Text(i18n('room_playback_timer_desc')),
                contentPadding: EdgeInsets.zero,
                value: uiState.closeTimeFlag,
                activeThumbColor: Theme.of(context).colorScheme.primary,
                onChanged: (bool value) => controller.updateTimerFlag(value),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const [15, 30, 45, 60, 90, 120, 240, 480]
                    .map(
                      (minutes) => ActionChip(
                        label: Text('$minutes ${i18n('minutes')}'),
                        onPressed: () => durationController.text = minutes.toString(),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: durationController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: i18n('room_playback_timer_duration'),
                  suffixText: i18n('minutes'),
                  helperText: i18n('room_playback_timer_custom_hint'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          );
        }),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(i18n('cancel'))),
          FilledButton(
            onPressed: () {
              final minutes = int.tryParse(durationController.text.trim());
              if (minutes == null || minutes < 1 || minutes > AppSettingsController.maxSleepMinutes) {
                ToastUtil.show(i18n('room_playback_timer_custom_hint'));
                return;
              }
              controller.updateTimerTimes(minutes);
              controller.updateTimerFlag(true);
              Navigator.of(context).pop();
            },
            child: Text(i18n('start_timer')),
          ),
        ],
      ),
    ).whenComplete(durationController.dispose);
  }
}

class ResolutionsRow extends StatefulWidget {
  const ResolutionsRow({super.key});

  @override
  State<ResolutionsRow> createState() => _ResolutionsRowState();
}

class _ResolutionsRowState extends State<ResolutionsRow> {
  LivePlayController get controller => Get.find<LivePlayController>();

  Widget buildInfoCount() {
    return Obx(() {
      final room = controller.state.value.room.detail;
      if (room == null) return const SizedBox.shrink();
      final app = SettingsService.to.app;
      final type = room.audienceType(
        preferRealOnline: app.preferRealOnlineCounts.v,
        platformEnabled: app.isRealOnlineEnabledFor(room.platform),
      );
      final value = room.audienceValue(
        preferRealOnline: app.preferRealOnlineCounts.v,
        platformEnabled: app.isRealOnlineEnabledFor(room.platform),
      );
      final icon = switch (type) {
        AudienceMetricType.onlineViewers => Icons.people_alt_rounded,
        AudienceMetricType.totalViewers => Icons.visibility_rounded,
        AudienceMetricType.followers => Icons.favorite_rounded,
        _ => Icons.whatshot_rounded,
      };
      final label = i18n(switch (type) {
        AudienceMetricType.onlineViewers => 'audience_online',
        AudienceMetricType.totalViewers => 'audience_total',
        AudienceMetricType.followers => 'audience_followers',
        AudienceMetricType.popularity => 'audience_popularity',
        AudienceMetricType.unknown => 'audience_count',
      });
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 4),
          Text(
            '$label ${value.isEmpty ? i18n('audience_waiting') : readableCount(value)}',
            style: Get.textTheme.bodySmall,
          ),
        ],
      );
    });
  }

  Widget _buildResolutionSelector() {
    return Obx(() {
      final state = controller.state.value;
      if (!state.room.success || state.player.qualites.isEmpty) {
        return const SizedBox.shrink();
      }
      final currentIndex = state.player.currentQuality;
      final currentQualityName = state.player.qualites[currentIndex].quality;

      return PopupMenuButton<int>(
        tooltip: i18n('toolbox_select_quality'),
        color: Get.theme.colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        offset: const Offset(0.0, 5.0),
        onOpened: () {
          controller.updateUI(isMenuOpen: true);
        },
        onCanceled: () {
          controller.updateUI(isMenuOpen: false);
        },
        position: PopupMenuPosition.under,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Text(
            currentQualityName,
            style: Get.theme.textTheme.labelSmall?.copyWith(color: Get.theme.colorScheme.primary),
          ),
        ),
        onSelected: (newQualityIndex) {
          controller.updateUI(isMenuOpen: false);
          controller.setResolution(ReloadDataType.changeQuality, newQualityIndex, state.player.currentLineIndex);
        },
        itemBuilder: (context) {
          return List.generate(state.player.qualites.length, (index) {
            final qualityRate = state.player.qualites[index];
            final isSelected = index == currentIndex;
            return PopupMenuItem<int>(
              value: index,
              child: Text(
                qualityRate.quality,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: isSelected ? Get.theme.colorScheme.primary : null),
              ),
            );
          });
        },
      );
    });
  }

  Widget _buildLineSelector() {
    return Obx(() {
      final state = controller.state.value;
      if (!state.room.success || state.player.playUrls.isEmpty) {
        return const SizedBox.shrink();
      }
      final currentIndex = state.player.currentLineIndex;
      final currentLineName = i18n("toolbox_line", args: {"index": (currentIndex + 1).toString()});

      return PopupMenuButton<int>(
        tooltip: i18n("select_play_line"),
        color: Get.theme.colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        offset: const Offset(0.0, 5.0),
        onOpened: () {
          controller.updateUI(isMenuOpen: true);
        },
        onCanceled: () {
          controller.updateUI(isMenuOpen: false);
        },
        position: PopupMenuPosition.under,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Text(
            currentLineName,
            style: Get.theme.textTheme.labelSmall?.copyWith(color: Get.theme.colorScheme.primary),
          ),
        ),
        onSelected: (newLineIndex) {
          controller.updateUI(isMenuOpen: false);
          controller.setResolution(ReloadDataType.changeLine, state.player.currentQuality, newLineIndex);
        },
        itemBuilder: (context) {
          return List.generate(state.player.playUrls.length, (index) {
            final isSelected = index == currentIndex;
            return PopupMenuItem<int>(
              value: index,
              child: Text(
                i18n("toolbox_line", args: {"index": (index + 1).toString()}),
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: isSelected ? Get.theme.colorScheme.primary : null),
              ),
            );
          });
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final state = controller.state.value;
      if (!state.room.success) {
        return Container(height: 55);
      }
      return Container(
        height: 55,
        padding: const EdgeInsets.all(4.0),
        child: Row(
          children: [
            Padding(padding: const EdgeInsets.all(8), child: buildInfoCount()),
            const Spacer(),
            _buildResolutionSelector(),
            _buildLineSelector(),
          ],
        ),
      );
    });
  }
}

class FavoriteFloatingButton extends StatefulWidget {
  const FavoriteFloatingButton({super.key, required this.room, this.compact = false});

  final LiveRoom room;
  final bool compact;

  @override
  State<FavoriteFloatingButton> createState() => _FavoriteFloatingButtonState();
}

class _FavoriteFloatingButtonState extends State<FavoriteFloatingButton> {
  StreamSubscription<dynamic>? subscription;

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
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  Future<void> _toggleFavorite(bool isFavorite) async {
    if (!isFavorite) {
      SettingsService.to.fav.addRoom(widget.room);
      EventBus.instance.emit('changeFavorite', true);
      if (mounted) setState(() {});
      return;
    }

    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: Text(i18n("unfollow")),
        content: Text(i18n("unfollow_message", args: {"name": widget.room.nick ?? ''})),
        actions: [
          TextButton(onPressed: () => Navigator.of(Get.context!).pop(false), child: Text(i18n("cancel"))),
          ElevatedButton(onPressed: () => Navigator.of(Get.context!).pop(true), child: Text(i18n("confirm"))),
        ],
      ),
    );
    if (confirmed != true) return;

    SettingsService.to.fav.removeRoom(widget.room);
    EventBus.instance.emit('changeFavorite', true);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isFavorite = SettingsService.to.fav.isFavorite(widget.room);
    final label = i18n(isFavorite ? "followed" : "follow");
    if (widget.compact) {
      return Tooltip(
        message: label,
        child: IconButton.filledTonal(
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 40, height: 38),
          padding: EdgeInsets.zero,
          onPressed: () => _toggleFavorite(isFavorite),
          icon: Icon(isFavorite ? Remix.heart_3_fill : Remix.heart_3_line, size: 19),
        ),
      );
    }

    return isFavorite
        ? FilledButton(
            style: ButtonStyle(
              padding: Platform.isWindows
                  ? WidgetStateProperty.all(EdgeInsets.all(12.0))
                  : WidgetStateProperty.all(EdgeInsets.all(5.0)),
              backgroundColor: WidgetStateProperty.all(Get.theme.colorScheme.primary.withAlpha(125)),
              shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0))),
              textStyle: WidgetStateProperty.all(AppTextStyles.t12),
              minimumSize: WidgetStateProperty.all(Size.zero),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => _toggleFavorite(isFavorite),
            child: Text(label),
          )
        : FilledButton(
            style: ButtonStyle(
              padding: Platform.isWindows
                  ? WidgetStateProperty.all(EdgeInsets.all(12.0))
                  : WidgetStateProperty.all(EdgeInsets.all(5.0)),
              backgroundColor: WidgetStateProperty.all(Get.theme.colorScheme.primary),
              shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0))),
              textStyle: WidgetStateProperty.all(AppTextStyles.t12),
              minimumSize: WidgetStateProperty.all(Size.zero),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => _toggleFavorite(isFavorite),
            child: Text(label),
          );
  }
}

class NotLivingVideoWidget extends StatelessWidget {
  const NotLivingVideoWidget({super.key, required this.controller});

  final LivePlayController controller;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 55,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.transparent, Colors.black45],
              ),
            ),
            child: Row(
              children: [
                if (GlobalPlayerState.to.fullscreenUI)
                  GestureDetector(
                    onTap: () {
                      controller.setNormalScreen();
                      controller.markFullscreenExit();
                      GlobalPlayerState.to.isFullscreen.value = false;
                      GlobalPlayerState.to.isWindowFullscreen.value = false;
                      // 箭头路径同样要恢复竖屏与系统栏：
                      // 只翻标志位会让手机停留在横屏沉浸状态，看起来像"点了没反应"。
                      controller.state.value.player.videoController?.exitFullScreen();
                    },
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(12),
                      child: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      controller.room.title!,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.t14.copyWith(color: Colors.white, decoration: TextDecoration.none),
                    ),
                  ),
                ),
                if (GlobalPlayerState.to.fullscreenUI) ...[
                  IconButton(
                    icon: const Icon(Icons.swap_horiz_outlined),
                    tooltip: i18n('switch_live_room'),
                    color: Colors.white,
                    onPressed: () => Get.dialog(PlayOther(controller: Get.find<LivePlayController>())),
                  ),
                  const DatetimeInfo(),
                ],
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(i18n("play_video_failed"), style: AppTextStyles.t16.copyWith(color: Colors.white)),
                  ),
                  Text(i18n("room_offline"), style: const TextStyle(color: Colors.white)),
                  Text(i18n("switch_other_room_hint"), style: AppTextStyles.t14.copyWith(color: Colors.white)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 直播间信息悬浮层：展示平台/房间号/清晰度/分辨率/音频码率/内核。
class _RoomInfoOsd extends StatefulWidget {
  const _RoomInfoOsd({required this.controller});

  final LivePlayController controller;

  @override
  State<_RoomInfoOsd> createState() => _RoomInfoOsdState();
}

class _RoomInfoOsdState extends State<_RoomInfoOsd> {
  Timer? _timer;
  int? _width;
  int? _height;
  int? _lastBitrate;

  @override
  void initState() {
    super.initState();
    _sample();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _sample();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _sample() {
    int? width;
    int? height;
    int? audioBitrate;
    try {
      final player = GlobalPlayerService.instance.playerManager.currentPlayer;
      width = player?.videoWidth;
      height = player?.videoHeight;
      audioBitrate = player?.audioBitrateKbps;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _width = width;
      _height = height;
      _lastBitrate = audioBitrate;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state.value;
    final detail = state.room.detail;
    final theme = Theme.of(context);
    final quality = state.player.currentQuality >= 0 &&
            state.player.qualites.length > state.player.currentQuality
        ? state.player.qualites[state.player.currentQuality].quality
        : '';
    final bitrate = _lastBitrate;
    // 观看人数按平台口径展示（B站为人气值，其余为真实在线）
    final audience = detail == null
        ? ''
        : switch (detail.audienceMetricType ?? AudienceMetricType.unknown) {
            AudienceMetricType.totalViewers => detail.totalViewers ?? '',
            AudienceMetricType.onlineViewers => detail.onlineViewers ?? '',
            _ => (detail.watching?.isNotEmpty == true ? detail.watching : detail.popularity) ?? '',
          };
    final rows = <String, String>{
      i18n('osd_platform'): detail?.platform ?? '-',
      i18n('osd_room'): detail?.roomId ?? '-',
      i18n('osd_anchor'): detail?.nick?.isNotEmpty == true ? detail!.nick! : '-',
      i18n('osd_quality'): quality.isEmpty ? '-' : quality,
      i18n('osd_line'): '${state.player.currentLineIndex + 1}',
      i18n('osd_resolution'):
          _width != null && _height != null ? '$_width×$_height' : '-',
      i18n('osd_audio_bitrate'):
          (bitrate != null && bitrate > 0) ? '$bitrate kbps' : '-',
      if (audience.isNotEmpty) i18n('osd_online'): audience,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                i18n('room_info_osd'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              ...rows.entries.map(
                (entry) => Text(
                  '${entry.key}: ${entry.value}',
                  style: theme.textTheme.labelSmall?.copyWith(color: Colors.white, height: 1.5),
                ),
              ),
            ],
          ),
          // 面板内关闭按钮：无需再进菜单开关
          Positioned(
            top: 0,
            right: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => SettingsService.to.app.showRoomInfoOsd.v = false,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(Icons.close_rounded, size: 14, color: Colors.white70),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
