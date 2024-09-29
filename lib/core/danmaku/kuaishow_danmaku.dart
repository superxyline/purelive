import 'dart:async';
import 'dart:developer';
import 'dart:math' as math;

import 'package:fixnum/src/int64.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/core/common/core_log.dart';
import 'package:pure_live/core/common/web_socket_util.dart';
import 'package:pure_live/core/interface/live_danmaku.dart';
import 'package:pure_live/core/site/kuaishou_site.dart';
import 'package:pure_live/plugins/fake_useragent.dart';

import 'kuaishou/ks.pb.dart';
// ignore_for_file: no_leading_underscores_for_local_identifiers

class KuaishowDanmakuArgs {
  String url;
  String token;
  String liveStreamId;
  String expTag;

  KuaishowDanmakuArgs({
    required this.url,
    required this.token,
    required this.liveStreamId,
    required this.expTag,
  });

  KuaishowDanmakuArgs.fromJson(Map<String, dynamic> json)
      : url = json['url'] ?? '',
        token = json['token'] ?? '',
        liveStreamId = json['liveStreamId'] ?? '',
        expTag = json['expTag'] ?? '';

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'url': url,
      'token': token,
      'liveStreamId': liveStreamId,
      'expTag': expTag,
    };
  }
}

class KuaishowDanmaku implements LiveDanmaku {
  @override
  int heartbeatTime = 20 * 1000;

  @override
  Function(LiveMessage msg)? onMessage;
  @override
  Function(String msg)? onClose;
  @override
  Function()? onReady;
  String serverUrl = "wss://cdnws.api.huya.com";

  WebScoketUtils? webScoketUtils;
  late KuaishowDanmakuArgs danmakuArgs;

  @override
  Future start(dynamic args) async {
    log("start", name: runtimeType.toString());
    if (args == null) {
      onClose?.call("服务器连接失败");
      return;
    }
    danmakuArgs = args as KuaishowDanmakuArgs;
    var kuaishouSite = Sites.of(Sites.kuaishouSite);
    var kuaishowSite = kuaishouSite.liveSite as KuaishowSite;
    kuaishowSite.headers['cookie'] = kuaishowSite.cookie;
    var mHeaders = kuaishowSite.headers;
    var fakeUseragent = FakeUserAgent.getRandomUserAgent();
    mHeaders['User-Agent'] = fakeUseragent['userAgent'];
    mHeaders['sec-ch-ua'] =
        'Google Chrome;v=${fakeUseragent['v']}, Chromium;v=${fakeUseragent['v']}, Not=A?Brand;v=24';
    mHeaders['sec-ch-ua-platform'] = fakeUseragent['device'];
    mHeaders['sec-fetch-dest'] = 'document';
    mHeaders['sec-fetch-mode'] = 'navigate';
    mHeaders['sec-fetch-site'] = 'same-origin';
    mHeaders['sec-fetch-user'] = '?1';
    mHeaders['accept'] =
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9';
    webScoketUtils = WebScoketUtils(
      url: danmakuArgs.url,
      heartBeatTime: heartbeatTime,
      headers: mHeaders,
      onMessage: (e) {
        decodeMessage(e);
      },
      onReady: () {
        onReady?.call();
        joinRoom(danmakuArgs);
      },
      onHeartBeat: () {
        heartbeat();
      },
      onReconnect: () {
        onClose?.call("与服务器断开连接，正在尝试重连");
      },
      onClose: (e) {
        onClose?.call("服务器连接失败$e");
      },
    );
    webScoketUtils?.connect();
  }

  void joinRoom(joinData) {
    danmakuArgs = joinData as KuaishowDanmakuArgs;
    var csWebEnterRoom = CSWebEnterRoom();
    var payload = CSWebEnterRoom_Payload();
    payload.liveStreamId = danmakuArgs.liveStreamId;
    payload.token = danmakuArgs.token;
    payload.expTag = danmakuArgs.expTag;

    /// 设置 pageId
    var charset =
        "bjectSymhasOwnProp-0123456789ABCDEFGHIJKLMNQRTUVWXYZ_dfgiklquvxz";
    var splits = charset.split("");
    var pageId = "";
    for (var i = 0; i < 16; i++) {
      pageId += splits[math.Random().nextInt(splits.length)];
    }
    var dateTime = DateTime.now().millisecondsSinceEpoch;
    pageId += "_$dateTime";

    payload.pageId = pageId;
    csWebEnterRoom.payloadType =
        Int64.parseInt(PayloadType.CS_ENTER_ROOM.value.toString());
    csWebEnterRoom.payload = payload;
    webScoketUtils?.sendMessage(csWebEnterRoom.writeToBuffer());
  }

  @override
  void heartbeat() {
    var csWebHeartbeat = CSWebHeartbeat();
    var csWebHeartbeatPayload = CSWebHeartbeat_Payload();
    csWebHeartbeatPayload.timestamp =
        Int64.parseInt(DateTime.now().millisecondsSinceEpoch.toString());
    csWebHeartbeat.payloadType =
        Int64.parseInt(PayloadType.CS_HEARTBEAT.value.toString());
    csWebHeartbeat.payload = csWebHeartbeatPayload;
    webScoketUtils?.sendMessage(csWebHeartbeat.writeToBuffer());
  }

  @override
  Future stop() async {
    onMessage = null;
    onClose = null;
    webScoketUtils?.close();
  }

  int strToNum(String? str) {
    if (str == null || str == "") {
      return 0;
    }
    var ratio = 1;
    var tmp = str;
    // 倍率
    if (tmp.contains("百")) {
      ratio *= 100;
      tmp = tmp.replaceFirst("百", "");
    }
    if (tmp.contains("千")) {
      ratio *= 1000;
      tmp = tmp.replaceFirst("千", "");
    }
    if (tmp.contains("万")) {
      ratio *= 10000;
      tmp = tmp.replaceFirst("万", "");
    }
    if (tmp.contains("亿")) {
      ratio *= 100000000;
      tmp = tmp.replaceFirst("亿", "");
    }
    tmp = tmp.replaceAll("+", "").replaceAll("-", "");
    var firstMatch = RegExp(r"(\d+(\.\d+)?)").firstMatch(tmp)?.group(1);

    if (firstMatch == null) {
      CoreLog.w("no match for '$tmp' to num");
      return 0;
    }
    var parse = double.parse(firstMatch);
    var num = (parse * ratio).floor();
    return num;
  }

  void decodeMessage(List<int> data) {
    var socketMessage = SocketMessage.fromBuffer(data);
    // var compressionType = socketMessage.compressionType;

    PayloadType payloadType = socketMessage.payloadType;
    // SC_FEED_PUSH 只获取推送信息
    if (payloadType != PayloadType.SC_FEED_PUSH) {
      return;
    }
    var payload = socketMessage.payload;
    var scWebFeedPush = SCWebFeedPush.fromBuffer(payload);
    // log(scWebFeedPush.toString(), name: runtimeType.toString());
    // 在线人数
    //    displayWatchingCount: 3.5万
    //    displayLikeCount: 14.7万
    var displayWatchingCount = scWebFeedPush.displayWatchingCount;
    var displayLikeCount = scWebFeedPush.displayLikeCount;
    var commentFeeds = scWebFeedPush.commentFeeds;

    var online = strToNum(displayWatchingCount);
    var likeCount = strToNum(displayLikeCount);
    // CoreLog.d("online num:  $online \t likeCount num:  $likeCount");

    onMessage?.call(
      LiveMessage(
        type: LiveMessageType.online,
        data: online,
        color: LiveMessageColor.white,
        message: "",
        userName: "",
      ),
    );

    for (var commentFeed in commentFeeds) {
      var user = commentFeed.user;
      var userName = user.userName;
      var color = commentFeed.color;
      var content = commentFeed.content;
      // 赞了这个直播
      var showType = commentFeed.showType;
      if (showType != WebCommentFeedShowType.FEED_SHOW_NORMAL) {
        continue;
      }
      // log(commentFeed.toString(), name: runtimeType.toString());
      // log("color: $color", name: runtimeType.toString());
      // color: #FF8BA7
      var messageColor = LiveMessageColor.hexToColor(color);
      onMessage?.call(LiveMessage(
        type: LiveMessageType.chat,
        color: messageColor,
        message: content,
        userName: userName,
      ));
    }
  }
}
