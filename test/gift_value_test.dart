import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/utils/gift_value.dart';

void main() {
  group('GiftValueRules', () {
    test('bilibili uses total coin: 1000 gold seeds = 1 yuan', () {
      // 实付 5000 金瓜子 = 5 元 = 500 分
      expect(
        GiftValueRules.estimateFen(
          platform: GiftValueRules.bilibili,
          data: {'price': 5000, 'coinType': 'gold'},
          giftCount: 1,
        ),
        500,
      );
    });

    test('bilibili silver (free) gifts carry no value', () {
      expect(
        GiftValueRules.estimateFen(
          platform: GiftValueRules.bilibili,
          data: {'price': 5000, 'coinType': 'silver'},
          giftCount: 1,
        ),
        0,
      );
    });

    test('huya price is 1/100 huya coin, 1:1 with yuan', () {
      // 实付 10000 → 100 虎牙币 → 100 元 = 10000 分
      expect(
        GiftValueRules.estimateFen(
          platform: GiftValueRules.huya,
          data: {'price': 10000},
          giftCount: 1,
        ),
        10000,
      );
    });

    test('douyin price is a unit price in diamonds (10 diamonds = 1 yuan)', () {
      // 单价 5 钻石 × 10 件 = 50 钻石 = 5 元 = 500 分
      expect(
        GiftValueRules.estimateFen(
          platform: GiftValueRules.douyin,
          data: {'price': 5},
          giftCount: 10,
        ),
        500,
      );
    });

    test('douyu and kuaishou have no price, so no value', () {
      for (final platform in ['douyu', 'kuaishou']) {
        expect(
          GiftValueRules.estimateFen(platform: platform, data: {'price': 999}, giftCount: 3),
          0,
        );
        expect(GiftValueRules.priceUnit(platform), GiftPriceUnit.unavailable);
        expect(GiftValueRules.anchorShare(platform), 0.0);
      }
    });

    test('anchor payout is the platform share of the value', () {
      expect(GiftValueRules.anchorFen(GiftValueRules.bilibili, 500), 250);
      expect(GiftValueRules.anchorFen('douyu', 500), 0);
    });

    test('formats fen as yuan with two decimals', () {
      expect(formatGiftValue(0), '¥0.00');
      expect(formatGiftValue(1234), '¥12.34');
    });
  });

  group('GiftTally', () {
    test('adds counts and values for per-message-count platforms', () {
      final tally = GiftTally();
      // B站：两条消息各自是独立的一次投喂
      tally.add(
        platform: GiftValueRules.bilibili,
        data: {'price': 1000, 'giftName': '小心心', 'coinType': 'gold'},
        userKey: 'u1',
        reportedCount: 2,
      );
      tally.add(
        platform: GiftValueRules.bilibili,
        data: {'price': 1000, 'giftName': '小心心', 'coinType': 'gold'},
        userKey: 'u2',
        reportedCount: 1,
      );
      expect(tally.count, 3);
      expect(tally.paidCount, 3);
      // 2000 金瓜子 = 2 元 = 200 分
      expect(tally.valueFen, 200);
    });

    test('treats douyin repeatCount as a running total, not an increment', () {
      final tally = GiftTally();
      final data = {'price': 5, 'giftName': '玫瑰'};
      // 一次 3 连击：平台依次上报 1、2、3
      for (final reported in [1, 2, 3]) {
        tally.add(
          platform: GiftValueRules.douyin,
          data: data,
          userKey: 'viewer',
          reportedCount: reported,
        );
      }
      // 只能算 3 件，不能算 1+2+3=6 件
      expect(tally.count, 3);
      // 5 钻石 × 3 = 15 钻石 = 1.5 元 = 150 分
      expect(tally.valueFen, 150);

      // 同一用户再来一轮新连击（计数从头开始）
      tally.add(
        platform: GiftValueRules.douyin,
        data: data,
        userKey: 'viewer',
        reportedCount: 1,
      );
      expect(tally.count, 4);
    });

    test('keeps separate combo counters per viewer and gift', () {
      final tally = GiftTally();
      tally.add(
        platform: GiftValueRules.douyin,
        data: {'price': 10, 'giftName': 'A'},
        userKey: 'v1',
        reportedCount: 2,
      );
      tally.add(
        platform: GiftValueRules.douyin,
        data: {'price': 10, 'giftName': 'B'},
        userKey: 'v1',
        reportedCount: 2,
      );
      // 两个礼物各自从 0 起算，都是新连击
      expect(tally.count, 4);
      expect(tally.valueFen, 400);
    });

    test('reset clears counters', () {
      final tally = GiftTally()
        ..add(
          platform: GiftValueRules.huya,
          data: {'price': 100},
          userKey: 'u',
          reportedCount: 1,
        );
      expect(tally.isEmpty, isFalse);
      tally.reset();
      expect(tally.isEmpty, isTrue);
      expect(tally.valueFen, 0);
      expect(tally.paidCount, 0);
    });

    test('free gifts still count toward the gift total', () {
      final tally = GiftTally()
        ..add(
          platform: GiftValueRules.bilibili,
          data: {'price': 100, 'coinType': 'silver'},
          userKey: 'u',
          reportedCount: 5,
        );
      expect(tally.count, 5);
      expect(tally.paidCount, 0);
      expect(tally.valueFen, 0);
    });
  });
}
