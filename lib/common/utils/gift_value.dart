/// 礼物价值折算（估算）与会话内礼物累计。
///
/// 礼物消息里的 `price` 单位各平台不同，这里集中口径：
/// - B站：实付金瓜子（`total_coin` 优先），1000 金瓜子 = 1 元；
///   `coinType == silver` 是免费礼物，只计数量不计价值。
/// - 虎牙：实付总额，单位是 1/100 虎牙币，1 虎牙币 ≈ 1 元。
/// - 抖音：`diamondCount` 是**单价**（钻石），1 元 ≈ 10 钻石。
/// - 斗鱼：协议里没有价格（解析时硬编码 1），只统计数量。
/// - 快手：匿名弹幕通道不下发礼物消息，暂时没有数据。
enum GiftPriceUnit {
  /// `price` 是本次礼物的实付总额
  total,

  /// `price` 是单价，需要乘以数量
  unit,

  /// 协议未提供价格，只统计数量
  unavailable,
}

class GiftValueRules {
  static const String bilibili = 'bilibili';
  static const String huya = 'huya';
  static const String douyin = 'douyin';

  /// 1 元对应多少个 `price` 单位。
  static int unitsPerYuan(String platform) => switch (platform) {
    bilibili => 1000,
    huya => 100,
    douyin => 10,
    _ => 0,
  };

  static GiftPriceUnit priceUnit(String platform) => switch (platform) {
    douyin => GiftPriceUnit.unit,
    bilibili || huya => GiftPriceUnit.total,
    _ => GiftPriceUnit.unavailable,
  };

  /// 主播到手比例。**这不是官方公开数据**：实际分成随合同与公会议价浮动，
  /// 这里按常见口径取 50%，界面展示时统一标注"估算"。
  static double anchorShare(String platform) => switch (platform) {
    bilibili || huya || douyin => 0.5,
    _ => 0.0,
  };

  /// 估算一条礼物消息的价值（人民币分）。取不到价格时返回 0。
  static int estimateFen({required String platform, required Map data, required int giftCount}) {
    final unit = priceUnit(platform);
    if (unit == GiftPriceUnit.unavailable) return 0;
    // B站银瓜子是免费礼物，不产生价值
    if (platform == bilibili && data['coinType']?.toString() == 'silver') return 0;
    final price = _asInt(data['price']);
    if (price <= 0) return 0;
    final perYuan = unitsPerYuan(platform);
    if (perYuan <= 0) return 0;
    final units = unit == GiftPriceUnit.unit ? price * (giftCount < 1 ? 1 : giftCount) : price;
    return units * 100 ~/ perYuan;
  }

  /// 由礼物价值估算主播到手（人民币分）。
  static int anchorFen(String platform, int valueFen) =>
      (valueFen * anchorShare(platform)).round();

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

/// 格式化为「¥12.34」。
String formatGiftValue(int fen) => '¥${(fen / 100).toStringAsFixed(2)}';

/// 一次会话期间的礼物累计（纯逻辑，便于单测）。
class GiftTally {
  /// 礼物件数
  int count = 0;

  /// 能算出价格的件数（免费礼物不计）
  int paidCount = 0;

  /// 礼物价值估算（人民币分）
  int valueFen = 0;

  /// 抖音 repeatCount 是**连击累计值**，用它记录上次上报值以算增量，
  /// 否则 1+2+…+n 会把一次连击的数量与价值放大数倍。
  final Map<String, int> _lastReportedCount = {};

  bool get isEmpty => count == 0;

  /// 累计一条礼物消息。
  ///
  /// [reportedCount] 是消息里的数量字段，[userKey] 用于区分同一直播间内的
  /// 不同送礼人（抖音连击按"用户+礼物"各自累计）。
  void add({
    required String platform,
    required Map data,
    required String userKey,
    required int reportedCount,
  }) {
    var amount = reportedCount < 1 ? 1 : reportedCount;
    if (platform == GiftValueRules.douyin) {
      final key = '$userKey|${data['giftName']}';
      final last = _lastReportedCount[key] ?? 0;
      final delta = amount > last ? amount - last : amount;
      _lastReportedCount[key] = amount;
      amount = delta;
    }
    count += amount;
    final fen = GiftValueRules.estimateFen(platform: platform, data: data, giftCount: amount);
    if (fen > 0) {
      valueFen += fen;
      paidCount += amount;
    }
  }

  void reset() {
    count = 0;
    paidCount = 0;
    valueFen = 0;
    _lastReportedCount.clear();
  }
}
