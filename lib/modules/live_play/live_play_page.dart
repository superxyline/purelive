import 'widgets/index.dart';
import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:pure_live/modules/live_play/live_play_controller.dart';

class LivePlayPage extends GetWidget<LivePlayController> {
  LivePlayPage({super.key});

  final SettingsService settings = Get.find<SettingsService>();
  Future<bool> onWillPop() async {
    try {
      var exit = await controller.onBackPressed();
      if (exit) {
        Get.back();
      }
    } catch (e) {
      Get.back();
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (settings.enableScreenKeepOn.value) {
      WakelockPlus.toggle(enable: settings.enableScreenKeepOn.value);
    }
    return BackButtonListener(
      onBackButtonPressed: onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: Obx(() => controller.getVideoSuccess.value
              ? Row(children: [
                  CircleAvatar(
                    foregroundImage: controller.detail.value == null && controller.detail.value!.avatar!.isEmpty
                        ? null
                        : NetworkImage(controller.detail.value!.avatar!),
                    radius: 13,
                    backgroundColor: Theme.of(context).disabledColor,
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        controller.detail.value == null && controller.detail.value!.nick == null
                            ? ''
                            : controller.detail.value!.nick!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      if (controller.detail.value != null && controller.detail.value!.area != null)
                        Text(
                          controller.detail.value!.area!.isEmpty
                              ? controller.detail.value!.platform!.toUpperCase()
                              : "${controller.detail.value!.platform!.toUpperCase()} / ${controller.detail.value!.area}",
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 8),
                        ),
                    ],
                  ),
                ])
              : Row(children: [
                  CircleAvatar(
                    foregroundImage: controller.currentPlayRoom.value.avatar == null
                        ? null
                        : NetworkImage(controller.currentPlayRoom.value.avatar!),
                    radius: 13,
                    backgroundColor: Theme.of(context).disabledColor,
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        controller.detail.value!.nick!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      Text(
                        controller.currentPlayRoom.value.area!.isEmpty
                            ? controller.currentPlayRoom.value.platform!.toUpperCase()
                            : "${controller.currentPlayRoom.value.platform!.toUpperCase()} / ${controller.currentPlayRoom.value.area}",
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 8),
                      ),
                    ],
                  ),
                ])),
          actions: [
            PopupMenuButton(
              tooltip: '搜索',
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
                  const PopupMenuItem(
                    value: 0,
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: MenuListTile(
                      leading: Icon(Icons.open_in_new_rounded),
                      text: "打开直播间",
                    ),
                  ),
                  const PopupMenuItem(
                    value: 1,
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: MenuListTile(
                      leading: Icon(Icons.live_tv_rounded),
                      text: "投屏",
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
                                  room: controller.detail.value!,
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
                                    room: controller.detail.value!,
                                  )),
                            ),
                          ]),
                        ),
                      ]),
              );
            });
          },
        ),
        floatingActionButton: Obx(() => controller.getVideoSuccess.value
            ? FavoriteFloatingButton(room: controller.currentPlayRoom.value)
            : FavoriteFloatingButton(room: controller.currentPlayRoom.value)),
      ),
    );
  }

  void showDlnaCastDialog() {
    Get.dialog(LiveDlnaPage(datasource: controller.playUrls[controller.currentLineIndex.value]));
  }

  Widget buildVideoPlayer() {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        color: Colors.black,
        child: Obx(
          () => controller.success.value
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
                          child: Obx(() => controller.isFirstLoad.value
                              ? const Center(
                                  child: CircularProgressIndicator(
                                  color: Colors.white,
                                ))
                              : controller.loadTimeOut.value
                                  ? CachedNetworkImage(
                                      imageUrl: controller.currentPlayRoom.value.cover!,
                                      cacheManager: CustomCacheManager.instance,
                                      fit: BoxFit.fill,
                                      errorWidget: (context, error, stackTrace) => const Center(
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
                                      ),
                                    )
                                  : TimeOutVideoWidget(
                                      controller: controller,
                                    )),
                        ),
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
    // controller.detail.value! watching or followers
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.whatshot_rounded, size: 14),
      const SizedBox(width: 4),
      Text(
        readableCount(controller.detail.value!.watching!),
        style: Get.textTheme.bodySmall,
      ),
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
                  color: rate.quality == controller.qualites[controller.currentQuality.value].quality
                      ? Get.theme.colorScheme.primary
                      : null,
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
                      '线路${i + 1}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: urls[i] == controller.playUrls[controller.currentLineIndex.value]
                                ? Get.theme.colorScheme.primary
                                : null,
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
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: buildInfoCount(),
            ),
            const Spacer(),
            ...controller.success.value ? buildResultionsList() : [],
          ],
        ),
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
  final settings = Get.find<SettingsService>();

  late bool isFavorite = settings.isFavorite(widget.room);

  @override
  Widget build(BuildContext context) {
    return isFavorite
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
                      onPressed: () => Get.back(result: false),
                      child: Text(S.of(context).cancel),
                    ),
                    ElevatedButton(
                      onPressed: () => Get.back(result: true),
                      child: Text(S.of(context).confirm),
                    ),
                  ],
                ),
              ).then((value) {
                if (value) {
                  setState(() => isFavorite = !isFavorite);
                  settings.removeRoom(widget.room);
                }
              });
            },
            child: CircleAvatar(
              foregroundImage: (widget.room.avatar == '') ? null : NetworkImage(widget.room.avatar!),
              radius: 18,
              backgroundColor: Theme.of(context).disabledColor,
            ),
          )
        : FloatingActionButton.extended(
            elevation: 2,
            backgroundColor: Theme.of(context).cardColor,
            onPressed: () {
              setState(() => isFavorite = !isFavorite);
              settings.addRoom(widget.room);
            },
            icon: CircleAvatar(
              foregroundImage: (widget.room.avatar == '') ? null : NetworkImage(widget.room.avatar!),
              radius: 18,
              backgroundColor: Theme.of(context).disabledColor,
            ),
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
          );
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
                    '${controller.currentPlayRoom.value.platform == Sites.iptvSite ? controller.currentPlayRoom.value.title : controller.currentPlayRoom.value.nick ?? ''}',
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
                    '${controller.currentPlayRoom.value.platform == Sites.iptvSite ? controller.currentPlayRoom.value.title : controller.currentPlayRoom.value.nick ?? ''}',
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
