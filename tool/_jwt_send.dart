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

Future<void> tryWs(String roomId, String uid, String stk, String devid, String loginBody, String label) async {
  print('\n=== $label ===');
  final ws = await WebSocket.connect('wss://danmuproxy.douyu.com:8506');
  String result = 'timeout';

  ws.listen((data) {
    if (data is! List<int>) return;
    for (final p in de(Uint8List.fromList(data))) {
      final parsed = ps(p);
      if (parsed is Map && parsed['type']?.toString() == 'loginres') {
        result = 'uid=${parsed["userid"]} sid=${parsed["sessionid"]} nick="${parsed["nickname"]}"';
        print('  $result');
      }
    }
  });

  ws.add(ser(loginBody));
  await Future.delayed(Duration(seconds: 3));

  if (result.contains('sid=0') || result == 'timeout') {
    print('  sessionid=0, 尝试发弹幕看看...');
    ws.add(ser('type@=joingroup/rid@=$roomId/gid@=-9999/'));
    await Future.delayed(Duration(seconds: 1));
    final cst = DateTime.now().millisecondsSinceEpoch.toString();
    ws.add(ser('type@=chatmessage/roomid@=$roomId/content@=test/col@=0/uid@=$uid/stk@=$stk/nn@=PL/txt@=test/dms@=5/cst@=$cst/'));
    await Future.delayed(Duration(seconds: 3));
  }

  await ws.close();
}

Future<void> main() async {
  final roomId = '10917030';
  final uid = '27047486';
  final stk = '11b344af7ef2cca3';
  final dmjwt = 'eyJhbGciOiJtZDUiLCJ0eXAiOiJKV1QifQ.eyJjdCI6MCwiaWF0IjoxNzg4MTc0OTg5LCJhdWQiOlsiZG0iXSwibHRraWQiOjEwNzE3NTU3MCwiYml6IjoxLCJ1aWQiOjI3MDQ3NDg2LCJleHAiOjE3ODg3Nzk3ODksInN1YiI6InN0Iiwia2V5IjoiZHktand0LW1kNSIsInN0ayI6IjExYjM0NGFmN2VmMmNjYTMifQ.ODJmYmE4MDYxM2ZlZTZiMTE1ZDEzYTgwODQ5Y2JmNWM';
  final devid = '1976bad760eb7b35a33d922900061701';
  final rt = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();

  // S1: 仅 uid + stk
  await tryWs(roomId, uid, stk, devid,
    'type@=loginreq/roomid@=$roomId/devid@=$devid/rt@=$rt/ver@=21952015/vk@=0/ct@=1/uid@=$uid/stk@=$stk/',
    'S1: uid+stk');

  // S2: uid + stk + dmjwt as aa1
  await tryWs(roomId, uid, stk, devid,
    'type@=loginreq/roomid@=$roomId/devid@=$devid/rt@=$rt/ver@=21952015/vk@=0/ct@=1/uid@=$uid/stk@=$stk/aa1@=$dmjwt/',
    'S2: uid+stk+dmjwt');

  // S3: uid + dmjwt as stk
  await tryWs(roomId, uid, stk, devid,
    'type@=loginreq/roomid@=$roomId/devid@=$devid/rt@=$rt/ver@=21952015/vk@=0/ct@=1/uid@=$uid/stk@=$dmjwt/',
    'S3: uid+dmjwt_as_stk');

  // S4: uid + stk + rt 长格式
  final rtMs = DateTime.now().millisecondsSinceEpoch.toString();
  await tryWs(roomId, uid, stk, devid,
    'type@=loginreq/roomid@=$roomId/devid@=$devid/rt@=$rtMs/ver@=21952015/vk@=0/ct@=1/uid@=$uid/stk@=$stk/',
    'S4: uid+stk+rt_ms');

  print('\nDone');
}