import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/services/quality_alert_service.dart';

/// 登录态降档告警：文案、平台隔离与冷却。
void main() {
  test('已登录平台被降档时弹一次提醒，冷却期内不重复', () {
    final service = QualityAlertService();
    final messages = <String>[];
    service.toastOverride = messages.add;

    service.reportClamped(
      platform: 'douyu',
      platformName: '斗鱼',
      requested: '原画',
      actual: '蓝光4M',
    );
    // 冷却期内（换 CDN / 换房间）不重复弹
    service.reportClamped(
      platform: 'douyu',
      platformName: '斗鱼',
      requested: '原画',
      actual: '蓝光4M',
    );

    expect(messages.length, 1);
    expect(messages.first, contains('斗鱼'));
    expect(messages.first, contains('原画 → 蓝光4M'));
    expect(messages.first, contains('重新登录'));
  });

  test('不同平台各自独立提醒', () {
    final service = QualityAlertService();
    final messages = <String>[];
    service.toastOverride = messages.add;

    service.reportClamped(platform: 'douyu', platformName: '斗鱼');
    service.reportClamped(platform: 'bilibili', platformName: '哔哩哔哩');

    expect(messages.length, 2);
    expect(messages[0], contains('斗鱼'));
    expect(messages[1], contains('哔哩哔哩'));
  });

  test('reset 后可以再次提醒', () {
    final service = QualityAlertService();
    final messages = <String>[];
    service.toastOverride = messages.add;

    service.reportClamped(platform: 'douyu', platformName: '斗鱼');
    service.reset();
    service.reportClamped(platform: 'douyu', platformName: '斗鱼');

    expect(messages.length, 2);
  });
}
