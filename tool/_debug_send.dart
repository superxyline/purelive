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
    for (var f in s.split('/')) { if (f.isEmpty) continue; var si = f.indexOf('@='); if (si <= 0) continue; r[f.substring(0, si)] = ps(f.substring(si+2).replaceAll('@S', '/').replaceAll('@A', '@')); }
    return r;
  }
  return s.replaceAll('@S', '/').replaceAll('@A', '@');
}

Future<void> main() async {
  final roomId = '10917030';
  final uid = '27047486';
  final stk = '11b344af7ef2cca3';
  final devid = '1976bad760eb7b35a33d922900061701';
  final rt = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();

  final ws = await WebSocket.connect('wss://danmuproxy.douyu.com:8506');

  ws.listen((data) {
    if (data is! List<int>) return;
    for (final p in de(Uint8List.fromList(data))) {
      final parsed = ps(p);
      if (parsed is Map) {
        print('  << ${parsed}');
      }
    }
  });

  // login
  final loginBody = 'type@=loginreq/roomid@=$roomId/devid@=$devid/rt@=$rt/ver@=21952015/vk@=0/ct@=1/uid@=$uid/stk@=$stk/';
  print('>>> loginreq');
  ws.add(ser(loginBody));
  await Future.delayed(Duration(seconds: 3));

  // joingroup
  print('>>> joingroup');
  ws.add(ser('type@=joingroup/rid@=$roomId/gid@=-9999/'));
  await Future.delayed(Duration(seconds: 2));

  // heartbeat
  print('>>> heartbeat');
  ws.add(ser('type@=mrkl/'));
  await Future.delayed(Duration(seconds: 1));

  // 尝试多种弹幕格式
  final cst = DateTime.now().millisecondsSinceEpoch.toString();
  final msg = '主播你好';

  // 格式1: 最小格式
  final f1 = 'type@=chatmessage/roomid@=$roomId/content@=$msg/uid@=$uid/stk@=$stk/nn@=PureLive/txt@=$msg/dms@=5/cst@=$cst/';
  print('>>> send v1 (minimal)');
  ws.add(ser(f1));
  await Future.delayed(Duration(seconds: 3));

  // 格式2: 带更多字段
  final f2 = 'type@=chatmessage/roomid@=$roomId/content@=$msg/col@=0/pt@=0/uid@=$uid/stk@=$stk/nn@=PureLive/txt@=$msg/level@=1/dms@=5/cst@=$cst/biz@=1/avs@=0/pc@=1/';
  print('>>> send v2 (with biz/avs/pc)');
  ws.add(ser(f2));
  await Future.delayed(Duration(seconds: 3));

  // 格式3: 带 sessionid=0
  final f3 = 'type@=chatmessage/roomid@=$roomId/content@=$msg/col@=0/pt@=0/uid@=$uid/stk@=$stk/nn@=PureLive/txt@=$msg/level@=1/dms@=5/cst@=$cst/sid@=0/';
  print('>>> send v3 (with sid)');
  ws.add(ser(f3));
  await Future.delayed(Duration(seconds: 5));

  await ws.close();
  print('done');
}