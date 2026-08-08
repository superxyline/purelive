import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/iptv/parsers/txt_parser.dart';

void main() {
  group('TxtParser', () {
    const providerId = 'txt_provider';

    test('parses genre playlist with multiple backup sources', () {
      const content = '''
央视,#genre#
CCTV1,http://example.com/cctv1.m3u8
CCTV2,http://example.com/a.m3u8#http://example.com/b.m3u8
''';

      final result = TxtParser().parse(content, providerId: providerId);

      expect(result.hasErrors, isFalse);
      expect(result.channelCount, 3);
      expect(result.channels[0].name, 'CCTV1');
      expect(result.channels[0].groupTitle, '央视');
      expect(result.channels[1].name, 'CCTV2 (线路1)');
      expect(result.channels[2].name, 'CCTV2 (线路2)');
      expect(result.channels[1].streamUrl, 'http://example.com/a.m3u8');
      expect(result.channels[2].streamUrl, 'http://example.com/b.m3u8');
    });

    test('skips malformed lines without failing', () {
      const content = '''
央视,#genre#
line-without-comma
CCTV1,http://example.com/cctv1.m3u8
''';

      final result = TxtParser().parse(content, providerId: providerId);

      expect(result.channelCount, 1);
      expect(result.channels.single.name, 'CCTV1');
      expect(result.hasErrors, isFalse);
    });
  });
}
