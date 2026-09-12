import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_message.dart';
import 'package:pure_live/core/danmaku/douyin_danmaku.dart';
import 'package:pure_live/core/danmaku/proto/douyin.pb.dart';

void main() {
  group('Douyin danmaku protocol', () {
    DouyinDanmaku createDanmaku(List<LiveMessage> received) {
      final danmaku = DouyinDanmaku();
      danmaku.danmakuArgs = DouyinDanmakuArgs(webRid: 'web', roomId: '100', userId: 'guest', cookie: '');
      danmaku.onMessage = received.add;
      return danmaku;
    }

    test('preserves room, id, user and timestamp metadata', () {
      final received = <LiveMessage>[];
      final danmaku = createDanmaku(received);
      final createdAt = DateTime(2026, 8, 17, 12).millisecondsSinceEpoch;
      final chat = ChatMessage(
        common: Common(roomId: Int64(100), msgId: Int64(9001), createTime: Int64(createdAt)),
        user: User(id: Int64(7), nickName: 'viewer'),
        content: 'hello',
      );

      danmaku.unPackWebcastChatMessage(chat.writeToBuffer(), envelopeMessageId: '8001');

      expect(received, hasLength(1));
      expect(received.single.userId, '7');
      expect(received.single.messageId, 'douyin:9001');
      expect(received.single.sentAt?.millisecondsSinceEpoch, createdAt);
    });

    test('drops chat payloads carrying another room id', () {
      final received = <LiveMessage>[];
      final danmaku = createDanmaku(received);
      final chat = ChatMessage(
        common: Common(roomId: Int64(200), msgId: Int64(1)),
        user: User(id: Int64(7), nickName: 'viewer'),
        content: 'wrong room',
      );

      danmaku.unPackWebcastChatMessage(chat.writeToBuffer());

      expect(received, isEmpty);
    });

    test('parses gift messages with diamond price and combo count', () {
      final received = <LiveMessage>[];
      final danmaku = createDanmaku(received);
      final message = GiftMessage(
        common: Common(roomId: Int64(100)),
        giftId: Int64(456),
        repeatCount: Int64(3),
        comboCount: Int64(3),
        user: User(id: Int64(7), nickName: '测试用户'),
        gift: GiftStruct(
          id: Int64(456),
          name: '小心心',
          diamondCount: 1,
          image: Image(urlListList: ['https://p3-webcast.douyinpic.com/gift.png']),
        ),
      );

      danmaku.unPackWebcastGiftMessage(message.writeToBuffer());

      expect(received, hasLength(1));
      final gift = received.single;
      expect(gift.type, LiveMessageType.gift);
      expect(gift.userName, '测试用户');
      expect(gift.message, '小心心');

      final data = gift.data as Map;
      expect(data['giftId'], '456');
      expect(data['giftCount'], 3);
      expect(data['giftName'], '小心心');
      expect(data['giftIcon'], 'https://p3-webcast.douyinpic.com/gift.png');
      // 价格取钻石单价，不再把 repeatCount 当价格
      expect(data['price'], 1);
      expect(data['platform'], 'douyin');
    });

    test('falls back to the gift icon image and defaults a missing count', () {
      final received = <LiveMessage>[];
      final danmaku = createDanmaku(received);
      final message = GiftMessage(
        common: Common(roomId: Int64(100)),
        giftId: Int64(685),
        user: User(id: Int64(7), nickName: '测试用户'),
        gift: GiftStruct(
          id: Int64(685),
          name: '粉丝团灯牌',
          icon: Image(urlListList: ['https://p3-webcast.douyinpic.com/icon.png']),
        ),
      );

      danmaku.unPackWebcastGiftMessage(message.writeToBuffer());

      expect(received, hasLength(1));
      final data = received.single.data as Map;
      expect(data['giftCount'], 1);
      expect(data['giftIcon'], 'https://p3-webcast.douyinpic.com/icon.png');
      // 免费礼物没有 diamondCount，价格兜底为 1
      expect(data['price'], 1);
    });
  });
}
