import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

List<int> ser(String body) {
  final b = utf8.encode(body);
  final p = 4+2+1+1+b.length+1;
  final r = BytesBuilder();
  r.add([p&0xFF,(p>>8)&0xFF,(p>>16)&0xFF,(p>>24)&0xFF]);
  r.add([p&0xFF,(p>>8)&0xFF,(p>>16)&0xFF,(p>>24)&0xFF]);
  r.add([0xB1,0x02]); r.add([0,0]); r.add(b); r.add([0]);
  return r.toBytes();
}
List<String> de(Uint8List buf) {
  final pk = <String>[]; var o = 0;
  while (o+12 <= buf.length) {
    final fl = ByteData.sublistView(buf, o, o+4).getUint32(0, Endian.little);
    final bl = fl - 9;
    if (bl < 0 || o+fl+4 > buf.length) break;
    pk.add(utf8.decode(buf.sublist(o+12, o+12+bl), allowMalformed: true));
    o += fl + 4;
  }
  return pk;
}
dynamic ps(String s) {
  if (s.contains('@=')) {
    var r = {};
    for (var f in s.split('/')) {
      if (f.isEmpty) continue;
      var si = f.indexOf('@=');
      if (si <= 0) continue;
      r[f.substring(0, si)] = ps(f.substring(si+2).replaceAll('@S', '/').replaceAll('@A', '@'));
    }
    return r;
  }
  return s.replaceAll('@S', '/').replaceAll('@A', '@');
}

Future<void> main() async {
  final roomId = '52319';
  final uid = '27047486';
  final stk = '11b344af7ef2cca3';
  final devid = '1976bad760eb7b35a33d922900061701';
  final rt = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
  final msg = '主播玩的是什么 有没有名字';

  print('=== 发送弹幕到房间 $roomId ===');
  print('消息: $msg');

  final ws = await WebSocket.connect('wss://danmuproxy.douyu.com:8506');

  ws.listen((data) {
    if (data is List<int>) {
      for (final p in de(Uint8List.fromList(data))) {
        final parsed = ps(p);
        if (parsed is Map) {
          final type = parsed['type']?.toString() ?? '';
          if (type == 'loginres') {
            print('[loginres] userid=${parsed["userid"]}');
          } else if (type == 'chatmsg') {
            final txt = parsed['txt']?.toString() ?? '';
            final nn = parsed['nn']?.toString() ?? '';
            print('  [$nn]: $txt');
          } else if (type == 'error') {
            print('[ERROR] ${parsed["msg"]}');
          } else if (type == 'dgb') {
            // gift, skip
          } else if (type != 'mrkl' && type != 'pingreq' && type != 'uenter' && type != 'configscreen') {
            print('[$type]');
          }
        }
      }
    }
  });

  // login
  final loginBody = 'type@=loginreq/roomid@=$roomId/devid@=$devid/rt@=$rt/ver@=21952015/vk@=0/ct@=1/uid@=$uid/stk@=$stk/';
  ws.add(ser(loginBody));
  await Future.delayed(Duration(seconds: 2));

  // joingroup
  ws.add(ser('type@=joingroup/rid@=$roomId/gid@=-9999/'));
  await Future.delayed(Duration(seconds: 1));

  // send danmaku
  final cst = DateTime.now().millisecondsSinceEpoch.toString();
  final chatBody = 'type@=chatmessage/roomid@=$roomId/content@=$msg/col@=0/pt@=0/ct@=$cst/sn@=0/ss@=0/uid@=$uid/nn@=PureLive/txt@=$msg/level@=1/dms@=5/cst@=$cst/';
  print('');
  print('>>> 发送弹幕: $msg');
  ws.add(ser(chatBody));

  // heartbeat
  Timer.periodic(Duration(seconds: 45), (_) {
    try { ws.add(ser('type@=mrkl/')); } catch (_) {}
  });

  // listen 10s
  await Future.delayed(Duration(seconds: 10));
  await ws.close();
  print('=== 完成 ===');
}