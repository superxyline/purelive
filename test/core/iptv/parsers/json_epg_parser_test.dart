import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/iptv/parsers/json_epg_parser.dart';

void main() {
  group('JsonEpgParser', () {
    const sourceId = 'json_epg';

    test('parses channels and programmes from unix timestamps', () {
      final map = {
        'channels': [
          {'id': 'c1', 'name': 'Channel 1', 'icon': 'http://logo/c1.png', 'number': '3'},
        ],
        'programmes': [
          {
            'channelId': 'c1',
            'title': 'Show A',
            'description': 'Desc',
            'start': 1700000000, // seconds
            'duration': 60,
          },
        ],
      };

      final result = JsonEpgParser().parse(jsonEncode(map), sourceId: sourceId);

      expect(result.channels, hasLength(1));
      expect(result.programmes, hasLength(1));

      final channel = result.channels.single;
      expect(channel.id, 'c1');
      expect(channel.primaryName, 'Channel 1');
      expect(channel.iconUrl, 'http://logo/c1.png');
      expect(channel.number, '3');

      final programme = result.programmes.single;
      expect(programme.title, 'Show A');
      expect(programme.description, 'Desc');
      expect(programme.start, DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000));
      expect(programme.stop, programme.start.add(const Duration(minutes: 60)));
    });

    test('falls back to epg key and ISO timestamps', () {
      final map = {
        'channels': [
          {'channelId': 'c2', 'displayName': 'Channel 2'},
        ],
        'epg': [
          {
            'channel': 'c2',
            'name': 'Show B',
            'start': '2026-02-21T12:00:00Z',
            'end': '2026-02-21T13:00:00Z',
          },
        ],
      };

      final result = JsonEpgParser().parse(jsonEncode(map), sourceId: sourceId);

      expect(result.channels.single.id, 'c2');
      expect(result.channels.single.primaryName, 'Channel 2');

      final programme = result.programmes.single;
      expect(programme.title, 'Show B');
      expect(programme.start, DateTime.parse('2026-02-21T12:00:00Z'));
      expect(programme.stop, DateTime.parse('2026-02-21T13:00:00Z'));
    });
  });
}
