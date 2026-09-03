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

Future<String?> tryLogin(String roomId, String loginBody, String label) async {
  print('\n=== $label ===');

  final ws = await WebSocket.connect('wss://danmuproxy.douyu.com:8506');
  final completer = Completer<String?>();

  ws.listen((data) {
    if (data is List<int>) {
      for (final p in de(Uint8List.fromList(data))) {
        final parsed = ps(p);
        if (parsed is Map && parsed['type']?.toString() == 'loginres') {
          final userId = parsed['userid']?.toString() ?? 'none';
          final sessionId = parsed['sessionid']?.toString() ?? 'none';
          final nickname = parsed['nickname']?.toString() ?? '';
          print('  userid=$userId sessionid=$sessionId nick=$nickname');
          if (!completer.isCompleted) completer.complete(userId);
        }
      }
    }
  });

  ws.add(ser(loginBody));
  final userId = await completer.future.timeout(Duration(seconds: 5), onTimeout: () => null);

  if (userId != null && userId != '0') {
    ws.add(ser('type@=joingroup/rid@=$roomId/gid@=-9999/'));
    await Future.delayed(Duration(seconds: 1));
    final testMsg = 'PureLive${Random().nextInt(9999)}';
    final cst = DateTime.now().millisecondsSinceEpoch.toString();
    final chatBody = 'type@=chatmessage/roomid@=$roomId/content@=$testMsg/col@=0/pt@=0/ct@=$cst/sn@=0/ss@=0/uid@=$userId/nn@=PureLive/txt@=$testMsg/level@=1/dms@=5/cst@=$cst/';
    print('  >> 发送: $testMsg');
    ws.add(ser(chatBody));
    await Future.delayed(Duration(seconds: 3));
  } else {
    print('  uid=0 未认证');
  }

  await ws.close();
  return userId;
}

Future<void> main() async {
  final roomId = '93589';
  final uid = '27047486';
  final stk = '11b344af7ef2cca3';
  final devid = '1976bad760eb7b35a33d922900061701';
  final rt = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();

  await tryLogin(roomId,
    'type@=loginreq/roomid@=$roomId/devid@=$devid/rt@=$rt/ver@=21952015/vk@=0/ct@=1/stk@=$stk/',
    'S1: stk only');
  await tryLogin(roomId,
    'type@=loginreq/roomid@=$roomId/devid@=$devid/rt@=$rt/ver@=21952015/vk@=0/ct@=1/uid@=$uid/stk@=$stk/',
    'S2: uid+stk');
  await tryLogin(roomId,
    'type@=loginreq/roomid@=$roomId/uid@=$uid/stk@=$stk/ver@=21952015/devid@=$devid/rt@=$rt/vk@=0/ct@=1/aa1@=1/',
    'S3: uid+stk+aa1');
  await tryLogin(roomId,
    'type@=loginreq/roomid@=$roomId/uid@=$uid/stk@=$stk/devid@=$devid/rt@=$rt/ver@=21952015/vk@=0/',
    'S4: minimal');
  await tryLogin(roomId,
    'type@=loginreq/roomid@=$roomId/uid@=$uid/stk@=$stk/devid@=$devid/rt@=$rt/ver@=21952015/vk@=0/ct@=1/biz@=1/',
    'S5: with biz');

  print('\nDone');
}
