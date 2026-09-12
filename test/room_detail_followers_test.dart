import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/site/douyin_site.dart';
import 'package:pure_live/core/site/kuaishou_site.dart';

void main() {
  group('Kuaishou room-detail fans', () {
    test('converts the unit-suffixed display string to a plain number', () {
      expect(KuaishowSite.parseFansCount({'fan': '152.7w'}), '1527000');
      expect(KuaishowSite.parseFansCount({'fan': '1.4w'}), '14000');
      expect(KuaishowSite.parseFansCount({'fan': '3.2亿'}), '320000000');
      expect(KuaishowSite.parseFansCount({'fan': '12.5k'}), '12500');
      expect(KuaishowSite.parseFansCount({'fan': '886'}), '886');
      expect(KuaishowSite.parseFansCount({'fan': '2.5万'}), '25000');
    });

    test('returns empty when counts or fan is absent', () {
      // 离线房间的 counts 可能是空对象，未开播时 author 也可能是空 Map。
      expect(KuaishowSite.parseFansCount(const <String, dynamic>{}), '');
      expect(KuaishowSite.parseFansCount({'fan': ''}), '');
      expect(KuaishowSite.parseFansCount(null), '');
      expect(KuaishowSite.parseFansCount({'fan': '暂无'}), '');
      expect(KuaishowSite.parseFansCount({'follow': '304'}), '');
    });
  });

  group('Douyin room-detail fans', () {
    test('prefers the numeric follower_count over the display string', () {
      // 线上实测 follower_count_str 可能是 "515.6万"，数字字段才是原始值。
      final owner = <String, dynamic>{
        'nickname': '某主播',
        'follow_info': <String, dynamic>{
          'following_count': 29,
          'follower_count': 9311,
          'follower_count_str': '9311',
        },
      };
      expect(DouyinSite.parseFollowersFromOwner(owner), '9311');

      final bigOwner = <String, dynamic>{
        'follow_info': <String, dynamic>{
          'follower_count': 5155606,
          'follower_count_str': '515.6万',
        },
      };
      expect(DouyinSite.parseFollowersFromOwner(bigOwner), '5155606');
    });

    test('falls back to the string field when the number is absent', () {
      final owner = <String, dynamic>{
        'follow_info': <String, dynamic>{'follower_count_str': '515.6万'},
      };
      expect(DouyinSite.parseFollowersFromOwner(owner), '515.6万');

      final plain = <String, dynamic>{
        'follow_info': <String, dynamic>{'follower_count': 123456},
      };
      expect(DouyinSite.parseFollowersFromOwner(plain), '123456');
    });

    test('returns empty when follow_info only carries follow status', () {
      // web enter 接口的 follow_info 只有关注状态，没有粉丝数：不显示该行。
      final owner = <String, dynamic>{
        'follow_info': <String, dynamic>{'follow_status': 0, 'follow_status_str': '0'},
      };
      expect(DouyinSite.parseFollowersFromOwner(owner), '');
      expect(DouyinSite.parseFollowersFromOwner(<String, dynamic>{}), '');
      expect(DouyinSite.parseFollowersFromOwner(null), '');
      expect(
        DouyinSite.parseFollowersFromOwner(<String, dynamic>{
          'follow_info': <String, dynamic>{'follower_count': 0},
        }),
        '',
      );
    });
  });
}
