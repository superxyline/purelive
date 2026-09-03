/// 斗鱼 WebSocket 实时探针
///
/// 无外部依赖，使用 dart:io WebSocket 直连斗鱼弹幕服务器
/// 验证: 连接 → 登录 → 收消息 → 心跳 整个流程
///
/// 运行: dartvm.exe tool/douyu_live_probe.dart <room_id>

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

// ── 协议函数 ──

List<int> serializeDouyu(String body) {
  const int magic = 689;
  final buffer = utf8.encode(body);
  final payloadLen = 4 + 2 + 1 + 1 + buffer.length + 1;
  final result = BytesBuilder();
  result.add([payloadLen & 0xFF, (payloadLen >> 8) & 0xFF, (payloadLen >> 16) & 0xFF, (payloadLen >> 24) & 0xFF]);
  result.add([payloadLen & 0xFF, (payloadLen >> 8) & 0xFF, (payloadLen >> 16) & 0xFF, (payloadLen >> 24) & 0xFF]);
  result.add([magic & 0xFF, (magic >> 8) & 0xFF]);
  result.add([0, 0]);
  result.add(buffer);
  result.add([0]);
  return result.toBytes();
}

List<String> deserializePackets(Uint8List buffer) {
  final packets = <String>[];
  var offset = 0;
  while (offset + 12 <= buffer.length) {
    final fullMsgLength = ByteData.sublistView(buffer, offset, offset + 4).getUint32(0, Endian.little);
    final frameLength = fullMsgLength + 4;
    final bodyLength = fullMsgLength - 9;
    if (fullMsgLength < 9 || bodyLength < 0 || offset + frameLength > buffer.length) break;
    packets.add(utf8.decode(buffer.sublist(offset + 12, offset + 12 + bodyLength), allowMalformed: true));
    offset += frameLength;
  }
  return packets;
}

dynamic parseStt(String str) {
  if (str.contains('//')) {
    return str.split('//').where((f) => f.isNotEmpty).map(parseStt).toList();
  }
  if (str.contains('@=')) {
    final result = {};
    for (var field in str.split('/')) {
      if (field.isEmpty) continue;
      final sep = field.indexOf('@=');
      if (sep <= 0) continue;
      final k = field.substring(0, sep);
      final v = field.substring(sep + 2).replaceAll('@S', '/').replaceAll('@A', '@');
      result[k] = parseStt(v);
    }
    return result;
  }
  return str.replaceAll('@S', '/').replaceAll('@A', '@');
}

String generateDevid() {
  final r = Random.secure();
  final hex = List<int>.generate(16, (_) => r.nextInt(256)).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0,8)}-${hex.substring(8,12)}-${hex.substring(12,16)}-${hex.substring(16,20)}-${hex.substring(20)}';
}

String md5Hex(List<int> msg) {
  // 简化MD5 — 复用已验证的实现
  final data = List<int>.from(msg);
  final origLen = data.length * 8;
  data.add(0x80);
  while (data.length % 64 != 56) data.add(0);
  final lb = ByteData(8);
  lb.setUint32(0, origLen & 0xFFFFFFFF, Endian.little);
  lb.setUint32(4, (origLen >> 32) & 0xFFFFFFFF, Endian.little);
  data.addAll(lb.buffer.asUint8List());

  int a0=0x67452301, b0=0xefcdab89, c0=0x98badcfe, d0=0x10325476;
  const s=[7,12,17,22,7,12,17,22,7,12,17,22,7,12,17,22,5,9,14,20,5,9,14,20,5,9,14,20,5,9,14,20,4,11,16,23,4,11,16,23,4,11,16,23,4,11,16,23,6,10,15,21,6,10,15,21,6,10,15,21,6,10,15,21];
  const k=[0xd76aa478,0xe8c7b756,0x242070db,0xc1bdceee,0xf57c0faf,0x4787c62a,0xa8304613,0xfd469501,0x698098d8,0x8b44f7af,0xffff5bb1,0x895cd7be,0x6b901122,0xfd987193,0xa679438e,0x49b40821,0xf61e2562,0xc040b340,0x265e5a51,0xe9b6c7aa,0xd62f105d,0x02441453,0xd8a1e681,0xe7d3fbc8,0x21e1cde6,0xc33707d6,0xf4d50d87,0x455a14ed,0xa9e3e905,0xfcefa3f8,0x676f02d9,0x8d2a4c8a,0xfffa3942,0x8771f681,0x6d9d6122,0xfde5380c,0xa4beea44,0x4bdecfa9,0xf6bb4b60,0xbebfbc70,0x289b7ec6,0xeaa127fa,0xd4ef3085,0x04881d05,0xd9d4d039,0xe6db99e5,0x1fa27cf8,0xc4ac5665,0xf4292244,0x432aff97,0xab9423a7,0xfc93a039,0x655b59c3,0x8f0ccc92,0xffeff47d,0x85845dd1,0x6fa87e4f,0xfe2ce6e0,0xa3014314,0x4e0811a1,0xf7537e82,0xbd3af235,0x2ad7d2bb,0xeb86d391];

  for (int i = 0; i < data.length; i += 64) {
    final chunk = Uint8List.fromList(data.sublist(i, i + 64));
    final m = List<int>.generate(16, (j) => ByteData.sublistView(chunk, j*4, j*4+4).getUint32(0, Endian.little));
    int a=a0, b=b0, c=c0, d=d0;
    for (int j = 0; j < 64; j++) {
      int f, g;
      if (j<16) { f=(b&c)|((~b)&d); g=j; }
      else if (j<32) { f=(d&b)|((~d)&c); g=(5*j+1)%16; }
      else if (j<48) { f=b^c^d; g=(3*j+5)%16; }
      else { f=c^(b|(~d)); g=(7*j)%16; }
      f = (f + a + k[j] + m[g]) & 0xFFFFFFFF;
      a=d; d=c; c=b; b = (b + ((f<<s[j])|(f>>>(32-s[j])))) & 0xFFFFFFFF;
    }
    a0=(a0+a)&0xFFFFFFFF; b0=(b0+b)&0xFFFFFFFF; c0=(c0+c)&0xFFFFFFFF; d0=(d0+d)&0xFFFFFFFF;
  }
  final digest = ByteData(16);
  digest.setUint32(0, a0, Endian.little);
  digest.setUint32(4, b0, Endian.little);
  digest.setUint32(8, c0, Endian.little);
  digest.setUint32(12, d0, Endian.little);
  return digest.buffer.asUint8List().map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

// ── 主流程 ──

void log(String msg) {
  final now = DateTime.now();
  final ts = '${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}:${now.second.toString().padLeft(2,'0')}.${(now.millisecond/100).floor()}';
  print('[$ts] $msg');
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dartvm.exe tool/douyu_live_probe.dart <room_id> [cookie]');
    print('Example: dartvm.exe tool/douyu_live_probe.dart 7777');
    print('');
    print('This connects to Douyu danmaku server, joins a room,');
    print('and listens for messages for 15 seconds to verify the protocol works.');
    exit(1);
  }

  final roomId = args[0];
  final cookie = args.length > 1 ? args[1] : '';

  log('╔════════════════════════════════════════╗');
  log('║  斗鱼 WebSocket 实时探针               ║');
  log('╚════════════════════════════════════════╝');
  log('');
  log('房间号: $roomId');
  log('Cookie: ${cookie.isEmpty ? "(无 - 匿名模式)" : "已提供 (${cookie.length} bytes)"}');

  // 解析 cookie 中的认证信息
  String? stk, aa1, uid;
  if (cookie.isNotEmpty) {
    for (final part in cookie.split(';')) {
      final trimmed = part.trim();
      if (trimmed.startsWith('acf_uid=')) uid = trimmed.substring(8);
      if (trimmed.startsWith('acf_stk=')) stk = trimmed.substring(8);
      if (trimmed.startsWith('acf_aa1=')) aa1 = trimmed.substring(8);
    }
    log('Cookie 认证: uid=${uid ?? "无"} stk=${stk != null ? "有" : "无"} aa1=${aa1 != null ? "有" : "无"}');
  }

  // 连接
  final url = 'wss://danmuproxy.douyu.com:8506';
  log('');
  log('>>> 连接 $url ...');

  WebSocket ws;
  try {
    ws = await WebSocket.connect(url, headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    }).timeout(Duration(seconds: 10));
  } catch (e) {
    log('✗ 连接失败: $e');
    exit(1);
  }
  log('✓ WebSocket 已连接');

  // 收集消息
  final receivedPackets = <Map<String, dynamic>>[];
  int chatMsgCount = 0;
  int giftCount = 0;
  String? serverUid;

  ws.listen(
    (data) {
      if (data is List<int>) {
        final packets = deserializePackets(Uint8List.fromList(data));
        for (final packet in packets) {
          final parsed = parseStt(packet);
          if (parsed is Map) {
            final type = parsed['type']?.toString() ?? '?';
            receivedPackets.add(parsed.cast<String, dynamic>());

            if (type == 'loginres') {
              serverUid = parsed['userid']?.toString() ?? parsed['uid']?.toString();
              log('  ← loginres: uid=$serverUid');
            } else if (type == 'chatmsg') {
              chatMsgCount++;
              final nn = parsed['nn']?.toString() ?? '?';
              final txt = parsed['txt']?.toString() ?? '';
              if (chatMsgCount <= 5) {
                log('  ← chatmsg [$nn]: $txt');
              } else if (chatMsgCount == 6) {
                log('  ← ... (继续接收更多弹幕)');
              }
            } else if (type == 'dgb') {
              giftCount++;
              final nn = parsed['nn']?.toString() ?? '?';
              final gn = parsed['gn']?.toString() ?? '?';
              log('  ← gift [$nn]: $gn');
            } else if (type == 'error') {
              log('  ← ERROR: ${parsed['msg']}');
            } else if (type != 'mrkl' && type != 'pingresp') {
              log('  ← $type');
            }
          }
        }
      }
    },
    onError: (e) => log('✗ WebSocket 错误: $e'),
    onDone: () => log('WebSocket 已关闭'),
  );

  // Step 1: 发送登录请求
  final devid = generateDevid();
  final rt = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
  final vkRaw = '$roomId$devid${rt}123456789012345678901234567890';
  final vk = md5Hex(utf8.encode(vkRaw));

  var loginBody = 'type@=loginreq/roomid@=$roomId/devid@=$devid/rt@=$rt/ver@=21952015/vk@=$vk/ct@=1/';
  if (stk != null && stk.isNotEmpty) loginBody += 'stk@=$stk/';
  if (aa1 != null && aa1.isNotEmpty) loginBody += 'aa1@=$aa1/';

  log('');
  log('>>> 发送 loginreq ...');
  ws.add(serializeDouyu(loginBody));

  // 等待登录响应
  await Future.delayed(Duration(seconds: 2));

  if (serverUid == null) {
    log('⚠ 未收到 loginres，服务器可能需要认证');
  }

  // Step 2: 加入分组
  final joinBody = 'type@=joingroup/rid@=$roomId/gid@=-9999/';
  log('');
  log('>>> 发送 joingroup ...');
  ws.add(serializeDouyu(joinBody));

  // Step 3: 心跳
  log('');
  log('>>> 发送心跳 mrkl ...');
  ws.add(serializeDouyu('type@=mrkl/'));

  // Step 4: 如果有 cookie，尝试发送弹幕
  if (cookie.isNotEmpty && serverUid != null) {
    await Future.delayed(Duration(seconds: 1));
    final testMsg = 'PureLive测试弹幕${Random().nextInt(9999)}';
    final cst = DateTime.now().millisecondsSinceEpoch.toString();
    final chatBody = 'type@=chatmessage/roomid@=$roomId/content@=$testMsg/col@=0/pt@=0/ct@=$cst/sn@=0/ss@=0/uid@=$serverUid/nn@=PureLive/txt@=$testMsg/level@=1/dms@=5/cst@=$cst/';
    log('');
    log('>>> 发送弹幕: "$testMsg" ...');
    ws.add(serializeDouyu(chatBody));
    await Future.delayed(Duration(seconds: 2));
  } else if (cookie.isEmpty) {
    log('');
    log('(未提供 Cookie，跳过弹幕发送测试)');
    log('提示: 使用 dartvm.exe tool/douyu_live_probe.dart $roomId "acf_uid=xxx;acf_stk=yyy" 来测试发送');
  }

  // Step 5: 继续监听 10 秒
  log('');
  log('正在监听弹幕流 (10秒) ...');

  // 定期发送心跳
  final heartbeatTimer = Timer.periodic(Duration(seconds: 45), (_) {
    try {
      ws.add(serializeDouyu('type@=mrkl/'));
    } catch (_) {}
  });

  await Future.delayed(Duration(seconds: 10));
  heartbeatTimer.cancel();

  // 结果汇总
  log('');
  log('════════════════════════════════════════');
  log('探针结果汇总:');
  log('  房间号:     $roomId');
  log('  服务器UID:  ${serverUid ?? "(未获取)"}');
  log('  收到包数:   ${receivedPackets.length}');
  log('  弹幕数:     $chatMsgCount');
  log('  礼物数:     $giftCount');
  if (chatMsgCount > 0) {
    log('  ✓ 弹幕接收正常');
  } else {
    log('  ⚠ 未收到弹幕 (房间可能未开播或需要登录)');
  }
  log('════════════════════════════════════════');

  await ws.close();
}
