import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/iptv/models/channel.dart';
import 'package:pure_live/core/iptv/parsers/m3u_parser.dart';

void main() {
  group('M3uParser', () {
    const providerId = 'test_provider';

    test('parses standard M3U playlist with extended attributes', () {
      const content = '''
#EXTM3U
#EXTINF:-1 tvg-id="cctv1" tvg-name="CCTV-1" tvg-logo="http://logo/cctv1.png" group-title="央视",CCTV-1 高清
http://example.com/cctv1.m3u8
#EXTINF:-1 group-title="卫视",东方卫视
http://example.com/dongfang.m3u8
''';

      final result = M3uParser().parse(content, providerId: providerId);

      expect(result.hasErrors, isFalse);
      expect(result.channelCount, 2);

      final first = result.channels.first;
      expect(first.providerId, providerId);
      expect(first.name, 'CCTV-1 高清');
      expect(first.tvgId, 'cctv1');
      expect(first.tvgName, 'CCTV-1');
      expect(first.tvgLogo, 'http://logo/cctv1.png');
      expect(first.groupTitle, '央视');
      expect(first.streamUrl, 'http://example.com/cctv1.m3u8');
      expect(first.streamType, StreamType.live);
      expect(first.id, startsWith('${providerId}_'));
    });

    test('reports error when #EXTM3U header is missing', () {
      const content = '#EXTINF:-1,NoHeader\nhttp://example.com/a.m3u8';

      final result = M3uParser().parse(content, providerId: providerId);

      expect(result.hasErrors, isTrue);
      expect(result.errors, contains('Missing #EXTM3U header'));
    });

    test('empty content reports error and yields no channels', () {
      final result = M3uParser().parse('', providerId: providerId);

      expect(result.hasErrors, isTrue);
      expect(result.channels, isEmpty);
    });

    test('skips entries with invalid stream urls', () {
      const content = '''
#EXTM3U
#EXTINF:-1,InvalidUrl
not-a-url
#EXTINF:-1,Valid
http://example.com/ok.m3u8
''';

      final result = M3uParser().parse(content, providerId: providerId);

      expect(result.channelCount, 1);
      expect(result.channels.single.streamUrl, 'http://example.com/ok.m3u8');
    });

    test('parses tvg-chno channel number', () {
      const content = '''
#EXTM3U
#EXTINF:-1 tvg-chno="5",五台
http://example.com/5.m3u8
''';

      final result = M3uParser().parse(content, providerId: providerId);

      expect(result.channels.single.channelNumber, 5);
    });

    test('infers VOD and series stream types', () {
      const content = '''
#EXTM3U
#EXTINF:-1 group-title="Movies",Movie
http://example.com/movie/1.mp4
#EXTINF:-1 group-title="Series",Series
http://example.com/series/1.mp4
''';

      final result = M3uParser().parse(content, providerId: providerId);

      expect(result.channels[0].streamType, StreamType.vod);
      expect(result.channels[1].streamType, StreamType.series);
    });
  });
}
