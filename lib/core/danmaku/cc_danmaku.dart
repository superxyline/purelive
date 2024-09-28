import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:pure_live/common/models/live_message.dart';
import 'package:pure_live/core/common/core_log.dart';
import 'package:pure_live/core/common/web_socket_util.dart';
import 'package:pure_live/core/interface/live_danmaku.dart';
import 'package:uuid/uuid.dart';

import '../common/binary_writer.dart';


class CCDanmakuArgs{
  int channelId;
  int gameType;
  int roomId;
  CCDanmakuArgs({
    required this.channelId,
    required this.roomId,
    required this.gameType,
  });

}

class CCDanmaku implements LiveDanmaku {
  @override
  int heartbeatTime = 45 * 1000;

  @override
  Function(LiveMessage msg)? onMessage;
  @override
  Function(String msg)? onClose;
  @override
  Function()? onReady;
  String serverUrl = "wss://weblink.cc.163.com";

  WebScoketUtils? webScoketUtils;

  @override
  Future start(dynamic args) async {
    webScoketUtils = WebScoketUtils(
      url: serverUrl,
      heartBeatTime: heartbeatTime,
      onMessage: (e) {
        decodeMessage(e);
      },
      onReady: () {
        onReady?.call();
        joinRoom(args);
      },
      onHeartBeat: () {
        heartbeat();
      },
      onReconnect: () {
        onClose?.call("与服务器断开连接，正在尝试重连");
      },
      onClose: (e) {
        onClose?.call("服务器连接失败$e");
      },
    );
    webScoketUtils?.connect();
  }

  List<int> get_reg() {
    var sid = 6144;
    var cid = 2;
    var update_req_info = {
      '22': 640,
      '23': 360,
      '24': 'web',
      '25': 'Linux',
      '29': '163_cc',
      '30': '',
      '31':
      'Mozilla/5.0 (Linux; Android 5.0; SM-G900P Build/LRX21T) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/72.0.3626.121 Mobile Safari/537.36',
    };
    var uuid = Uuid();
    var device_token = uuid.v1() + '@web.cc.163.com';
    var macAdd = device_token;
    var data = {
      'web-cc': DateTime
          .now()
          .microsecondsSinceEpoch,
      'macAdd': macAdd,
      'device_token': device_token,
      'page_uuid': uuid.v1(),
      'update_req_info': update_req_info,
      'system': 'win',
      'memory': 1,
      'version': 1,
      'webccType': 4253,
    };

    /// 在 Dart 中，可以使用 ByteData 和 ByteBuffer 类来实现类似 Python 中 struct.pack() 的功能
    // var reg_data = struct('<HHI').pack(sid, cid, 0) + encode_dict(data);

    var writer = BinaryWriter([]);
    writer.writeInt(sid, 2, endian: Endian.little);
    writer.writeInt(cid, 2, endian: Endian.little);
    // writer.writeInt(0, 1, endian: Endian.little);

    writer.writeBytes(encodeDict(data));

    return writer.buffer;
  }

  List<int> get_beat(){
    var sid = 6144;
    var cid = 5;
    var data = {};

    var writer = BinaryWriter([]);
    writer.writeInt(sid, 2, endian: Endian.little);
    writer.writeInt(cid, 2, endian: Endian.little);
    // writer.writeInt(0, 1, endian: Endian.little);

    // writer.writeBytes(encodeDict(data));
    return writer.buffer;
  }

  List<int> encodeStr(String r) {
    List<int> buffer = utf8.encode(r);
    return buffer;
  }

  Uint8List createUint8ListFromHexString(String hex) {
    var result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      var num = hex.substring(i, i + 2);
      var byte = int.parse(num, radix: 16);
      result[i ~/ 2] = byte;
    }
    return result;
  }

  convert(int source, {Type type = Type.WORD}) {
    var s = source.toRadixString(16);
    var pre = '0';
    if (s.length % 2 == 1) {
      s = pre + s;
    }
    List list = <int>[];
    var uint8list = createUint8ListFromHexString(s);
    switch (type) {
      case Type.BYTE:
        break;
      case Type.WORD:
        if (uint8list.length == 1) {
          list.add(0);
        }
        break;
      case Type.DWORD:
        for (var i = 0; i < 4 - uint8list.length; i++) {
          list.add(0);
        }
        break;
      case Type.STRING:
        // TODO: Handle this case.
    }
    list.addAll(uint8list);
    return list;
  }


  List<int> encodeNum(int r) {
    var writer = BinaryWriter([]);
    if(r < 256){
      writer.writeInt(r, 1, endian: Endian.little);
    } else if(r < 65525) {
      writer.writeInt(r, 2, endian: Endian.little);
    } else {
      writer.writeInt(r, 4, endian: Endian.little);
    }
    return writer.buffer;
  }

  List<int> encodeList(List list){
    var writer = BinaryWriter([]);
    for (var value in list) {
      if(value.runtimeType == Map) {
        writer.writeBytes(encodeDict(value));
        continue;
      }

      if(value.runtimeType == double) {
        writer.writeDouble(value, 8, endian: Endian.little);
        continue;
      }
      if(value.runtimeType == int) {
        writer.writeBytes(encodeNum(value));
        continue;
      }
      if(value.runtimeType == String) {
        writer.writeBytes(encodeStr(value));
        continue;
      }
      if(value.runtimeType == List) {
        writer.writeBytes(encodeList(value));
        continue;
      }
    }
    return writer.buffer;
  }

  List<int> encodeDict(Map d) {
    var writer = BinaryWriter([]);
    for (var key in d.keys) {
      var keyBytes = utf8.encode(key);
      writer.writeBytes(keyBytes);
      var value = d[key];
      if(value.runtimeType == Map) {
        writer.writeBytes(encodeDict(value));
        continue;
      }

      if(value.runtimeType == double) {
        writer.writeDouble(value, 8, endian: Endian.little);
        continue;
      }

      if(value.runtimeType == int) {
        writer.writeBytes(encodeNum(value));
        continue;
      }

      if(value.runtimeType == String) {
        writer.writeBytes(encodeStr(value));
        continue;
      }

      if(value.runtimeType == List) {
        writer.writeBytes(encodeList(value));
        continue;
      }

    }
    return writer.buffer;
  }

  void joinRoom(args) {

    // 先注册信息
    webScoketUtils?.sendMessage(get_reg());

    var args2 = args as CCDanmakuArgs;
    var sid = 512;
    var cid = 1;
    // channel_id, gametype, roomId
    var data = {
      'roomId': args2.roomId,
      'cid': args2.channelId,
      'gametype': args2.gameType,
    };

    var writer = BinaryWriter([]);
    writer.writeInt(sid, 2, endian: Endian.little);
    writer.writeInt(cid, 2, endian: Endian.little);
    // writer.writeInt(0, 1, endian: Endian.little);
    writer.writeBytes(encodeDict(data));
    webScoketUtils?.sendMessage(writer.buffer);
  }

  @override
  void heartbeat() {
    webScoketUtils?.sendMessage(get_beat());
  }

  @override
  Future stop() async {
    onMessage = null;
    onClose = null;
    webScoketUtils?.close();
  }

  void decodeMessage(List<int> data) {
    try {
      String? result = deserialize(data);
      if (result == null) {
        return;
      }
      var jsonData = sttToJObject(result);

      var type = jsonData["type"]?.toString();
      //斗鱼好像不会返回人气值
      //有些直播间存在阴间弹幕，不知道什么情况
      if (type == "chatmsg") {
        var col = int.tryParse(jsonData["col"].toString()) ?? 0;
        var liveMsg = LiveMessage(
          type: LiveMessageType.chat,
          userName: jsonData["nn"].toString(),
          message: jsonData["txt"].toString(),
          color: getColor(col),
        );

        onMessage?.call(liveMsg);
      }
    } catch (e) {
      CoreLog.error(e);
    }
  }

  List<int> serializeDouyu(String body) {
    try {
      const int clientSendToServer = 689;
      const int encrypted = 0;
      const int reserved = 0;

      List<int> buffer = utf8.encode(body);

      var writer = BinaryWriter([]);
      writer.writeInt(4 + 4 + body.length + 1, 4, endian: Endian.little);
      writer.writeInt(4 + 4 + body.length + 1, 4, endian: Endian.little);
      writer.writeInt(clientSendToServer, 2, endian: Endian.little);
      writer.writeInt(encrypted, 1, endian: Endian.little);
      writer.writeInt(reserved, 1, endian: Endian.little);
      writer.writeBytes(buffer);
      writer.writeInt(0, 1, endian: Endian.little);
      return writer.buffer;
    } catch (e) {
      CoreLog.error(e);
      return [];
    }
  }

  String? deserialize(List<int> buffer) {
    try {
      var reader = BinaryReader(Uint8List.fromList(buffer));
      int fullMsgLength = reader.readInt32(endian: Endian.little); //fullMsgLength
      CoreLog.d("$fullMsgLength");
      reader.readInt32(endian: Endian.little); //fullMsgLength2
      int bodyLength = fullMsgLength - 9;
      reader.readShort(endian: Endian.little); //packType
      reader.readByte(endian: Endian.little); //encrypted
      reader.readByte(endian: Endian.little); //reserved

      var bytes = reader.readBytes(bodyLength);

      reader.readByte(endian: Endian.little); //固定为0
      return utf8.decode(bytes);
    } catch (e) {
      CoreLog.error(e);
      return null;
    }
  }

  //辣鸡STT
  dynamic sttToJObject(String str) {
    if (str.contains("//")) {
      var result = [];
      for (var field in str.split("//")) {
        if (field.isEmpty) {
          continue;
        }
        result.add(sttToJObject(field));
      }
      return result;
    }
    if (str.contains("@=")) {
      var result = {};
      for (var field in str.split('/')) {
        if (field.isEmpty) {
          continue;
        }
        var tokens = field.split("@=");
        var k = tokens[0];
        var v = unscapeSlashAt(tokens[1]);
        result[k] = sttToJObject(v);
      }
      return result;
    } else if (str.contains("@A=")) {
      return sttToJObject(unscapeSlashAt(str));
    } else {
      return unscapeSlashAt(str);
    }
  }

  String unscapeSlashAt(String str) {
    return str.replaceAll("@S", "/").replaceAll("@A", "@");
  }

  LiveMessageColor getColor(int type) {
    switch (type) {
      case 1:
        return LiveMessageColor(255, 0, 0);
      case 2:
        return LiveMessageColor(30, 135, 240);
      case 3:
        return LiveMessageColor(122, 200, 75);
      case 4:
        return LiveMessageColor(255, 127, 0);
      case 5:
        return LiveMessageColor(155, 57, 244);
      case 6:
        return LiveMessageColor(255, 105, 180);
      default:
        return LiveMessageColor.white;
    }
  }
}

enum Type {
  BYTE, //1
  WORD, //2
  DWORD, //4
  STRING
}