import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/danmaku/huya_gift_catalog.dart';
import 'package:pure_live/pkg/tars/codec/tars_input_stream.dart';
import 'package:pure_live/pkg/tars/codec/tars_output_stream.dart';
import 'package:pure_live/pkg/tars/codec/tars_struct.dart';

/// 与生产 _UserId 字段 tag 一致的测试桩。
class _TUserId extends TarsStruct {
  int lUid = 0;
  String sHuYaUA = '';

  @override
  void readFrom(TarsInputStream inputStream) {
    lUid = inputStream.readInt(0, false);
    sHuYaUA = inputStream.readString(3, false);
  }

  @override
  void writeTo(TarsOutputStream os) {
    os.writeInt(lUid, 0);
    os.writeString(sHuYaUA, 3);
  }

  @override
  Object deepCopy() => _TUserId();

  @override
  void displayAsString(StringBuffer sb, int level) {}
}

/// 与生产 _PropsItem 字段 tag 一致的测试桩，用于构造响应帧。
class _TIdentity extends TarsStruct {
  String pic24 = '';

  @override
  void readFrom(TarsInputStream inputStream) {
    pic24 = inputStream.readString(3, false);
  }

  @override
  void writeTo(TarsOutputStream os) {
    os.writeString(pic24, 3);
  }

  @override
  Object deepCopy() => _TIdentity()..pic24 = pic24;

  @override
  void displayAsString(StringBuffer sb, int level) {}
}

class _TItem extends TarsStruct {
  int id = 0;
  String name = '';
  int priceYb = 0;
  List<_TIdentity> identities = <_TIdentity>[];

  @override
  void readFrom(TarsInputStream inputStream) {
    id = inputStream.readInt(1, false);
    name = inputStream.readString(2, false);
    priceYb = inputStream.readInt(3, false);
    identities = inputStream.readList<_TIdentity>(<_TIdentity>[_TIdentity()], 16, false);
  }

  @override
  void writeTo(TarsOutputStream os) {
    os.writeInt(id, 1);
    os.writeString(name, 2);
    os.writeInt(priceYb, 3);
    os.writeList(identities, 16);
  }

  @override
  Object deepCopy() => _TItem();

  @override
  void displayAsString(StringBuffer sb, int level) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Huya gift catalog WUP', () {
    setUp(() => HuyaGiftCatalog.instance.clear());

    test('buildGetPropsListRequest encodes the expected frame', () {
      final request = HuyaGiftCatalog.instance.buildGetPropsListRequest(uid: 12345);

      // WebSocketCommand: iCmdType@0 = 3 (EWSCmd_WupReq), vData@1
      final command = TarsInputStream(request);
      expect(command.readInt(0, true), 3);
      final vData = command.readBytes(1, true);

      // vData = [4字节大端长度(含自身)][RequestPacket]
      final length = ByteData.sublistView(vData).getUint32(0);
      expect(length, vData.length);
      final packet = TarsInputStream(vData.sublist(4));

      expect(packet.readInt(1, false), 1); // iVersion
      expect(packet.readString(5, false), 'PropsUIServer');
      expect(packet.readString(6, false), 'getPropsList');

      // sBuffer: map { "tReq": { "GetPropsListReq": bytes } }(手工读,库的嵌套
      // readMap 有 dynamic 推断缺陷)
      final sBuffer = packet.readBytes(7, false);
      final outer = TarsInputStream(sBuffer);
      final hd = HeadData();
      expect(outer.skipToTag(0), isTrue);
      outer.readHead(hd);
      expect(hd.type, TarsStructType.MAP.index);
      expect(outer.readInt(0, true), 1);
      expect(outer.read('', 0, true), 'tReq');
      expect(outer.skipToTag(1), isTrue);
      outer.readHead(hd);
      expect(hd.type, TarsStructType.MAP.index);
      expect(outer.readInt(0, true), 1);
      expect(outer.read('', 0, true), 'GetPropsListReq');
      final reqBytes = outer.read(Uint8List, 1, true) as Uint8List;
      expect(reqBytes, isNotEmpty);

      // GetPropsListReq: tUserId@1 struct { lUid@0 = 12345, sHuYaUA@3 }, iTemplateType@3 = 1
      final req = TarsInputStream(reqBytes);
      final userId = req.readTarsStruct(_TUserId(), 1, true) as _TUserId;
      expect(userId.lUid, 12345);
      expect(userId.sHuYaUA, 'webh5&1.0.0&websocket');
      expect(req.readInt(3, false), 1); // iTemplateType TPL_MIRROR
    });

    test('handleWupResponse fills the catalog from a WUP response', () {
      // GetPropsListRsp: vPropsItemList@1 = [PropsItem{id@1, name@2, yb@3, identities@16}]
      final rsp = TarsOutputStream();
      rsp.writeList(
        <_TItem>[
          _TItem()
            ..id = 31036
            ..name = '虎粮'
            ..priceYb = 100
            ..identities = <_TIdentity>[_TIdentity()..pic24 = 'https://huyaimg.msstatic.com/gift_24.png'],
        ],
        1,
      );

      // sBuffer: map { "tRsp": { "GetPropsListRsp": rspBytes } }
      final sBuffer = TarsOutputStream();
      sBuffer.writeMap(<String, Map<String, Uint8List>>{
        'tRsp': <String, Uint8List>{'GetPropsListRsp': rsp.toUint8List()},
      }, 0);

      // RequestPacket { sFuncName@6, sBuffer@7 }
      final packet = TarsOutputStream();
      packet.writeString('getPropsList', 6);
      packet.writeUint8List(sBuffer.toUint8List(), 7);
      final packetBytes = packet.toUint8List();

      // 帧长前缀
      final lengthPrefix = ByteData(4)..setUint32(0, packetBytes.length + 4, Endian.big);
      final frame = BytesBuilder()
        ..add(lengthPrefix.buffer.asUint8List())
        ..add(packetBytes);

      HuyaGiftCatalog.instance.handleWupResponse(frame.toBytes());

      final info = HuyaGiftCatalog.instance.get(31036);
      expect(info, isNotNull);
      expect(info!.name, '虎粮');
      expect(info.priceYb, 100);
      expect(info.icon, 'https://huyaimg.msstatic.com/gift_24.png');
    });

    test('handleWupResponse ignores unrelated or malformed frames', () {
      HuyaGiftCatalog.instance.handleWupResponse(Uint8List.fromList([0, 0, 0, 1, 0xff]));
      expect(HuyaGiftCatalog.instance.isLoaded, isFalse);
    });
  });
}
