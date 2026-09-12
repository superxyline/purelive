import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/site/bilibili_site.dart';

void main() {
  group('Bilibili room-detail followers', () {
    test('reads anchor_info.relation_info.attention (singular)', () {
      final roomInfo = <String, dynamic>{
        'anchor_info': <String, dynamic>{
          'base_info': <String, dynamic>{'uname': '七海Nana7mi'},
          // 真实接口形状：relation_info 只有 attention 一个键。
          'relation_info': <String, dynamic>{'attention': 1114426},
        },
      };
      expect(BiliBiliSite.parseFollowersFromRoomInfo(roomInfo), '1114426');
    });

    test('does not accept the search API plural field name', () {
      // 复数 attentions 是搜索接口 live_room 的字段，getInfoByRoom 没有；
      // 取错字段会静默返回空串，让直播间信息永远缺这一行。
      final roomInfo = <String, dynamic>{
        'anchor_info': <String, dynamic>{
          'relation_info': <String, dynamic>{'attentions': 123456},
        },
      };
      expect(BiliBiliSite.parseFollowersFromRoomInfo(roomInfo), '');
    });

    test('returns empty string when relation_info is missing (risk control)', () {
      expect(
        BiliBiliSite.parseFollowersFromRoomInfo(<String, dynamic>{
          'anchor_info': <String, dynamic>{
            'base_info': <String, dynamic>{'uname': 'x'},
          },
        }),
        '',
      );
      expect(BiliBiliSite.parseFollowersFromRoomInfo(const <String, dynamic>{}), '');
      expect(BiliBiliSite.parseFollowersFromRoomInfo(null), '');
    });
  });
}
