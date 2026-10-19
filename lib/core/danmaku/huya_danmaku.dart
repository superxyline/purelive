import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pure_live/core/common/core_log.dart';
import 'package:pure_live/common/models/live_message.dart';
import 'package:pure_live/core/tars/huya_user_id.dart';
import 'package:pure_live/core/danmaku/huya_gift_catalog.dart';
import 'package:pure_live/pkg/tars/net/base_tars_http.dart';
import 'package:pure_live/pkg/tars/codec/tars_struct.dart';
import 'package:pure_live/core/common/web_socket_util.dart';
import 'package:pure_live/core/tars/game_event_message_board_panel.dart';
import 'package:pure_live/core/tars/get_game_event_message_board_req.dart';
import 'package:pure_live/core/tars/get_game_event_message_board_rsp.dart';
import 'package:pure_live/core/interface/live_danmaku.dart';
import 'package:pure_live/pkg/tars/codec/tars_input_stream.dart';
import 'package:pure_live/pkg/tars/codec/tars_output_stream.dart';

// ignore_for_file: no_leading_underscores_for_local_identifiers

class HuyaDanmakuArgs {
  final int uid;
  final int topSid;
  final int subSid;
  HuyaDanmakuArgs({required this.uid, required this.topSid, required this.subSid});
  @override
  String toString() {
    return json.encode({"uid": uid, "topSid": topSid, "subSid": subSid});
  }
}

class HuyaDanmaku implements LiveDanmaku {
  @override
  int heartbeatTime = 60 * 1000;
  bool _connected = false;

  @override
  bool get isConnected => _connected;

  @override
  void markConnected() {
    _connected = true;
    // 新会话：作废上一次连接遗留的 SC 去重集合与在途刷新
    _sessionGeneration++;
    _emittedSuperChats.clear();
    _superChatRefreshQueued = false;
  }

  @override
  void markDisconnected() {
    _connected = false;
    _sessionGeneration++;
    _emittedSuperChats.clear();
    _superChatRefreshQueued = false;
  }

  @override
  Function(LiveMessage msg)? onMessage;
  @override
  Function(String msg)? onClose;
  @override
  Function()? onReady;
  String serverUrl = "wss://wsapi.huya.com";

  WebScoketUtils? webScoketUtils;

  // ---------------------------------------------------------------------------
  // 醒目留言（SC）：通知先到、留言板快照后更新的最终一致性时序
  // （移植自上游 huya_danmaku，含补偿窗口与事件去重）
  // ---------------------------------------------------------------------------

  /// 醒目留言在弹幕区的播报形态："xxx(来自一元上头条)"。
  static final RegExp _headlineScRegex = RegExp(r'\(来自.+?上头条\)');

  /// 有界去重：长时间观看不会让集合无限增长。
  static const int _maxRememberedSuperChats = 512;

  /// 补偿窗口：通知到达后按这几个时间点重拉，覆盖「推送先到、快照后到」。
  static const List<Duration> defaultSuperChatRetryDelays = <Duration>[
    Duration.zero,
    Duration(milliseconds: 600),
    Duration(milliseconds: 1800),
    Duration(milliseconds: 4000),
  ];

  final Set<LiveSuperChatMessage> _emittedSuperChats = <LiveSuperChatMessage>{};
  Future<void>? _superChatRefreshFuture;
  bool _superChatRefreshQueued = false;
  int _sessionGeneration = 0;

  /// Current website heartbeat: `EWSCmdC2S_HeartBeatReq` (20).
  List<int> get heartbeatData {
    final command = TarsOutputStream();
    command.write(20, 0);
    command.write(Uint8List(0), 1);
    return command.toUint8List();
  }

  late HuyaDanmakuArgs danmakuArgs;
  int _generation = 0;

  @override
  Future start(dynamic args) async {
    final generation = ++_generation;
    await webScoketUtils?.close();
    webScoketUtils = null;
    if (generation != _generation) return;
    danmakuArgs = args as HuyaDanmakuArgs;
    markDisconnected();
    webScoketUtils = WebScoketUtils(
      url: serverUrl,
      heartBeatTime: heartbeatTime,
      onMessage: (e) {
        if (generation == _generation) decodeMessage(e);
      },
      onReady: () {
        if (generation != _generation) return;
        markConnected();
        onReady?.call();
        joinRoom();
        // Keep the new room-group connection alive immediately.
        heartbeat();
      },
      onHeartBeat: () {
        heartbeat();
      },
      onReconnect: () {
        if (generation != _generation) return;
        markDisconnected();
        onClose?.call("与服务器断开连接，正在尝试重连");
      },
      onClose: (e) {
        if (generation != _generation) return;
        markDisconnected();
        onClose?.call("服务器连接失败$e");
      },
    );
    await webScoketUtils?.connect();
  }

  void joinRoom() {
    var joinData = getJoinData(danmakuArgs.uid);
    webScoketUtils?.sendMessage(joinData);
    // 注册成功后拉一次礼物目录（WUP getPropsList）：
    // 6501 礼物消息的礼物名/图标在旧 payload 中可能缺失，用目录补齐。
    try {
      webScoketUtils?.sendMessage(
        HuyaGiftCatalog.instance.buildGetPropsListRequest(uid: danmakuArgs.uid),
      );
    } catch (e) {
      CoreLog.error(e);
    }
  }

  List<int> getJoinData(int uid) {
    try {
      final group = TarsOutputStream();
      group.write(<String>['live:$uid', 'chat:$uid'], 0);
      group.write('', 1);

      final command = TarsOutputStream();
      command.write(16, 0); // EWSCmdC2S_RegisterGroupReq
      command.write(group.toUint8List(), 1);
      return command.toUint8List();
    } catch (e) {
      CoreLog.error(e);
      return [];
    }
  }

  @override
  void heartbeat() {
    webScoketUtils?.sendMessage(heartbeatData);
  }

  @override
  Future stop() async {
    _generation++;
    markDisconnected();
    onMessage = null;
    onClose = null;
    onReady = null;
    await webScoketUtils?.close();
    webScoketUtils = null;
  }

  void decodeMessage(List<int> data) {
    try {
      var stream = TarsInputStream(Uint8List.fromList(data));
      var type = stream.read(0, 0, false);
      if (type == 7) {
        stream = TarsInputStream(stream.readBytes(1, false));
        HYPushMessage wSPushMessage = HYPushMessage();
        wSPushMessage.readFrom(stream);
        unawaited(_decodePush(wSPushMessage.uri, wSPushMessage.msg));
      } else if (type == 22) {
        final push = HYPushMessageV2();
        push.readFrom(TarsInputStream(stream.readBytes(1, false)));
        for (final item in push.items) {
          unawaited(_decodePush(item.uri, item.msg, messageId: item.messageId));
        }
      } else if (type == 4) {
        // EWSCmd_WupRsp：WUP 响应（当前仅礼物目录 getPropsList）
        final vData = stream.read(Uint8List, 1, false) as Uint8List?;
        if (vData != null && vData.isNotEmpty) {
          HuyaGiftCatalog.instance.handleWupResponse(vData);
        }
      }
    } catch (e) {
      CoreLog.error(e);
    }
  }

  Future<void> _decodePush(int uri, List<int> payload, {int messageId = 0}) async {
    if (uri == 1400) {
      final messageNotice = HYMessage();
      messageNotice.readFrom(TarsInputStream(Uint8List.fromList(payload)));
      final color = messageNotice.bulletFormat.fontColor;
      // "xxx(来自一元上头条)" 是醒目留言在弹幕区的播报：留言板 WUP 还没更新时
      // 这条先到，靠它触发一次后台重拉把 SC 补上（与 2001314 共用同一条刷新管线）。
      if (_headlineScRegex.hasMatch(messageNotice.content)) {
        _scheduleSuperChatRefresh();
      }
      onMessage?.call(
        LiveMessage(
          type: LiveMessageType.chat,
          color: color <= 0 ? LiveMessageColor.white : LiveMessageColor.numberToColor(color),
          message: messageNotice.content,
          userName: messageNotice.userInfo.nickName,
          userId: messageNotice.userInfo.uid.toString(),
          messageId: messageId > 0 ? 'huya:$messageId' : '',
        ),
      );
    } else if (uri == 8006) {
      final attendeeCount = TarsInputStream(Uint8List.fromList(payload)).read(0, 0, false);
      onMessage?.call(
        LiveMessage(
          type: LiveMessageType.online,
          // Current website captures keep iAttendeeCount in the same
          // multi-million popularity range as the list value.
          data: LiveAudienceUpdate(kind: LiveAudienceMetricKind.popularity, value: attendeeCount),
          color: LiveMessageColor.white,
          message: '',
          userName: '',
          messageId: messageId > 0 ? 'huya:$messageId' : '',
        ),
      );
    } else if (uri == 2001314) {
      // 留言板变化通知：payload 能直接解出面板就立即上屏，否则后台补拉
      final fromPanel = superChatsFromPanel(payload);
      if (fromPanel != null) {
        for (final chat in fromPanel) {
          if (!_rememberSuperChat(chat)) continue;
          onMessage?.call(
            LiveMessage(
              type: LiveMessageType.superChat,
              userName: 'SUPER_CHAT_MESSAGE',
              message: 'SUPER_CHAT_MESSAGE',
              color: LiveMessageColor.white,
              data: chat,
            ),
          );
        }
        return;
      }
      // 通知可能先于留言板快照到达：这里不能同步等 HTTP（会串行化其它弹幕），
      // 交给带补偿窗口的后台刷新。
      _scheduleSuperChatRefresh();
    } else if (uri == 6501) {
      // 虎牙礼物消息 (SendItemSubBroadcastPacket)
      try {
        final gift = HuyaSendItemSubBroadcastPacket();
        gift.readFrom(TarsInputStream(Uint8List.fromList(payload)));
        // 礼物名/图标缺失时查礼物目录补齐（旧版 payload 无 sPropsName@20）
        final catalogInfo = HuyaGiftCatalog.instance.get(gift.iItemType);
        var giftName = gift.sPropsName.trim();
        if (giftName.isEmpty) giftName = catalogInfo?.name ?? '';
        // 价格：实付总额优先（100 = 1 虎牙币）；缺失时用目录单价 × 数量
        var price = gift.lPayTotal;
        if (price <= 0 && catalogInfo != null && catalogInfo.priceYb > 0) {
          price = catalogInfo.priceYb * (gift.iItemCount > 0 ? gift.iItemCount : 1);
        }
        onMessage?.call(
          LiveMessage(
            type: LiveMessageType.gift,
            userName: gift.sSenderNick,
            userId: gift.lSenderUid > 0 ? gift.lSenderUid.toString() : '',
            message: giftName,
            color: const LiveMessageColor(255, 200, 0), // 金色表示礼物
            data: {
              'giftId': gift.iItemType.toString(),
              'giftCount': gift.iItemCount > 0 ? gift.iItemCount : 1,
              'giftName': giftName,
              // 图标优先取礼物目录（消息本身不携带图标）
              'giftIcon': catalogInfo?.icon ?? '',
              'price': price > 0 ? price : 1,
              'platform': 'huya',
            },
            messageId: messageId > 0 ? 'huya:$messageId' : '',
          ),
        );
      } catch (e) {
        CoreLog.error('Failed to parse huya gift message: $e');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 醒目留言（SC）拉取：通知 → 有界补偿窗口 → 去重上屏
  // ---------------------------------------------------------------------------

  static const String _sdkUa = "HYSDK(Windows,30000002)_APP(pc_exe&7100004&official)_SDK(trans&2.40.0.6448)";

  /// 留言板快照 → 统一 SC 模型（与 HuyaSite 共用同一份解析，避免两处漂移）。
  static List<LiveSuperChatMessage> parseSuperChats(GameEventMessageBoardPanel panel, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final messages = <LiveSuperChatMessage>[];
    for (final item in panel.vGameEventMessageBoardInfo) {
      final content = item.sContent.trim();
      if (content.isEmpty) continue;
      // start_time = end_time - total，end_time = 现在 + 剩余
      final remainSec = item.iCountDown > 0 ? item.iCountDown : item.iTotalSec;
      if (remainSec <= 0) continue;
      final totalSeconds = item.iTotalSec > 0 ? item.iTotalSec : remainSec;
      var price = item.iCost;
      if (price <= 0 && item.iCostPay > 0) price = max(1, (item.iCostPay / 100).round());
      final endTime = at.add(Duration(seconds: remainSec));
      final startTime = endTime.subtract(Duration(seconds: totalSeconds));
      messages.add(
        LiveSuperChatMessage(
          messageId: item.lMessageId > 0 ? 'huya:${item.lMessageId}' : '',
          backgroundBottomColor: "#246488",
          backgroundColor: "#ffffff",
          endTime: endTime,
          face: item.tMessageUser.sAvatar,
          message: content,
          price: price,
          startTime: startTime,
          userName: item.tMessageUser.sNick.trim(),
        ),
      );
    }
    return messages;
  }

  /// payload 直接就是留言板面板时解析 SC；解不出返回 null（交给重拉）。
  static List<LiveSuperChatMessage>? superChatsFromPanel(List<int> payload, {DateTime? now}) {
    if (payload.isEmpty) return null;
    final GameEventMessageBoardPanel panel;
    try {
      final bytes = Uint8List.fromList(payload);
      if (!TarsInputStream(bytes).skipToTag(1)) return null;
      panel = GameEventMessageBoardPanel()..readFrom(TarsInputStream(bytes));
    } catch (_) {
      return null;
    }
    return parseSuperChats(panel, now: now);
  }

  void _scheduleSuperChatRefresh() {
    if (_superChatRefreshFuture != null) {
      _superChatRefreshQueued = true;
      return;
    }
    _superChatRefreshQueued = false;
    final generation = _sessionGeneration;
    final future = _refreshSuperChats(generation);
    _superChatRefreshFuture = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_superChatRefreshFuture, future)) {
          _superChatRefreshFuture = null;
        }
        if (_superChatRefreshQueued && generation == _sessionGeneration) {
          _scheduleSuperChatRefresh();
        }
      }),
    );
  }

  Future<void> _refreshSuperChats(int generation) async {
    for (var attempt = 0; attempt < defaultSuperChatRetryDelays.length; attempt++) {
      final delay = defaultSuperChatRetryDelays[attempt];
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      if (generation != _sessionGeneration || danmakuArgs.topSid == 0) return;

      try {
        final messages = await _fetchSuperChats(danmakuArgs.topSid).timeout(const Duration(seconds: 3));
        if (generation != _sessionGeneration) return;

        final hadKnown = _emittedSuperChats.isNotEmpty;
        var emittedNew = false;
        for (final message in messages) {
          if (!_rememberSuperChat(message)) continue;
          emittedNew = true;
          onMessage?.call(
            LiveMessage(
              type: LiveMessageType.superChat,
              userName: 'SUPER_CHAT_MESSAGE',
              message: 'SUPER_CHAT_MESSAGE',
              color: LiveMessageColor.white,
              data: message,
            ),
          );
        }
        // 已有基线后又出现新条目，说明快照追上来了，不用再重试
        if (hadKnown && emittedNew) return;
      } catch (error) {
        if (generation == _sessionGeneration && attempt == defaultSuperChatRetryDelays.length - 1) {
          CoreLog.error('huya_super_chat_refresh_failed: $error');
        }
      }
    }
  }

  bool _rememberSuperChat(LiveSuperChatMessage message) {
    if (!_emittedSuperChats.add(message)) return false;
    while (_emittedSuperChats.length > _maxRememberedSuperChats) {
      _emittedSuperChats.remove(_emittedSuperChats.first);
    }
    return true;
  }

  Future<List<LiveSuperChatMessage>> _fetchSuperChats(int lPid) async {
    final client = BaseTarsHttp(
      "https://wup.huya.com",
      "wupui",
      timeOut: 2,
      headers: {'Origin': 'https://www.huya.com', 'Referer': 'https://www.huya.com', 'User-Agent': _sdkUa},
    );
    final tid = HuyaUserId()..sHuYaUA = _sdkUa;
    final req = GetGameEventMessageBoardReq()
      ..lPid = lPid
      ..tId = tid
      ..iMessageBoardScope = 0
      ..iPageSize = 50;
    try {
      final rsp = await client.tupRequest("getHeadLineMessageBoard", req, GetGameEventMessageBoardRsp());
      final messages = parseSuperChats(rsp.tMessageBoardPanel);
      messages.sort((a, b) => b.startTime.compareTo(a.startTime));
      return messages.length > 10 ? messages.sublist(0, 10) : messages;
    } finally {
      // 关闭传输，避免通知频繁时堆积连接
      client.dio.close(force: true);
    }
  }
}

class HYPushMessage extends TarsStruct {
  int pushType = 0;
  int uri = 0;
  List<int> msg = <int>[];
  int protocolType = 0;

  @override
  void readFrom(TarsInputStream inputStream) {
    pushType = inputStream.read(pushType, 0, false);
    uri = inputStream.read(uri, 1, false);
    msg = inputStream.readBytes(2, false);
    protocolType = inputStream.read(protocolType, 3, false);
  }

  @override
  void writeTo(TarsOutputStream outputStream) {}

  @override
  Object deepCopy() {
    return HYPushMessage()
      ..pushType = pushType
      ..uri = uri
      ..msg = List<int>.from(msg)
      ..protocolType = protocolType;
  }

  @override
  void displayAsString(StringBuffer sb, int level) {}
}

class HYPushMessageV2 extends TarsStruct {
  String groupId = '';
  List<HYMessageItem> items = <HYMessageItem>[];

  @override
  void readFrom(TarsInputStream inputStream) {
    groupId = inputStream.read(groupId, 0, false);
    items = inputStream.readList<HYMessageItem>(<HYMessageItem>[HYMessageItem()], 1, false);
  }

  @override
  void writeTo(TarsOutputStream outputStream) {
    outputStream.write(groupId, 0);
    outputStream.write(items, 1);
  }

  @override
  Object deepCopy() => HYPushMessageV2()
    ..groupId = groupId
    ..items = items.map((item) => item.deepCopy() as HYMessageItem).toList();

  @override
  void displayAsString(StringBuffer sb, int level) {}
}

class HYMessageItem extends TarsStruct {
  int uri = 0;
  List<int> msg = <int>[];
  int messageId = 0;

  @override
  void readFrom(TarsInputStream inputStream) {
    uri = inputStream.read(uri, 0, false);
    msg = inputStream.readBytes(1, false);
    messageId = inputStream.read(messageId, 2, false);
  }

  @override
  void writeTo(TarsOutputStream outputStream) {
    outputStream.write(uri, 0);
    outputStream.write(Uint8List.fromList(msg), 1);
    outputStream.write(messageId, 2);
  }

  @override
  Object deepCopy() => HYMessageItem()
    ..uri = uri
    ..msg = List<int>.from(msg)
    ..messageId = messageId;

  @override
  void displayAsString(StringBuffer sb, int level) {}
}

class HYSender extends TarsStruct {
  int uid = 0;
  int lMid = 0;
  String nickName = "";
  int gender = 0;

  @override
  void readFrom(TarsInputStream inputStream) {
    uid = inputStream.read(uid, 0, false);
    lMid = inputStream.read(lMid, 0, false);
    nickName = inputStream.read(nickName, 2, false);
    gender = inputStream.read(gender, 3, false);
  }

  @override
  void writeTo(TarsOutputStream outputStream) {}

  @override
  Object deepCopy() {
    return HYSender()
      ..uid = uid
      ..lMid = lMid
      ..nickName = nickName
      ..gender = gender;
  }

  @override
  void displayAsString(StringBuffer sb, int level) {}
}

class HYMessage extends TarsStruct {
  HYSender userInfo = HYSender();
  String content = "";
  HYBulletFormat bulletFormat = HYBulletFormat();

  @override
  void readFrom(TarsInputStream inputStream) {
    userInfo = inputStream.readTarsStruct(userInfo, 0, false) as HYSender;
    content = inputStream.read(content, 3, false);
    bulletFormat = inputStream.readTarsStruct(bulletFormat, 6, false) as HYBulletFormat;
  }

  @override
  void writeTo(TarsOutputStream outputStream) {}

  @override
  Object deepCopy() {
    return HYMessage()
      ..userInfo = userInfo.deepCopy() as HYSender
      ..content = content
      ..bulletFormat = bulletFormat.deepCopy() as HYBulletFormat;
  }

  @override
  void displayAsString(StringBuffer sb, int level) {}
}

class HYBulletFormat extends TarsStruct {
  int fontColor = 0;
  int fontSize = 4;
  int textSpeed = 0;
  int transitionType = 1;

  @override
  void readFrom(TarsInputStream inputStream) {
    fontColor = inputStream.read(fontColor, 0, false);
    fontSize = inputStream.read(fontSize, 1, false);
    textSpeed = inputStream.read(textSpeed, 2, false);
    transitionType = inputStream.read(transitionType, 3, false);
  }

  @override
  void writeTo(TarsOutputStream outputStream) {}

  @override
  Object deepCopy() {
    return HYBulletFormat()
      ..fontColor = fontColor
      ..fontSize = fontSize
      ..textSpeed = textSpeed
      ..transitionType = transitionType;
  }

  @override
  void displayAsString(StringBuffer sb, int level) {}
}

/// 虎牙礼物消息结构 (SendItemSubBroadcastPacket)
/// uri == 6501；字段按 tag 升序读取，与线上协议一致。
class HuyaSendItemSubBroadcastPacket extends TarsStruct {
  int iItemType = 0; // tag 0 - 礼物ID (int32)
  String strPayId = ""; // tag 1 - 支付流水号
  int iItemCount = 1; // tag 2 - 礼物数量 (int32)
  int lPresenterUid = 0; // tag 3 - 主播UID (int64)
  int lSenderUid = 0; // tag 4 - 送礼者UID (int64)
  String sPresenterNick = ""; // tag 5 - 主播昵称
  String sSenderNick = ""; // tag 6 - 送礼者昵称
  String sSendContent = ""; // tag 7 - 附言
  String sPropsName = ""; // tag 20 - 礼物名称（旧版消息可能为空）
  int lPayTotal = 0; // tag 41 - 实付总额（100 = 1 虎牙币）

  @override
  void readFrom(TarsInputStream inputStream) {
    // 逐字段容错读取：单个字段缺失或类型不符时保留默认值，
    // 避免一个字段解析失败导致整条礼物消息被丢弃。
    try {
      iItemType = inputStream.read(iItemType, 0, false);
    } catch (_) {}
    try {
      strPayId = inputStream.read(strPayId, 1, false);
    } catch (_) {}
    try {
      iItemCount = inputStream.read(iItemCount, 2, false);
    } catch (_) {}
    try {
      lPresenterUid = inputStream.read(lPresenterUid, 3, false);
    } catch (_) {}
    try {
      lSenderUid = inputStream.read(lSenderUid, 4, false);
    } catch (_) {}
    try {
      sPresenterNick = inputStream.read(sPresenterNick, 5, false);
    } catch (_) {}
    try {
      sSenderNick = inputStream.read(sSenderNick, 6, false);
    } catch (_) {}
    try {
      sSendContent = inputStream.read(sSendContent, 7, false);
    } catch (_) {}
    try {
      sPropsName = inputStream.read(sPropsName, 20, false);
    } catch (_) {}
    try {
      lPayTotal = inputStream.read(lPayTotal, 41, false);
    } catch (_) {}
  }

  @override
  void writeTo(TarsOutputStream outputStream) {
    outputStream.write(iItemType, 0);
    outputStream.write(strPayId, 1);
    outputStream.write(iItemCount, 2);
    outputStream.write(lPresenterUid, 3);
    outputStream.write(lSenderUid, 4);
    outputStream.write(sPresenterNick, 5);
    outputStream.write(sSenderNick, 6);
    outputStream.write(sSendContent, 7);
    outputStream.write(sPropsName, 20);
    outputStream.write(lPayTotal, 41);
  }

  @override
  Object deepCopy() {
    return HuyaSendItemSubBroadcastPacket()
      ..iItemType = iItemType
      ..strPayId = strPayId
      ..iItemCount = iItemCount
      ..lPresenterUid = lPresenterUid
      ..lSenderUid = lSenderUid
      ..sPresenterNick = sPresenterNick
      ..sSenderNick = sSenderNick
      ..sSendContent = sSendContent
      ..sPropsName = sPropsName
      ..lPayTotal = lPayTotal;
  }

  @override
  void displayAsString(StringBuffer sb, int level) {}
}
