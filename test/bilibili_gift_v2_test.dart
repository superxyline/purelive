import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_message.dart';
import 'package:pure_live/core/danmaku/bilibili_danmaku.dart';
import 'package:pure_live/core/danmaku/bilibili_gift_v2.dart';

/// 手工构造 protobuf wire format 的辅助（用于伪造 SEND_GIFT_V2 的 data.pb）。
class _PbWriter {
  final out = BytesBuilder();

  void _varint(int value) {
    var v = value;
    while (true) {
      if (v & ~0x7f == 0) {
        out.addByte(v);
        break;
      }
      out.addByte((v & 0x7f) | 0x80);
      v >>= 7;
    }
  }

  void tag(int fieldNumber, int wireType) => _varint((fieldNumber << 3) | wireType);

  void str(int fieldNumber, String value) {
    final bytes = utf8.encode(value);
    tag(fieldNumber, 2);
    _varint(bytes.length);
    out.add(bytes);
  }

  void num(int fieldNumber, int value) {
    tag(fieldNumber, 0);
    _varint(value);
  }

  void msg(int fieldNumber, List<int> bytes) {
    tag(fieldNumber, 2);
    _varint(bytes.length);
    out.add(bytes);
  }

  Uint8List build() => out.toBytes();
}

Uint8List _giftItemBytes({required String iconUrl, required int count}) {
  final icon = _PbWriter();
  icon.str(1, iconUrl);

  final w = _PbWriter();
  w.num(1, 31036);
  w.str(2, '小花花');
  w.num(3, count);
  w.num(5, 100);
  w.str(8, 'gold');
  w.num(7, 200);
  w.num(10, 1757000000);
  w.str(18, '投喂');
  w.msg(35, icon.build());
  return w.build();
}

Uint8List _broadcastBytes({required int uid, required String uname, required List<int> giftItem}) {
  final w = _PbWriter();
  w.num(1, uid);
  w.str(2, uname);
  w.msg(10, giftItem);
  return w.build();
}

Uint8List _packet(List<int> body, {required int operation, int protocolVersion = 0}) {
  final bytes = Uint8List(16 + body.length);
  final header = ByteData.sublistView(bytes);
  header.setUint32(0, bytes.length, Endian.big);
  header.setUint16(4, 16, Endian.big);
  header.setUint16(6, protocolVersion, Endian.big);
  header.setUint32(8, operation, Endian.big);
  header.setUint32(12, 1, Endian.big);
  bytes.setRange(16, bytes.length, body);
  return bytes;
}

void main() {
  group('Bilibili SEND_GIFT_V2 protobuf', () {
    test('parses SendGiftBroadcast with gift item and blind gift', () {
      final blind = _PbWriter();
      blind.str(3, '梦幻盲盒');
      blind.num(6, 1000);

      final broadcast = _PbWriter();
      broadcast.num(1, 12345);
      broadcast.str(2, '测试用户');
      broadcast.msg(9, blind.build());
      broadcast.msg(10, _giftItemBytes(iconUrl: 'https://i0.hdslb.com/bfs/live/gift.png', count: 2));

      final items = parseSendGiftBroadcast(broadcast.build());

      expect(items, hasLength(1));
      final gift = items.single;
      expect(gift.uid, 12345);
      expect(gift.uname, '测试用户');
      expect(gift.giftId, 31036);
      expect(gift.giftName, '小花花');
      expect(gift.num, 2);
      expect(gift.action, '投喂');
      expect(gift.price, 100);
      expect(gift.totalCoin, 200);
      expect(gift.coinType, 'gold');
      expect(gift.timestamp, 1757000000);
      expect(gift.imgBasic, 'https://i0.hdslb.com/bfs/live/gift.png');
      expect(gift.blindGiftName, '梦幻盲盒');
      expect(gift.blindGiftPrice, 1000);
    });

    test('returns empty on malformed payload', () {
      expect(parseSendGiftBroadcastBase64('!!!not-base64!!!'), isEmpty);
      expect(parseSendGiftBroadcast(Uint8List.fromList([0xff, 0xff, 0xff])), isEmpty);
    });

    test('full chain: SEND_GIFT_V2 cmd produces gift messages', () {
      final broadcast = _broadcastBytes(
        uid: 999,
        uname: '礼物用户',
        giftItem: _giftItemBytes(iconUrl: 'https://i0.hdslb.com/bfs/live/gift.png', count: 1),
      );

      final danmaku = BiliBiliDanmaku();
      final received = <LiveMessage>[];
      danmaku.onMessage = received.add;
      final body = json.encode({
        'cmd': 'SEND_GIFT_V2',
        'data': {'pb': base64.encode(broadcast)},
      });

      danmaku.decodeMessage(_packet(utf8.encode(body), operation: 5));

      expect(received, hasLength(1));
      final gift = received.single;
      expect(gift.type, LiveMessageType.gift);
      expect(gift.userName, '礼物用户');
      expect(gift.message, '投喂 小花花');
      final data = gift.data as Map;
      expect(data['giftId'], '31036');
      expect(data['giftCount'], 1);
      expect(data['giftIcon'], 'https://i0.hdslb.com/bfs/live/gift.png');
      expect(data['price'], 200);
      expect(data['platform'], 'bilibili');
    });
  });
}
