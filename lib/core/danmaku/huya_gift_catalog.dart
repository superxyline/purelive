import 'dart:typed_data';

import 'package:pure_live/pkg/tars/codec/tars_input_stream.dart';
import 'package:pure_live/pkg/tars/codec/tars_output_stream.dart';
import 'package:pure_live/pkg/tars/codec/tars_struct.dart';

/// 虎牙礼物目录。
///
/// 6501 礼物消息里礼物名(sPropsName@20)在旧版 payload 中可能缺失，
/// 图标也不随消息下发。虎牙通过 WUP(getPropsList，PropsUIServer) 提供
/// 全量礼物目录（名称/单价/图标），经弹幕 WebSocket 发送
/// （WebSocketCommand{iCmdType=EWSCmd_WupReq}，编码参考 huya-danmu 的
/// Taf.Wup v1 实现）。收到 EWSCmd_WupRsp 后解析并缓存。
class HuyaGiftInfo {
  final int id;

  /// 礼物名（如「虎粮」「超级火箭」）。
  final String name;

  /// 单价（虎牙币，100 = 1 元），对应 iPropsYb。
  final int priceYb;

  /// 礼物图标 URL。
  final String icon;

  const HuyaGiftInfo({required this.id, required this.name, required this.priceYb, required this.icon});
}

class HuyaGiftCatalog {
  HuyaGiftCatalog._();

  static final HuyaGiftCatalog instance = HuyaGiftCatalog._();

  static const int _wupReqCmd = 3; // EWSCmd_WupReq
  static const String _servantName = 'PropsUIServer';
  static const String _funcName = 'getPropsList';

  final Map<int, HuyaGiftInfo> _gifts = <int, HuyaGiftInfo>{};

  bool get isLoaded => _gifts.isNotEmpty;

  HuyaGiftInfo? get(int giftId) => _gifts[giftId];

  void clear() => _gifts.clear();

  /// 编码 getPropsList 请求帧（经弹幕 WebSocket 发送）。
  /// [uid] 为弹幕连接的 uid，匿名时为 0。
  Uint8List buildGetPropsListRequest({required int uid}) {
    final reqStruct = _GetPropsListReq()
      ..tUserId.lUid = uid
      ..tUserId.sHuYaUA = 'webh5&1.0.0&websocket'
      ..iTemplateType = 1; // EClientTemplateType.TPL_MIRROR

    final reqOs = TarsOutputStream();
    reqStruct.writeTo(reqOs);

    // sBuffer: map(0) { "tReq": map(1) { "GetPropsListReq": <req bytes> } }
    final sBufferOs = TarsOutputStream();
    sBufferOs.writeMap(<String, Map<String, Uint8List>>{
      'tReq': <String, Uint8List>{'GetPropsListReq': reqOs.toUint8List()},
    }, 0);

    // RequestPacket
    final packet = TarsOutputStream();
    // 注:writeInt 按值自动选择 wire 类型(BYTE/SHORT/INT),服务器端
    // tars 解码按实际类型读取,与 JS 端显式 SHORT/INT 编码互相兼容。
    packet.writeInt(1, 1); // iVersion
    packet.writeInt(0, 2); // cPacketType
    packet.writeInt(0, 3); // iMessageType
    packet.writeInt(1, 4); // iRequestId
    packet.writeString(_servantName, 5);
    packet.writeString(_funcName, 6);
    packet.writeUint8List(sBufferOs.toUint8List(), 7);
    packet.writeInt(3000, 8); // iTimeout
    packet.writeMap(<String, String>{}, 9); // context
    packet.writeMap(<String, String>{}, 10); // status

    // 帧长前缀（4 字节大端，含自身长度）+ RequestPacket
    final packetBytes = packet.toUint8List();
    final lengthPrefix = ByteData(4)..setUint32(0, packetBytes.length + 4, Endian.big);
    final frame = BytesBuilder();
    frame.add(lengthPrefix.buffer.asUint8List());
    frame.add(packetBytes);

    // WebSocketCommand { iCmdType@0, vData@1 }
    final command = TarsOutputStream();
    command.writeInt(_wupReqCmd, 0);
    command.writeUint8List(frame.toBytes(), 1);
    return command.toUint8List();
  }

  /// 解析 EWSCmd_WupRsp 的 vData，填充礼物目录。
  void handleWupResponse(Uint8List vData) {
    try {
      if (vData.length <= 4) return;
      final length = ByteData.sublistView(vData).getUint32(0);
      final end = (4 + length <= vData.length) ? 4 + length : vData.length;
      final packet = TarsInputStream(vData.sublist(4, end));

      final sFuncName = packet.read('', 6, false)?.toString() ?? '';
      if (sFuncName.isNotEmpty && sFuncName != _funcName) return;
      final sBuffer = packet.read(Uint8List, 7, false) as Uint8List?;
      if (sBuffer == null || sBuffer.isEmpty) return;

      // sBuffer: map(0) { "tRsp": map(1) { "GetPropsListRsp": <rsp bytes> } }
      // 注意:TarsInputStream.readMap 对嵌套 Map 值存在 dynamic 集合推断缺陷,
      // 这里手工按 wire 顺序读两层 map。
      final outer = TarsInputStream(sBuffer);
      final rspBytes = _readNestedMapValue(outer, outerKey: 'tRsp', innerKey: 'GetPropsListRsp');
      if (rspBytes == null || rspBytes.isEmpty) return;

      final rsp = TarsInputStream(rspBytes);
      final items = rsp.readList<_PropsItem>(<_PropsItem>[_PropsItem()], 1, false);
      for (final item in items) {
        if (item.iPropsId <= 0) continue;
        _gifts[item.iPropsId] = HuyaGiftInfo(
          id: item.iPropsId,
          name: item.sPropsName,
          priceYb: item.iPropsYb,
          icon: item.icon,
        );
      }
    } catch (_) {
      // 礼物目录是尽力而为的增强，解析失败静默降级（卡片退回兜底文案）
    }
  }

  /// 读取 WUP sBuffer 的两层字符串 map,取 [outerKey] → [innerKey] 的字节值。
  static Uint8List? _readNestedMapValue(
    TarsInputStream stream, {
    required String outerKey,
    required String innerKey,
  }) {
    final head = HeadData();
    if (!stream.skipToTag(0)) return null;
    stream.readHead(head);
    if (head.type != TarsStructType.MAP.index) return null;
    final size = stream.readInt(0, true);
    for (var i = 0; i < size; i++) {
      final key = stream.read('', 0, true)?.toString() ?? '';
      if (key != outerKey) continue;
      if (!stream.skipToTag(1)) return null;
      stream.readHead(head);
      if (head.type != TarsStructType.MAP.index) return null;
      final innerSize = stream.readInt(0, true);
      for (var j = 0; j < innerSize; j++) {
        final inner = stream.read('', 0, true)?.toString() ?? '';
        final value = stream.read(Uint8List, 1, false) as Uint8List?;
        if (inner == innerKey && value != null) return value;
      }
    }
    return null;
  }

}

class _UserId extends TarsStruct {
  int lUid = 0;
  String sHuYaUA = '';

  @override
  void writeTo(TarsOutputStream os) {
    os.writeInt(lUid, 0);
    os.writeString('', 1); // sGuid
    os.writeString('', 2); // sToken
    os.writeString(sHuYaUA, 3);
    os.writeString('', 4); // sCookie
  }

  @override
  void readFrom(TarsInputStream inputStream) {}

  @override
  Object deepCopy() => _UserId()..lUid = lUid..sHuYaUA = sHuYaUA;

  @override
  void displayAsString(StringBuffer sb, int level) {}
}

class _GetPropsListReq extends TarsStruct {
  final _UserId tUserId = _UserId();
  int iTemplateType = 0;
  int lPresenterUid = 0;
  int lSid = 0;
  int lSubSid = 0;

  @override
  void writeTo(TarsOutputStream os) {
    os.writeTarsStruct(tUserId, 1);
    os.writeString('', 2); // sMd5
    os.writeInt(iTemplateType, 3);
    os.writeString('', 4); // sVersion
    os.writeInt(0, 5); // iAppId
    os.writeInt(lPresenterUid, 6);
    os.writeInt(lSid, 7);
    os.writeInt(lSubSid, 8);
  }

  @override
  void readFrom(TarsInputStream inputStream) {}

  @override
  Object deepCopy() => _GetPropsListReq();

  @override
  void displayAsString(StringBuffer sb, int level) {}
}

class _PropsIdentity extends TarsStruct {
  String sPropsPic18 = '';
  String sPropsPic24 = '';
  String sPropsPicGif = '';

  @override
  void readFrom(TarsInputStream inputStream) {
    sPropsPic18 = inputStream.readString(2, false);
    sPropsPic24 = inputStream.readString(3, false);
    sPropsPicGif = inputStream.readString(4, false);
  }

  @override
  void writeTo(TarsOutputStream os) {}

  @override
  Object deepCopy() => _PropsIdentity();

  @override
  void displayAsString(StringBuffer sb, int level) {}
}

class _PropsItem extends TarsStruct {
  int iPropsId = 0;
  String sPropsName = '';
  int iPropsYb = 0;
  final List<_PropsIdentity> vPropsIdentity = <_PropsIdentity>[];

  String get icon {
    for (final identity in vPropsIdentity) {
      if (identity.sPropsPic24.isNotEmpty) return identity.sPropsPic24;
    }
    for (final identity in vPropsIdentity) {
      if (identity.sPropsPic18.isNotEmpty) return identity.sPropsPic18;
    }
    for (final identity in vPropsIdentity) {
      if (identity.sPropsPicGif.isNotEmpty) return identity.sPropsPicGif;
    }
    return '';
  }

  @override
  void readFrom(TarsInputStream inputStream) {
    iPropsId = inputStream.readInt(1, false);
    sPropsName = inputStream.readString(2, false);
    iPropsYb = inputStream.readInt(3, false);
    vPropsIdentity.clear();
    vPropsIdentity.addAll(
      inputStream.readList<_PropsIdentity>(<_PropsIdentity>[_PropsIdentity()], 16, false),
    );
  }

  @override
  void writeTo(TarsOutputStream os) {}

  @override
  Object deepCopy() => _PropsItem();

  @override
  void displayAsString(StringBuffer sb, int level) {}
}
