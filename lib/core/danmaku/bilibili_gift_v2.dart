import 'dart:convert';
import 'dart:typed_data';

/// B站直播 SEND_GIFT_V2（protobuf 礼物消息）解析。
///
/// 2026-07 起部分直播间礼物下发由 JSON `SEND_GIFT` 灰度切换为
/// `SEND_GIFT_V2`：`data.pb` 为 base64 编码的 SendGiftBroadcast 消息。
/// 字段号与 blivedm（xfgryujk）的 models/pb.py 对齐：
/// ```
/// SendGiftBroadcast:  uid@1 uname@2 face@3 guard_level@5 medal_info@8
///                     blind_gift@9 gift_list@10(repeated)
/// SendGiftV2GiftItem: gift_id@1 gift_name@2 num@3 gift_type@4 price@5
///                     total_coin@7 coin_type@8 tid@9 timestamp@10 rnd@12
///                     action@18 gift_info@35{ img_basic@1 }
/// SendGiftV2BlindGift: original_gift_name@3 original_gift_price@6
/// ```
/// 出于精简只手写解析礼物卡片需要的字段，未知字段按 wire type 跳过。

class BiliGiftV2Item {
  final int uid;
  final String uname;
  final int giftId;
  final String giftName;
  final int num;
  final String action;
  final int price;
  final int totalCoin;
  final String coinType;
  final int timestamp;
  final String imgBasic;
  final String blindGiftName;
  final int blindGiftPrice;

  const BiliGiftV2Item({
    required this.uid,
    required this.uname,
    required this.giftId,
    required this.giftName,
    required this.num,
    required this.action,
    required this.price,
    required this.totalCoin,
    required this.coinType,
    required this.timestamp,
    required this.imgBasic,
    required this.blindGiftName,
    required this.blindGiftPrice,
  });
}

/// 解析 base64 编码的 SendGiftBroadcast；解析失败返回空列表。
List<BiliGiftV2Item> parseSendGiftBroadcastBase64(String base64Data) {
  try {
    return parseSendGiftBroadcast(base64Decode(base64Data));
  } catch (_) {
    return const <BiliGiftV2Item>[];
  }
}

List<BiliGiftV2Item> parseSendGiftBroadcast(Uint8List bytes) {
  try {
    final reader = _PbReader(bytes);
    var uid = 0;
    var uname = '';
    String? blindGiftName;
    int? blindGiftPrice;
    // (giftId, giftName, num, action, price, totalCoin, coinType, timestamp, imgBasic)
    final gifts = <(int, String, int, String, int, int, String, int, String)>[];

    while (reader.hasMore) {
      final head = reader.readTag();
      switch (head.fieldNumber) {
        case 1:
          uid = reader.readVarint();
          break;
        case 2:
          uname = reader.readString();
          break;
        case 9:
          final blind = _parseBlindGift(reader.readBytes());
          if (blind != null) {
            blindGiftName = blind.$1;
            blindGiftPrice = blind.$2;
          }
          break;
        case 10:
          final gift = _parseGiftItem(reader.readBytes());
          if (gift != null) gifts.add(gift);
          break;
        default:
          reader.skipField(head.wireType);
      }
    }

    return gifts
        .map(
          (g) => BiliGiftV2Item(
            uid: uid,
            uname: uname,
            giftId: g.$1,
            giftName: g.$2,
            num: g.$3,
            action: g.$4,
            price: g.$5,
            totalCoin: g.$6,
            coinType: g.$7,
            timestamp: g.$8,
            imgBasic: g.$9,
            blindGiftName: blindGiftName ?? '',
            blindGiftPrice: blindGiftPrice ?? 0,
          ),
        )
        .toList();
  } catch (_) {
    return const <BiliGiftV2Item>[];
  }
}

// 解析单个礼物项，返回 (giftId, giftName, num, action, price, totalCoin, coinType, timestamp, imgBasic)
(int, String, int, String, int, int, String, int, String)? _parseGiftItem(Uint8List bytes) {
  final reader = _PbReader(bytes);
  var giftId = 0;
  var giftName = '';
  var num = 0;
  var action = '';
  var price = 0;
  var totalCoin = 0;
  var coinType = '';
  var timestamp = 0;
  var imgBasic = '';

  while (reader.hasMore) {
    final head = reader.readTag();
    switch (head.fieldNumber) {
      case 1:
        giftId = reader.readVarint();
        break;
      case 2:
        giftName = reader.readString();
        break;
      case 3:
        num = reader.readVarint();
        break;
      case 5:
        price = reader.readVarint();
        break;
      case 7:
        totalCoin = reader.readVarint();
        break;
      case 8:
        coinType = reader.readString();
        break;
      case 10:
        timestamp = reader.readVarint();
        break;
      case 18:
        action = reader.readString();
        break;
      case 35:
        imgBasic = _parseGiftInfoImgBasic(reader.readBytes());
        break;
      default:
        reader.skipField(head.wireType);
    }
  }
  if (giftName.isEmpty || num <= 0) return null;
  return (giftId, giftName, num, action, price, totalCoin, coinType, timestamp, imgBasic);
}

String _parseGiftInfoImgBasic(Uint8List bytes) {
  final reader = _PbReader(bytes);
  while (reader.hasMore) {
    final head = reader.readTag();
    if (head.fieldNumber == 1 && head.wireType == 2) {
      return reader.readString();
    }
    reader.skipField(head.wireType);
  }
  return '';
}

(String, int)? _parseBlindGift(Uint8List bytes) {
  final reader = _PbReader(bytes);
  var name = '';
  var price = 0;
  while (reader.hasMore) {
    final head = reader.readTag();
    switch (head.fieldNumber) {
      case 3:
        name = reader.readString();
        break;
      case 6:
        price = reader.readVarint();
        break;
      default:
        reader.skipField(head.wireType);
    }
  }
  return (name, price);
}

class _PbHead {
  final int fieldNumber;
  final int wireType;
  const _PbHead(this.fieldNumber, this.wireType);
}

class _PbReader {
  final Uint8List data;
  int pos = 0;

  _PbReader(this.data);

  bool get hasMore => pos < data.length;

  _PbHead readTag() {
    final tag = readVarint();
    return _PbHead(tag >> 3, tag & 0x07);
  }

  int readVarint() {
    var result = 0;
    var shift = 0;
    while (true) {
      if (pos >= data.length) throw const FormatException('unexpected end');
      final b = data[pos++];
      result |= (b & 0x7f) << shift;
      if (b & 0x80 == 0) break;
      shift += 7;
    }
    return result;
  }

  String readString() {
    final len = readVarint();
    final text = utf8.decode(data.sublist(pos, pos + len), allowMalformed: true);
    pos += len;
    return text;
  }

  Uint8List readBytes() {
    final len = readVarint();
    final out = Uint8List.sublistView(data, pos, pos + len);
    pos += len;
    return out;
  }

  void skipField(int wireType) {
    switch (wireType) {
      case 0:
        readVarint();
        break;
      case 1:
        pos += 8;
        break;
      case 2:
        final len = readVarint();
        pos += len;
        break;
      case 5:
        pos += 4;
        break;
      default:
        throw FormatException('unsupported wire type: $wireType');
    }
  }
}
