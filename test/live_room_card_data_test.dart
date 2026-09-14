import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_room.dart';

/// 收藏列表刷新时的合并保护：平台详情接口失败/被风控降级会返回一个只带
/// roomId 与 platform 的空对象，若拿它覆盖缓存会把卡片清空并落盘。
void main() {
  group('LiveRoom.hasUsableCardData', () {
    test('rejects the placeholder room platforms return on failure', () {
      final placeholder = LiveRoom(roomId: '21452505', platform: 'bilibili').getLiveRoomWithError();
      expect(placeholder.title, anyOf(isNull, isEmpty));
      expect(placeholder.nick, anyOf(isNull, isEmpty));
      expect(placeholder.cover, anyOf(isNull, isEmpty));
      expect(placeholder.hasUsableCardData, isFalse);
    });

    test('accepts any room that carries at least one card field', () {
      expect(LiveRoom(title: '标题').hasUsableCardData, isTrue);
      expect(LiveRoom(nick: '主播').hasUsableCardData, isTrue);
      expect(LiveRoom(cover: 'https://example.com/a.jpg').hasUsableCardData, isTrue);
    });

    test('keeps an offline room that still has its own data', () {
      // 真·下播房间由平台返回，仍带标题/主播名，应当照常合并（更新为未开播）
      final offline = LiveRoom(
        roomId: '6',
        platform: 'bilibili',
        title: '某主播的直播间',
        nick: '某主播',
        liveStatus: LiveStatus.offline,
      ).getLiveRoomWithError();
      expect(offline.hasUsableCardData, isTrue);
      expect(offline.liveStatus, LiveStatus.offline);
    });
  });
}
