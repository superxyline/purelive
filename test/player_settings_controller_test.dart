import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/services/settings/player_settings_controller.dart';

void main() {
  group('player settings migration', () {
    test('keeps the global audio-only switch from backups', () {
      final config = PlayerSettingsController.extractConfig({
        'player': <String, dynamic>{'audioOnly': true, 'floatPlay': true},
      });

      // 全局"纯音频模式"是有效设置（定制版 2.0.0 恢复），不再做 legacy 退役。
      expect(config['audioOnly'], isTrue);
      expect(config['floatPlay'], isTrue);
    });

    test('keeps audio-only disabled for older backups without the field', () {
      final config = PlayerSettingsController.extractConfig({'player': <String, dynamic>{}});

      expect(config['audioOnly'], isFalse);
      expect(config['windowsPipAlwaysOnTop'], isFalse);
    });

    test('preserves the Windows mini-player stacking preference', () {
      final config = PlayerSettingsController.extractConfig({
        'player': <String, dynamic>{'windowsPipAlwaysOnTop': true},
      });

      expect(config['windowsPipAlwaysOnTop'], isTrue);
    });
  });
}
