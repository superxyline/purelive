import 'dart:io';

import 'package:floating/floating.dart';
import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/core/common/core_log.dart';
import 'package:pure_live/modules/areas/areas_list_controller.dart';
import 'package:pure_live/modules/live_play/live_play_controller.dart';
import 'package:pure_live/modules/util/site_logo_widget.dart';
import 'package:pure_live/plugins/cache_network.dart';
import 'package:pure_live/plugins/extension/string_extension.dart';
import 'package:pure_live/routes/app_navigation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'widgets/index.dart';

class LivePlayPage extends GetView<LivePlayController> {
  LivePlayPage({super.key});

  final SettingsService settings = Get.find<SettingsService>();

  Future<bool> onWillPop() async {
    try {
      var exit = await controller.onBackPressed();
      if (exit) {
        Navigator.of(Get.context!).pop();
      }
    } catch (e) {
      CoreLog.error(e);
      Navigator.of(Get.context!).pop();
    }
    return true;
  }

  /// 顶部左边的UI
  buildTableTarLeft() {
    return Row(children: [
      /// 头像
      CacheNetWorkUtils.getCircleAvatar(controller.liveRoomRx.avatar.value, radius: 20),
      const SizedBox(width: 8),

      /// 右边
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /// 名称
          Text(
            controller.liveRoomRx.nick.value.appendTxt(""),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(Get.context!).textTheme.labelSmall,
          ),

          /// 所属站点
          Row(
            /// 横着摆放
            children: [
              /// 站点logo
              if (controller.liveRoomRx.platform.value.isNotNullOrEmpty) SiteWidget.getSiteLogeImage(controller.liveRoomRx.platform.value!)!,

              /// 站点logo
              const SizedBox(width: 5),
              if (controller.liveRoomRx.platform.value.isNotNullOrEmpty)
                TextButton(
                    style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        elevation: 0,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        minimumSize: Size.square(10),
                        side: BorderSide(
                          width: 0,
                          style: BorderStyle.none,
                          strokeAlign: 0,
                          color: Colors.grey.withOpacity(0.1),
                        ),
                        textStyle: Theme.of(Get.context!).textTheme.labelSmall,
                        shape: RoundedRectangleBorder(
                          side: BorderSide(
                            width: 0,
                            style: BorderStyle.none,
                            strokeAlign: 0,
                            color: Colors.grey.withOpacity(0.1),
                          ),
                          borderRadius: BorderRadius.circular(8),
                        )),
                    onPressed: () async {
                      if (!controller.liveRoomRx.area.value.isNullOrEmpty && !controller.liveRoomRx.platform.value.isNullOrEmpty) {
                        try {
                          /// 平台
                          var site = controller.liveRoomRx.platform.value!;
                          // CoreLog.d("site: $site");
                          var areasListController = Get.findOrNull<AreasListController>(tag: site);
                          if (areasListController == null) {
                            return;
                          }
                          var list = areasListController.list;
                          // CoreLog.d("list: $list");
                          if (list.isEmpty) {
                            CoreLog.d("loading areasList Data ...");
                            await areasListController.loadData();
                          }

                          /// 类别
                          var area = controller.liveRoomRx.area.value!;
                          LiveArea? liveArea;
                          bool flag = false;
                          for (var i = 0; i < list.length && !flag; i++) {
                            var liveCategory = list[i];
                            for (var j = 0; j < liveCategory.children.length && !flag; j++) {
                              var tmpLiveArea = liveCategory.children[j];
                              if (tmpLiveArea.areaName == area) {
                                liveArea = tmpLiveArea;
                                flag = true;
                                break;
                              }
                            }
                          }
                          if (liveArea == null) {
                            CoreLog.w("Not Find ${site}/${area}");
                            return;
                          }
                          Navigator.pop(Get.context!);
                          AppNavigator.toCategoryDetail(site: Sites.of(site), category: liveArea);
                        } catch (e) {
                          CoreLog.error(e);
                        }
                      }
                    },
                    child: Text(
                      "${Sites.of(controller.liveRoomRx.platform.value!).name}${controller.liveRoomRx.area.value.isNullOrEmpty ? '' : "/${controller.liveRoomRx.area.value}"}",
                      style: Theme.of(Get.context!).textTheme.labelSmall,
                    )),
            ],
          ),
        ],
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (settings.enableScreenKeepOn.value) {
      WakelockPlus.toggle(enable: settings.enableScreenKeepOn.value);
    }
    final page = Obx(() {
      CoreLog.d("isFullscreen.value ${controller.isFullscreen.value}");
      if (controller.isFullscreen.value == true) {
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            controller.videoController?.exitFull();
          },
          child: Scaffold(
            body: buildVideoPlayerBody(),
          ),
        );
      }
      return BackButtonListener(
        onBackButtonPressed: onWillPop,
        child: Scaffold(
          appBar: AppBar(
            title: Obx(() => buildTableTarLeft()),
            actions: [
              PopupMenuButton(
                tooltip: S.of(context).search,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                offset: const Offset(12, 0),
                position: PopupMenuPosition.under,
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (int index) {
                  if (index == 0) {
                    controller.openNaviteAPP();
                  } else {
                    showDlnaCastDialog();
                  }
                },
                itemBuilder: (BuildContext context) {
                  return [
                    PopupMenuItem(
                      value: 0,
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: MenuListTile(
                        leading: Icon(Icons.open_in_new_rounded),
                        text: S.of(context).live_room_open_external,
                      ),
                    ),
                    PopupMenuItem(
                      value: 1,
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: MenuListTile(
                        leading: Icon(Icons.live_tv_rounded),
                        text: S.of(context).screen_caste,
                      ),
                    ),
                  ];
                },
              )
            ],
          ),
          body: Builder(
            builder: (BuildContext context) {
              return LayoutBuilder(builder: (context, constraint) {
                final width = Get.width;
                return SafeArea(
                  child: width <= 680
                      ? Column(
                          children: <Widget>[
                            buildVideoPlayer(),
                            const ResolutionsRow(),
                            const Divider(height: 1),
                            Expanded(
                              child: Obx(() => DanmakuListView(
                                    key: controller.danmakuViewKey,
                                    room: controller.liveRoomRx.toLiveRoom(),
                                  )),
                            ),
                          ],
                        )
                      : Row(children: <Widget>[
                          Flexible(
                            flex: 5,
                            child: buildVideoPlayer(),
                          ),
                          Flexible(
                            flex: 3,
                            child: Column(children: [
                              const ResolutionsRow(),
                              const Divider(height: 1),
                              Expanded(
                                child: Obx(() => DanmakuListView(
                                      key: controller.danmakuViewKey,
                                      room: controller.liveRoomRx.toLiveRoom(),
                                    )),
                              ),
                            ]),
                          ),
                        ]),
                );
              });
            },
          ),
          floatingActionButton: Obx(() => controller.getVideoSuccess.value ? FavoriteFloatingButton(room: controller.liveRoomRx.toLiveRoom()) : FavoriteFloatingButton(room: controller.liveRoomRx.toLiveRoom())),
        ),
      );
    });
    if (!Platform.isAndroid) {
      return page;
    }
    return PiPSwitcher(
      floating: controller.pip,
      childWhenDisabled: page,
      childWhenEnabled: buildVideoPlayer(),
    );
  }

  void showDlnaCastDialog() {
    Get.dialog(LiveDlnaPage(datasource: controller.playUrls[controller.currentLineIndex.value]));
  }

  /// 播放器主页UI
  Widget buildVideoPlayer() {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: buildVideoPlayerBody(),
    );
  }

  /// 播放器主体内容
  Widget buildVideoPlayerBody() {
    return Container(
      color: Colors.black,
      child: Obx(
        () => /*controller.isLoadingVideo.value
              ? const Center(
                /// 加载动画
                child: CircularProgressIndicator(
                color: Colors.white,
              ))
              :*/
            controller.success.value
                ? VideoPlayer(controller: controller.videoController!)
                : controller.hasError.value && controller.isActive.value == false
                    ? ErrorVideoWidget(controller: controller)
                    : !controller.getVideoSuccess.value
                        ? ErrorVideoWidget(controller: controller)
                        : Card(
                            elevation: 0,
                            margin: const EdgeInsets.all(0),
                            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                            clipBehavior: Clip.antiAlias,
                            color: Get.theme.focusColor,
                            child: Obx(() => controller.isLoadingVideo.value
                                ? const Center(
                                    child: CircularProgressIndicator(
                                    color: Colors.white,
                                  ))
                                : controller.loadTimeOut.value
                                    ? const Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.live_tv_rounded, size: 48),
                                            Text(
                                              "无法获取播放信息",
                                              style: TextStyle(color: Colors.white, fontSize: 18),
                                            ),
                                            Text(
                                              "当前房间未开播或无法观看",
                                              style: TextStyle(color: Colors.white, fontSize: 18),
                                            ),
                                            Text(
                                              "请按确定按钮刷新重试",
                                              style: TextStyle(color: Colors.white, fontSize: 18),
                                            ),
                                          ],
                                        ),
                                      )
                                    : TimeOutVideoWidget(
                                        controller: controller,
                                      )),
                          ),
      ),
    );
  }
}

class ResolutionsRow extends StatefulWidget {
  const ResolutionsRow({super.key});

  @override
  State<ResolutionsRow> createState() => _ResolutionsRowState();
}

class _ResolutionsRowState extends State<ResolutionsRow> {
  LivePlayController get controller => Get.find();

  Widget buildInfoCount() {
    // controller.liveRoomRx watching or followers
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.whatshot_rounded, size: 14),
      const SizedBox(width: 4),
      Obx(() => Text(
            readableCount(readableCountStrToNum(controller.liveRoomRx.watching.value).toString()),
            style: Get.textTheme.bodySmall,
          )),
    ]);
  }

  List<Widget> buildResultionsList() {
    return controller.qualites
        .map<Widget>((rate) => PopupMenuButton(
              tooltip: rate.quality,
              color: Get.theme.colorScheme.surfaceContainerHighest,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              offset: const Offset(0.0, 5.0),
              position: PopupMenuPosition.under,
              icon: Text(
                rate.quality,
                style: Get.theme.textTheme.labelSmall?.copyWith(
                  color: rate.quality == controller.qualites[controller.currentQuality.value].quality ? Get.theme.colorScheme.primary : null,
                ),
              ),
              onSelected: (String index) {
                controller.setResolution(rate.quality, index);
              },
              itemBuilder: (context) {
                final items = <PopupMenuItem<String>>[];
                final urls = controller.playUrls;
                for (int i = 0; i < urls.length; i++) {
                  items.add(PopupMenuItem<String>(
                    value: i.toString(),
                    child: Text(
                      '线路${i + 1}\t${urls[i].contains(".flv") ? "FLV" : "HLS"}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: urls[i] == controller.playUrls[controller.currentLineIndex.value] ? Get.theme.colorScheme.primary : null,
                          ),
                    ),
                  ));
                }
                return items;
              },
            ))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Container(
        height: 55,
        padding: const EdgeInsets.all(4.0),
        child: ListView(scrollDirection: Axis.horizontal, children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: buildInfoCount(),
          ),
          ...buildResultionsList(),
        ]),
      ),
    );
  }
}

class FavoriteFloatingButton extends StatefulWidget {
  const FavoriteFloatingButton({
    super.key,
    required this.room,
  });

  final LiveRoom room;

  @override
  State<FavoriteFloatingButton> createState() => _FavoriteFloatingButtonState();
}

class _FavoriteFloatingButtonState extends State<FavoriteFloatingButton> {
  LivePlayController get controller => Get.find();

  @override
  Widget build(BuildContext context) {
    final settings = Get.find<SettingsService>();
    // late bool isFavorite = settings.isFavorite(widget.room);
    return Obx(() => controller.isFavorite.value
        ? FloatingActionButton(
            elevation: 2,
            backgroundColor: Theme.of(context).cardColor,
            tooltip: S.of(context).unfollow,
            onPressed: () {
              Get.dialog(
                AlertDialog(
                  title: Text(S.of(context).unfollow),
                  content: Text(S.of(context).unfollow_message(widget.room.nick!)),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(Get.context!).pop(false);
                      },
                      child: Text(S.of(context).cancel),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(Get.context!).pop(true);
                      },
                      child: Text(S.of(context).confirm),
                    ),
                  ],
                ),
              ).then((value) {
                if (value == true) {
                  controller.isFavorite.value = !controller.isFavorite.value;
                  // setState(() => controller.isFavorite.toggle);
                  settings.removeRoom(widget.room);
                }
              });
            },
            child: CacheNetWorkUtils.getCircleAvatar(widget.room.avatar, radius: 18),
          )
        : FloatingActionButton.extended(
            elevation: 2,
            backgroundColor: Theme.of(context).cardColor,
            onPressed: () {
              controller.isFavorite.value = !controller.isFavorite.value;
              // setState(() => controller.isFavorite.toggle);
              settings.addRoom(widget.room);
            },
            icon: CacheNetWorkUtils.getCircleAvatar(widget.room.avatar, radius: 18),
            label: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.of(context).follow,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  widget.room.nick!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ));
  }
}

class ErrorVideoWidget extends StatelessWidget {
  const ErrorVideoWidget({super.key, required this.controller});

  final LivePlayController controller;

  @override
  Widget build(BuildContext context) {
    return Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Obx(() => Text(
                    '${controller.liveRoomRx.platform.value == Sites.iptvSite ? controller.liveRoomRx.title.value : controller.liveRoomRx.nick.value ?? ''}',
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  )),
            ),
            Expanded(
              child: Center(
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
                    const Text(
                      "所有线路已切换且无法播放",
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    const Text(
                      "请切换播放器或设置解码方式刷新重试",
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    const Text(
                      "如仍有问题可能该房间未开播或无法观看",
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    )
                  ],
                ),
              ),
            ),
          ],
        ));
  }
}

class TimeOutVideoWidget extends StatelessWidget {
  const TimeOutVideoWidget({super.key, required this.controller});

  final LivePlayController controller;

  @override
  Widget build(BuildContext context) {
    return Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Obx(() => Text(
                    '${controller.liveRoomRx.platform.value == Sites.iptvSite ? controller.liveRoomRx.title.value : controller.liveRoomRx.nick.value ?? ''}',
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  )),
            ),
            Expanded(
              child: Center(
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
                    const Text(
                      "该房间未开播或已下播",
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    const Text(
                      "请刷新或者切换其他直播间进行观看吧",
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ));
  }
}
