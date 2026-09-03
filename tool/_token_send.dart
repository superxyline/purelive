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
  final cookie = 'acf_uid=$uid;acf_stk=$stk;dy_did=1976bad760eb7b35a33d922900061701';

  // Step 1: 从房间页获取 token
  print('=== Step 1: 获取房间 token ===');
  final client = HttpClient()..badCertificateCallback = ((_, __, ___) => true);
  String? token;
  try {
    final req = await client.getUrl(Uri.parse("https://www.douyu.com/$roomId"));
    req.headers.set("Cookie", cookie);
    req.headers.set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36");
    final resp = await req.close().timeout(Duration(seconds: 10));
    final html = await resp.transform(utf8.decoder).join();

    // 搜索 $ROOM arguments 或 token
    final tokenMatch = RegExp(r'"token"\s*:\s*"([^"]+)"').firstMatch(html);
    if (tokenMatch != null) {
      token = tokenMatch.group(1);
      print('token found: ${token!.substring(0, token!.length.clamp(0, 40))}...');
    }

    // 也尝试搜索 rst / room arguments
    final rstMatch = RegExp(r'var\s+rst\s*=\s*"([^"]+)"').firstMatch(html);
    if (rstMatch != null) {
      print('rst found: ${rstMatch.group(1)}');
    }

    // 搜索 room_info 中的关键字段
    final roomInfoMatch = RegExp(r'\$ROOM\s*=\s*(\{[^;]+\})').firstMatch(html);
    if (roomInfoMatch != null) {
      print('ROOM object found (${roomInfoMatch.group(1)!.length} chars)');
    }

    // 搜索 roomid / channel / rid
    for (final pattern in [r'"room_id"\s*:\s*(\d+)', r'"rid"\s*:\s*(\d+)', r'"channel"\s*:\s*(\d+)']) {
      final m = RegExp(pattern).firstMatch(html);
      if (m != null) print('Found ${pattern}: ${m.group(1)}');
    }
  } catch (e) {
    print('Page fetch error: $e');
  }
  client.close();

  // Step 2: 连接 WebSocket 带 token
  print('\n=== Step 2: WebSocket 连接 ===');
  final ws = await WebSocket.connect('wss://danmuproxy.douyu.com:8506');

  ws.listen((data) {
    if (data is! List<int>) return;
    for (final p in de(Uint8List.fromList(data))) {
      final parsed = ps(p);
      if (parsed is Map) {
        final type = parsed['type']?.toString() ?? '';
        if (type == 'loginres') {
          print('[loginres] userid=${parsed["userid"]} sessionid=${parsed["sessionid"]} nickname="${parsed["nickname"]}"');
        } else if (type == 'error') {
          print('[ERROR] ${parsed}');
        } else if (type == 'chatmsg') {
          print('  [${parsed["nn"]}]: ${parsed["txt"]}');
        } else if (type == 'gbroadcast' || type == 'spbc') {
          // skip broadcasts
        } else if (type != 'mrkl' && type != 'pingreq' && type != 'uenter' && type != 'configscreen' && type != 'oni' && type != 'oun') {
          print('[$type] ${parsed}');
        }
      }
    }
  });

  final devid = '1976bad760eb7b35a33d922900061701';
  final rt = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();

  // 尝试带 token 的 loginreq
  var loginBody = 'type@=loginreq/roomid@=$roomId/devid@=$devid/rt@=$rt/ver@=21952015/vk@=0/ct@=1/uid@=$uid/stk@=$stk/';
  if (token != null) {
    loginBody += 'stk@=$token/';
  }
  print('>>> loginreq (with token)');
  ws.add(ser(loginBody));
  await Future.delayed(Duration(seconds: 3));

  ws.add(ser('type@=joingroup/rid@=$roomId/gid@=-9999/'));
  await Future.delayed(Duration(seconds: 1));

  // 发送弹幕
  final cst = DateTime.now().millisecondsSinceEpoch.toString();
  final msg = '主播你好';
  final chatBody = 'type@=chatmessage/roomid@=$roomId/content@=$msg/col@=0/pt@=0/uid@=$uid/stk@=$stk/nn@=PureLive/txt@=$msg/level@=1/dms@=5/cst@=$cst/rid@=$roomId/';
  print('>>> 发送: $msg');
  ws.add(ser(chatBody));
  await Future.delayed(Duration(seconds: 5));

  await ws.close();
  print('done');
}