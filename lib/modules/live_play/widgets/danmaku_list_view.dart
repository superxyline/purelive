import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/live_play/live_play_controller.dart';
import 'package:pure_live/modules/util/danmu_util.dart';
import 'package:pure_live/plugins/extension/string_extension.dart';

class DanmakuListView extends StatefulWidget {
  final LiveRoom room;

  const DanmakuListView({super.key, required this.room});

  @override
  State<DanmakuListView> createState() => DanmakuListViewState();
}

class DanmakuListViewState extends State<DanmakuListView> with AutomaticKeepAliveClientMixin<DanmakuListView> {
  final ScrollController _scrollController = ScrollController();
  bool _scrollHappen = false;

  LivePlayController get controller => Get.find<LivePlayController>();
  final List<StreamSubscription> listenList = [];
  final List<Worker> workerList = [];

  // final Lock lock = Lock();
  @override
  void initState() {
    super.initState();
    workerList.add(debounce(controller.messages, (callback) async {
      await _scrollToBottom();
    }, time: 1300.milliseconds));
    // listenList.add(controller.messages.listen((p0) {
    //   _scrollToBottom();
    // }));
  }

  @override
  void dispose() {
    listenList.map((e) async => await e.cancel());
    listenList.clear();
    workerList.map((e) => e.dispose());
    workerList.clear();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _scrollToBottom() async {
    if (_scrollHappen) return;

    /// 没有全屏时，才滚动
    if (_scrollController.hasClients && !controller.isFullscreen.value) {
      await _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 1000),
        curve: Curves.linearToEaseOut,
      );
      // setState(() {});
    }
  }

  bool _userScrollAction(UserScrollNotification notification) {
    if (notification.direction == ScrollDirection.forward) {
      setState(() => _scrollHappen = true);
    } else if (notification.direction == ScrollDirection.reverse) {
      final pos = _scrollController.position;
      if (pos.maxScrollExtent - pos.pixels <= 100) {
        setState(() => _scrollHappen = false);
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Obx(() => Visibility(
        visible: controller.videoController?.videoPlayer.isFullscreen.value != true,
        child: Stack(
          children: [
            NotificationListener<UserScrollNotification>(
              onNotification: _userScrollAction,
              child: ListView.builder(
                controller: _scrollController,

                /// 只显示 100 条弹幕
                itemCount: (controller.messages.length > 100 ? 100 : controller.messages.length),
                shrinkWrap: true,
                itemBuilder: (context, index) {
                  var partIndex = controller.messages.length > 100 ? controller.messages.length - 100 : 0;
                  var sIndex = partIndex + index;
                  final danmaku = controller.messages[sIndex];
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            /// 弹幕的用户等级
                            if (danmaku.userLevel.isNotNullOrEmpty && danmaku.userLevel != "0")
                              WidgetSpan(
                                child: IntrinsicWidth(
                                    child: Container(
                                  decoration: BoxDecoration(
                                    color: DanmuUtil.getUserLevelColor(danmaku.userLevel),
                                    borderRadius: BorderRadius.circular(12.0), // 设置圆角半径
                                  ),
                                  // height: 18,
                                  // width: 36,
                                  alignment: Alignment.center,
                                  // 居中的子Widget
                                  // padding: EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                                  margin: EdgeInsets.only(right: 4),
                                  child: Row(children: [
                                    Padding(padding: EdgeInsets.all(3)),
                                    Text(
                                      "${danmaku.userLevel}",
                                      textAlign: TextAlign.center, // 居中的子Widget
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w200,
                                      ),
                                    ),
                                    Padding(padding: EdgeInsets.all(3)),
                                  ]),
                                )),
                              ),
                            // ),

                            /// 弹幕的粉丝牌
                            if (danmaku.fansName.isNotNullOrEmpty && danmaku.fansLevel.isNotNullOrEmpty && danmaku.fansLevel != "0")
                              WidgetSpan(
                                child:
                                    // Expanded( child:
                                    IntrinsicWidth(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: DanmuUtil.getFansLevelColor(danmaku.fansLevel),
                                      borderRadius: BorderRadius.circular(5.0), // 设置圆角半径
                                    ),
                                    // height: 18,
                                    // width: 80,
                                    alignment: Alignment.center,
                                    // 居中的子Widget
                                    // padding: EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                                    margin: EdgeInsets.only(right: 4),
                                    child: Row(
                                      children: [
                                        Padding(padding: EdgeInsets.all(1)),
                                        /// 弹幕的粉丝牌
                                        Text(
                                          "${danmaku.fansName}",
                                          textAlign: TextAlign.center, // 居中的子Widget
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w200,
                                          ),
                                        ),
                                        Padding(padding: EdgeInsets.all(1)),

                                        /// 弹幕的粉丝牌等级
                                        Expanded(
                                            child: CircleAvatar(
                                          radius: 8.0, // 圆的半径
                                          backgroundColor: Colors.white70, // 圆的背景颜色
                                          child: Text(
                                            "${danmaku.fansLevel}",
                                            textAlign: TextAlign.right, // 居中的子Widget
                                            style: TextStyle(
                                              color: DanmuUtil.getFansLevelColor(danmaku.fansLevel),
                                              fontSize: 8,
                                              fontWeight: FontWeight.w200,
                                            ),
                                          ),
                                        )),
                                        Padding(padding: EdgeInsets.all(1)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            // ),

                            /// 弹幕的用户名
                            TextSpan(
                              text: "${danmaku.userName}: ",
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 14,
                                fontWeight: FontWeight.w200,
                              ),
                            ),

                            /// 弹幕主体部分
                            TextSpan(
                              text: danmaku.message,
                              style: TextStyle(fontSize: 14, color: danmaku.color != Colors.white ? danmaku.color : null),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_scrollHappen)
              Positioned(
                left: 12,
                bottom: 12,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.arrow_downward_rounded),
                  label: const Text('回到底部'),
                  onPressed: () {
                    setState(() => _scrollHappen = false);
                    _scrollToBottom();
                  },
                ),
              )
          ],
        )));
  }

  @override
  bool get wantKeepAlive => false;
}
