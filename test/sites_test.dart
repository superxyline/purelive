import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/sites.dart';

void main() {
  test('validates live-room route platform ids without constructing a site', () {
    expect(Sites.isSupported('bilibili'), isTrue);
    expect(Sites.isSupported(' HUYA '), isTrue);
    expect(Sites.isSupported(' douyu '), isTrue);
    expect(Sites.isSupported(' DOUYIN '), isTrue);
    // 裁剪定制版已下线 Twitch/SOOP 等平台。
    expect(Sites.isSupported(' twitch '), isFalse);
    expect(Sites.isSupported(' SOOP '), isFalse);
    expect(Sites.isSupported('unknown-platform'), isFalse);
  });
}
