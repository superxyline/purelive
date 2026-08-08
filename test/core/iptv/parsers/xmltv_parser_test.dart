import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/iptv/parsers/xmltv_parser.dart';

const _xml = '''<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <channel id="cctv1.example.com">
    <display-name lang="zh">CCTV-1</display-name>
    <display-name lang="zh">1</display-name>
    <icon src="http://logo/cctv1.png"/>
  </channel>
  <programme start="20260221120000 +0800" stop="20260221130000 +0800" channel="cctv1.example.com">
    <title lang="zh">新闻联播</title>
    <desc lang="zh">每日新闻</desc>
    <category lang="zh">新闻</category>
    <new/>
  </programme>
</tv>''';

void main() {
  group('XmltvParser', () {
    const sourceId = 'epg_source';

    test('parses channels and programmes with timezone offset', () {
      final result = XmltvParser().parse(_xml, sourceId: sourceId);

      expect(result.channels, hasLength(1));
      expect(result.programmes, hasLength(1));

      final channel = result.channels.single;
      expect(channel.id, 'cctv1.example.com');
      expect(channel.sourceId, sourceId);
      expect(channel.primaryName, 'CCTV-1');
      expect(channel.iconUrl, 'http://logo/cctv1.png');
      expect(channel.number, '1');

      final programme = result.programmes.single;
      expect(programme.channelId, 'cctv1.example.com');
      expect(programme.title, '新闻联播');
      expect(programme.description, '每日新闻');
      expect(programme.category, '新闻');
      expect(programme.isNew, isTrue);
      // 2026-02-21 12:00 +08:00 == 04:00 UTC
      expect(programme.start, DateTime.utc(2026, 2, 21, 4));
      expect(programme.stop, DateTime.utc(2026, 2, 21, 5));
    });

    test('parses date without timezone as UTC', () {
      const xml = '''<tv>
  <programme start="20260221120000" stop="20260221130000" channel="c1">
    <title>T</title>
  </programme>
</tv>''';

      final result = XmltvParser().parse(xml, sourceId: sourceId);
      final programme = result.programmes.single;

      expect(programme.start, DateTime.utc(2026, 2, 21, 12));
      expect(programme.stop, DateTime.utc(2026, 2, 21, 13));
    });

    test('skips programme entries missing required attributes', () {
      const xml = '''<tv>
  <programme start="20260221120000" channel="c1">
    <title>T</title>
  </programme>
</tv>''';

      final result = XmltvParser().parse(xml, sourceId: sourceId);

      expect(result.programmes, isEmpty);
    });

    test('decompresses gzip bytes automatically', () {
      final gz = GZipEncoder().encode(utf8.encode(_xml));
      expect(gz, isNotNull);

      final result = XmltvParser().parseBytes(gz, sourceId: sourceId);

      expect(result.channels, hasLength(1));
      expect(result.programmes, hasLength(1));
    });
  });
}
