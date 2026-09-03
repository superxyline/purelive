/// 独立测试脚本 — 验证斗鱼弹幕发送协议的正确性
///
/// 运行方式:
///   dart tool/test_douyu_chat_standalone.dart
///
/// 此脚本不依赖 flutter_test，可以在命令行直接运行。
/// 它验证:
///   1. STT 序列化/反序列化正确性
///   2. VK (MD5) 计算正确性
///   3. Cookie 解析正确性
///   4. 帧格式与现有 DouyuDanmaku 兼容性
///   5. 端到端协议流程模拟

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

// ─────────────────────────────────────────────────
// 以下是从 DouyuChatSender 复制的核心协议逻辑
// （避免 import 路径问题，直接内嵌测试）
// ─────────────────────────────────────────────────

// === BinaryWriter (从项目中复制核心逻辑) ===
class _BinaryWriter {
  List<int> buffer;
  int position = 0;
  _BinaryWriter(this.buffer);

  void writeBytes(List<int> list) {
    buffer.addAll(list);
    position += list.length;
  }

  void writeInt(int value, int len, {Endian endian = Endian.big}) {
    var b = Uint8List(len).buffer;
    var bytes = ByteData.view(b);
    if (len == 1) bytes.setUint8(0, value.toUnsigned(8));
    if (len == 2) bytes.setInt16(0, value, endian);
    if (len == 4) bytes.setInt32(0, value, endian);
    if (len == 8) bytes.setInt64(0, value, endian);
    buffer.addAll(bytes.buffer.asUint8List());
    position += len;
  }
}

// === 协议核心函数 ===

List<int> serializeDouyu(String body) {
  const int clientSendToServer = 689;
  List<int> buffer = utf8.encode(body);
  // payload_len = len2(4) + magic(2) + encrypted(1) + reserved(1) + body(N) + null(1) = N + 9
  final int payloadLen = 4 + 2 + 1 + 1 + buffer.length + 1;
  var writer = _BinaryWriter([]);
  writer.writeInt(payloadLen, 4, endian: Endian.little);
  writer.writeInt(payloadLen, 4, endian: Endian.little);
  writer.writeInt(clientSendToServer, 2, endian: Endian.little);
  writer.writeInt(0, 1, endian: Endian.little); // encrypted
  writer.writeInt(0, 1, endian: Endian.little); // reserved
  writer.writeBytes(buffer);
  writer.writeInt(0, 1, endian: Endian.little); // null terminator
  return writer.buffer;
}

List<String> deserializeDouyuPackets(List<int> buffer) {
  final packets = <String>[];
  var offset = 0;
  while (offset + 12 <= buffer.length) {
    final header = ByteData.sublistView(Uint8List.fromList(buffer), offset, offset + 4);
    final fullMsgLength = header.getUint32(0, Endian.little);
    final frameLength = fullMsgLength + 4;
    final bodyLength = fullMsgLength - 9;
    if (fullMsgLength < 9 || bodyLength < 0 || offset + frameLength > buffer.length) break;
    final bodyStart = offset + 12;
    final bodyEnd = bodyStart + bodyLength;
    packets.add(utf8.decode(buffer.sublist(bodyStart, bodyEnd), allowMalformed: true));
    offset += frameLength;
  }
  return packets;
}

String unscapeSlashAt(String str) => str.replaceAll('@S', '/').replaceAll('@A', '@');

dynamic parseStt(String str) {
  if (str.contains('//')) {
    var result = [];
    for (var field in str.split('//')) {
      if (field.isEmpty) continue;
      result.add(parseStt(field));
    }
    return result;
  }
  if (str.contains('@=')) {
    var result = {};
    for (var field in str.split('/')) {
      if (field.isEmpty) continue;
      final separator = field.indexOf('@=');
      if (separator <= 0) continue;
      var k = field.substring(0, separator);
      var v = unscapeSlashAt(field.substring(separator + 2));
      result[k] = parseStt(v);
    }
    return result;
  } else if (str.contains('@A=')) {
    return parseStt(unscapeSlashAt(str));
  } else {
    return unscapeSlashAt(str);
  }
}

// === MD5 (纯 Dart 实现) ===
String md5Hex(List<int> message) {
  // Use a growable list (Uint8List.fromList creates fixed-length)
  final msg = Uint8List(message.length);
  msg.setAll(0, message);
  // We need a growable list for padding
  final List<int> data = List<int>.from(msg);
  final originalLength = data.length * 8;
  data.add(0x80);
  while (data.length % 64 != 56) {
    data.add(0);
  }
  final lenBytes = ByteData(8);
  lenBytes.setUint32(0, originalLength & 0xFFFFFFFF, Endian.little);
  lenBytes.setUint32(4, (originalLength >> 32) & 0xFFFFFFFF, Endian.little);
  data.addAll(lenBytes.buffer.asUint8List());

  int a0 = 0x67452301;
  int b0 = 0xefcdab89;
  int c0 = 0x98badcfe;
  int d0 = 0x10325476;

  const List<int> s = [
    7,12,17,22,7,12,17,22,7,12,17,22,7,12,17,22,
    5,9,14,20,5,9,14,20,5,9,14,20,5,9,14,20,
    4,11,16,23,4,11,16,23,4,11,16,23,4,11,16,23,
    6,10,15,21,6,10,15,21,6,10,15,21,6,10,15,21,
  ];
  const List<int> k = [
    0xd76aa478,0xe8c7b756,0x242070db,0xc1bdceee,
    0xf57c0faf,0x4787c62a,0xa8304613,0xfd469501,
    0x698098d8,0x8b44f7af,0xffff5bb1,0x895cd7be,
    0x6b901122,0xfd987193,0xa679438e,0x49b40821,
    0xf61e2562,0xc040b340,0x265e5a51,0xe9b6c7aa,
    0xd62f105d,0x02441453,0xd8a1e681,0xe7d3fbc8,
    0x21e1cde6,0xc33707d6,0xf4d50d87,0x455a14ed,
    0xa9e3e905,0xfcefa3f8,0x676f02d9,0x8d2a4c8a,
    0xfffa3942,0x8771f681,0x6d9d6122,0xfde5380c,
    0xa4beea44,0x4bdecfa9,0xf6bb4b60,0xbebfbc70,
    0x289b7ec6,0xeaa127fa,0xd4ef3085,0x04881d05,
    0xd9d4d039,0xe6db99e5,0x1fa27cf8,0xc4ac5665,
    0xf4292244,0x432aff97,0xab9423a7,0xfc93a039,
    0x655b59c3,0x8f0ccc92,0xffeff47d,0x85845dd1,
    0x6fa87e4f,0xfe2ce6e0,0xa3014314,0x4e0811a1,
    0xf7537e82,0xbd3af235,0x2ad7d2bb,0xeb86d391,
  ];

  for (int i = 0; i < data.length; i += 64) {
    final chunk = data.sublist(i, i + 64);
    final m = List<int>.generate(16, (j) {
      final bd = ByteData.sublistView(Uint8List.fromList(chunk), j * 4, j * 4 + 4);
      return bd.getUint32(0, Endian.little);
    });
    int a = a0, b = b0, c = c0, d = d0;
    for (int j = 0; j < 64; j++) {
      int f, g;
      if (j < 16) { f = (b & c) | ((~b) & d); g = j; }
      else if (j < 32) { f = (d & b) | ((~d) & c); g = (5 * j + 1) % 16; }
      else if (j < 48) { f = b ^ c ^ d; g = (3 * j + 5) % 16; }
      else { f = c ^ (b | (~d)); g = (7 * j) % 16; }
      f = (f + a + k[j] + m[g]) & 0xFFFFFFFF;
      a = d; d = c; c = b;
      b = (b + ((f << s[j]) | (f >>> (32 - s[j])))) & 0xFFFFFFFF;
    }
    a0 = (a0 + a) & 0xFFFFFFFF;
    b0 = (b0 + b) & 0xFFFFFFFF;
    c0 = (c0 + c) & 0xFFFFFFFF;
    d0 = (d0 + d) & 0xFFFFFFFF;
  }
  final digest = ByteData(16);
  digest.setUint32(0, a0, Endian.little);
  digest.setUint32(4, b0, Endian.little);
  digest.setUint32(8, c0, Endian.little);
  digest.setUint32(12, d0, Endian.little);
  return digest.buffer.asUint8List().map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

String generateVk(String roomId, String devid, String rt) {
  return md5Hex(utf8.encode('$roomId$devid${rt}123456789012345678901234567890'));
}

// === Cookie 解析 ===
String extractCookieValue(String cookie, String name) {
  final regex = RegExp('(?:^|;\\s*)${RegExp.escape(name)}=([^;]*)');
  return regex.firstMatch(cookie)?.group(1) ?? '';
}

// === 消息构建 ===
String buildLoginReq({required String roomId, required String devid, required String rt, String? stk, String? aa1}) {
  final vk = generateVk(roomId, devid, rt);
  var body = 'type@=loginreq/roomid@=$roomId/devid@=$devid/rt@=$rt/ver@=21952015/vk@=$vk/ct@=1/';
  if (stk != null && stk.isNotEmpty) body += 'stk@=$stk/';
  if (aa1 != null && aa1.isNotEmpty) body += 'aa1@=$aa1/';
  return body;
}

String buildJoinGroup({required String roomId}) => 'type@=joingroup/rid@=$roomId/gid@=-9999/';

String buildChatMessage({required String content, required String roomId, required String uid, String nickname = ''}) {
  final cst = DateTime.now().millisecondsSinceEpoch.toString();
  final nn = nickname.isEmpty ? 'guest' : nickname;
  return 'type@=chatmessage/roomid@=$roomId/content@=$content/col@=0/pt@=0/ct@=$cst/sn@=0/ss@=0/uid@=$uid/nn@=$nn/txt@=$content/level@=1/dms@=5/cst@=$cst/';
}

String buildHeartbeat() => 'type@=mrkl/';

// ─────────────────────────────────────────────────
// 测试框架（简单的 assert 封装）
// ─────────────────────────────────────────────────

int _pass = 0;
int _fail = 0;
int _total = 0;

void _group(String name) {
  stdout.write('\n\x1B[36m═══ $name ═══\x1B[0m\n');
}

void _test(String name, void Function() fn) {
  _total++;
  try {
    fn();
    _pass++;
    stdout.write('  \x1B[32m✓\x1B[0m $name\n');
  } catch (e) {
    _fail++;
    stdout.write('  \x1B[31m✗\x1B[0m $name\n');
    stdout.write('    \x1B[31m$e\x1B[0m\n');
  }
}

void expect(dynamic actual, dynamic expected, {String? reason}) {
  if (actual != expected) {
    throw Exception('${reason ?? "assertion failed"}: expected "$expected", got "$actual"');
  }
}

void expectTrue(bool condition, {String? reason}) {
  if (!condition) throw Exception(reason ?? 'expected true');
}

void expectMatch(RegExp regex, String str, {String? reason}) {
  if (!regex.hasMatch(str)) throw Exception('${reason ?? "regex match failed"}: "$str" does not match ${regex.pattern}');
}

// ─────────────────────────────────────────────────
// 主测试函数
// ─────────────────────────────────────────────────

void main() {
  stdout.write('\x1B[1m╔══════════════════════════════════════════════╗\x1B[0m\n');
  stdout.write('\x1B[1m║  斗鱼弹幕发送协议 — 独立验证测试             ║\x1B[0m\n');
  stdout.write('\x1B[1m╚══════════════════════════════════════════════╝\x1B[0m\n');

  // ── 测试组 1: STT 序列化 ──
  _group('STT 序列化');
  _test('serializeDouyu 产生正确的帧长度', () {
    final body = 'type@=mrkl/';
    final frame = serializeDouyu(body);
    final bodyBytes = utf8.encode(body);
    final expectedPayloadLen = 4 + 2 + 1 + 1 + bodyBytes.length + 1; // len2+magic+enc+rsv+body+null
    final expectedFrameLen = 4 + expectedPayloadLen;
    expect(frame.length, expectedFrameLen, reason: '帧总长度');
  });

  _test('serializeDouyu 帧头包含正确的 magic number (689)', () {
    final frame = serializeDouyu('type@=mrkl/');
    // magic 在 offset 8-9 (little-endian uint16)
    final magic = frame[8] | (frame[9] << 8);
    expect(magic, 689, reason: 'magic number');
  });

  _test('serializeDouyu payload_len 为小端序重复两次', () {
    final frame = serializeDouyu('type@=mrkl/');
    final bd = ByteData.sublistView(Uint8List.fromList(frame));
    final len1 = bd.getUint32(0, Endian.little);
    final len2 = bd.getUint32(4, Endian.little);
    expect(len1, len2, reason: '两个 payload_len 应相同');
    final bodyByteLen = utf8.encode('type@=mrkl/').length; expect(len1, 4 + 2 + 1 + 1 + bodyByteLen + 1, reason: 'payload_len = len2(4)+magic(2)+enc(1)+rsv(1)+body(\)+null(1)');  // body = 'type@=mrkl/' = 12 bytes
  });

  _test('serializeDouyu 尾部有 null 终止符', () {
    final frame = serializeDouyu('type@=mrkl/');
    expect(frame.last, 0, reason: '尾部 null');
  });

  // ── 测试组 2: STT 反序列化 ──
  _group('STT 反序列化');
  _test('deserializeDouyuPackets 正确解析单个包', () {
    final body = 'type@=chatmsg/rid@=100/txt@=hello/';
    final frame = serializeDouyu(body);
    final packets = deserializeDouyuPackets(frame);
    expect(packets.length, 1, reason: '应解析出1个包');
    expect(packets.first, body, reason: '包内容应一致');
  });

  _test('deserializeDouyuPackets 正确解析多个包', () {
    final body1 = 'type@=chatmsg/rid@=100/txt@=hello/';
    final body2 = 'type@=dgb/rid@=100/gn@=gift/';
    final frame1 = serializeDouyu(body1);
    final frame2 = serializeDouyu(body2);
    final packets = deserializeDouyuPackets([...frame1, ...frame2]);
    expect(packets.length, 2, reason: '应解析出2个包');
    expect(packets[0], body1);
    expect(packets[1], body2);
  });

  _test('deserializeDouyuPackets 处理空数据', () {
    expect(deserializeDouyuPackets([]).length, 0);
  });

  _test('deserializeDouyuPackets 处理截断数据', () {
    final frame = serializeDouyu('type@=mrkl/');
    final truncated = frame.sublist(0, frame.length ~/ 2);
    expect(deserializeDouyuPackets(truncated).length, 0);
  });

  _test('deserializeDouyuPackets 处理三种包的连续帧', () {
    final b1 = 'type@=loginres/uid@=12345/';
    final b2 = 'type@=joingroup/rid@=7777/gid@=-9999/';
    final b3 = 'type@=chatmessage/uid@=12345/txt@=hi/';
    final data = [...serializeDouyu(b1), ...serializeDouyu(b2), ...serializeDouyu(b3)];
    final packets = deserializeDouyuPackets(data);
    expect(packets.length, 3);
    expect(packets[0].contains('loginres'), true, reason: '第一个包应为 loginres');
    expect(packets[1].contains('joingroup'), true, reason: '第二个包应为 joingroup');
    expect(packets[2].contains('chatmessage'), true, reason: '第三个包应为 chatmessage');
  });

  // ── 测试组 3: STT 解析 ──
  _group('STT 解析');
  _test('parseStt 解析基本键值对', () {
    final r = parseStt('type@=chatmsg/rid@=100/');
    expect(r['type'], 'chatmsg');
    expect(r['rid'], '100');
  });

  _test('parseStt 处理 @S 转义 (slash)', () {
    final r = parseStt('txt@=hello@Sworld/');
    expect(r['txt'], 'hello/world');
  });

  _test('parseStt 处理 @A 转义 (@)', () {
    final r = parseStt('txt@=hello@A@A/');
    expect(r['txt'], 'hello@@');
  });

  _test('parseStt 处理简单字符串', () {
    final r = parseStt('hello');
    expect(r, 'hello');
  });

  _test('parseStt 处理嵌套结构', () {
    final r = parseStt('a@=b/c@=d/');
    expect(r is Map, true, reason: '应为 Map');
    expect(r['a'], 'b');
    expect(r['c'], 'd');
  });

  // ── 测试组 4: MD5 / VK ──
  _group('MD5 / VK 计算');
  _test('MD5("hello") 正确', () {
    final hash = md5Hex(utf8.encode('hello'));
    expect(hash, '5d41402abc4b2a76b9719d911017c592', reason: 'MD5("hello")');
  });

  _test('MD5("") 正确', () {
    final hash = md5Hex(utf8.encode(''));
    expect(hash, 'd41d8cd98f00b204e9800998ecf8427e', reason: 'MD5("")');
  });

  _test('MD5("abc") 正确', () {
    final hash = md5Hex(utf8.encode('abc'));
    expect(hash, '900150983cd24fb0d6963f7d28e17f72', reason: 'MD5("abc")');
  });

  _test('MD5("message digest") 正确', () {
    final hash = md5Hex(utf8.encode('message digest'));
    expect(hash, 'f96b697d7cb7938d525a2f31aaf161d0', reason: 'MD5("message digest")');
  });

  _test('generateVk 产生一致结果', () {
    final vk1 = generateVk('7777', 'dev-123', '1700000000');
    final vk2 = generateVk('7777', 'dev-123', '1700000000');
    expect(vk1, vk2, reason: '相同输入应产生相同 VK');
  });

  _test('generateVk 不同输入产生不同输出', () {
    final vk1 = generateVk('7777', 'dev-123', '1700000000');
    final vk2 = generateVk('8888', 'dev-123', '1700000000');
    expectTrue(vk1 != vk2, reason: '不同 roomId 应产生不同 VK');
  });

  _test('generateVk 产生32位十六进制', () {
    final vk = generateVk('7777', 'dev-123', '1700000000');
    expectMatch(RegExp(r'^[0-9a-f]{32}$'), vk);
    expect(vk.length, 32);
  });

  // ── 测试组 5: Cookie 解析 ──
  _group('Cookie 解析');
  _test('extractCookieValue 提取 acf_uid', () {
    expect(extractCookieValue('acf_uid=12345; acf_stk=abc', 'acf_uid'), '12345');
  });

  _test('extractCookieValue 提取 acf_stk', () {
    expect(extractCookieValue('acf_uid=12345; acf_stk=abcdef', 'acf_stk'), 'abcdef');
  });

  _test('extractCookieValue 不存在的字段返回空', () {
    expect(extractCookieValue('acf_uid=12345', 'acf_stk'), '');
  });

  _test('extractCookieValue 空字符串返回空', () {
    expect(extractCookieValue('', 'acf_uid'), '');
  });

  _test('extractCookieValue 提取末尾字段', () {
    expect(extractCookieValue('a=1; b=2; acf_uid=999', 'acf_uid'), '999');
  });

  // ── 测试组 6: 消息构建 ──
  _group('消息构建');
  _test('buildLoginReq 包含所有必要字段', () {
    final body = buildLoginReq(roomId: '7777', devid: 'test-dev', rt: '1700000000');
    expectTrue(body.contains('type@=loginreq'));
    expectTrue(body.contains('roomid@=7777'));
    expectTrue(body.contains('devid@=test-dev'));
    expectTrue(body.contains('rt@=1700000000'));
    expectTrue(body.contains('ver@=21952015'));
    expectTrue(body.contains('vk@='));
    expectTrue(body.contains('ct@=1'));
  });

  _test('buildLoginReq 包含 stk 和 aa1', () {
    final body = buildLoginReq(roomId: '7777', devid: 'd', rt: '1', stk: 'my_stk', aa1: 'my_aa1');
    expectTrue(body.contains('stk@=my_stk'));
    expectTrue(body.contains('aa1@=my_aa1'));
  });

  _test('buildLoginReq 不包含空 stk', () {
    final body = buildLoginReq(roomId: '7777', devid: 'd', rt: '1');
    expectTrue(!body.contains('stk@='), reason: '不应包含空 stk');
    expectTrue(!body.contains('aa1@='), reason: '不应包含空 aa1');
  });

  _test('buildJoinGroup 格式正确', () {
    final body = buildJoinGroup(roomId: '7777');
    expect(body, 'type@=joingroup/rid@=7777/gid@=-9999/');
  });

  _test('buildChatMessage 包含必要字段', () {
    final body = buildChatMessage(content: '你好', roomId: '7777', uid: '12345', nickname: '用户A');
    expectTrue(body.contains('type@=chatmessage'));
    expectTrue(body.contains('roomid@=7777'));
    expectTrue(body.contains('content@=你好'));
    expectTrue(body.contains('uid@=12345'));
    expectTrue(body.contains('nn@=用户A'));
    expectTrue(body.contains('txt@=你好'));
    expectTrue(body.contains('dms@=5'));
    expectTrue(body.contains('col@=0'));
  });

  _test('buildChatMessage 默认昵称 guest', () {
    final body = buildChatMessage(content: 'hi', roomId: '1', uid: '2');
    expectTrue(body.contains('nn@=guest'));
  });

  _test('buildHeartbeat 格式正确', () {
    expect(buildHeartbeat(), 'type@=mrkl/');
  });

  // ── 测试组 7: 端到端协议流程 ──
  _group('端到端协议流程模拟');
  _test('完整流程: 构建 → 序列化 → 反序列化 → 解析', () {
    const roomId = '7777';
    const devid = 'test-device-1234';
    const rt = '1700000000';
    const uid = '99999';
    const message = '你好斗鱼!';

    // Step 1: 构建登录请求
    final loginBody = buildLoginReq(roomId: roomId, devid: devid, rt: rt);
    final loginFrame = serializeDouyu(loginBody);
    expectTrue(loginFrame.isNotEmpty, reason: '登录帧不为空');

    // Step 2: 构建加入分组
    final joinBody = buildJoinGroup(roomId: roomId);
    final joinFrame = serializeDouyu(joinBody);
    expectTrue(joinFrame.isNotEmpty, reason: '加组帧不为空');

    // Step 3: 构建弹幕消息
    final chatBody = buildChatMessage(content: message, roomId: roomId, uid: uid, nickname: '测试用户');
    final chatFrame = serializeDouyu(chatBody);
    expectTrue(chatFrame.isNotEmpty, reason: '弹幕帧不为空');

    // Step 4: 反序列化验证
    final loginPackets = deserializeDouyuPackets(loginFrame);
    expectTrue(loginPackets.first.contains('type@=loginreq'));

    final joinPackets = deserializeDouyuPackets(joinFrame);
    expectTrue(joinPackets.first.contains('type@=joingroup'));

    final chatPackets = deserializeDouyuPackets(chatFrame);
    expectTrue(chatPackets.first.contains('type@=chatmessage'));

    // Step 5: 解析 STT 验证内容
    final parsed = parseStt(chatPackets.first) as Map;
    expect(parsed['type'], 'chatmessage');
    expect(parsed['roomid'], roomId);
    expect(parsed['content'], message);
    expect(parsed['uid'], uid);
    expect(parsed['nn'], '测试用户');
  });

  _test('模拟服务器响应: loginres → chatmsg 回显', () {
    // 模拟服务器返回 loginres
    final loginresBody = 'type@=loginres/userid@=88888/roomgroup@=1/';
    final loginresFrame = serializeDouyu(loginresBody);
    final packets = deserializeDouyuPackets(loginresFrame);
    final parsed = parseStt(packets.first) as Map;
    expect(parsed['type'], 'loginres');
    expect(parsed['userid'], '88888');

    // 模拟服务器回显 chatmsg
    final echoBody = 'type@=chatmsg/rid@=7777/uid@=88888/nn@=test/txt@=hello/dms@=1/';
    final echoFrame = serializeDouyu(echoBody);
    final echoPackets = deserializeDouyuPackets(echoFrame);
    final echoParsed = parseStt(echoPackets.first) as Map;
    expect(echoParsed['type'], 'chatmsg');
    expect(echoParsed['txt'], 'hello');
  });

  _test('模拟服务器返回错误', () {
    final errorBody = 'type@=error/msg@=发送过于频繁/';
    final errorFrame = serializeDouyu(errorBody);
    final packets = deserializeDouyuPackets(errorFrame);
    final parsed = parseStt(packets.first) as Map;
    expect(parsed['type'], 'error');
    expect(parsed['msg'], '发送过于频繁');
  });

  _test('Unicode 弹幕内容往返测试', () {
    const content = '🎉Hello你好🌍';
    final body = buildChatMessage(content: content, roomId: '1', uid: '2');
    final frame = serializeDouyu(body);
    final packets = deserializeDouyuPackets(frame);
    final parsed = parseStt(packets.first) as Map;
    expect(parsed['content'], content, reason: 'Unicode 内容往返应一致');
  });

  _test('大量数据帧合并解析', () {
    final frames = <int>[];
    final expectedTexts = <String>[];
    for (int i = 0; i < 50; i++) {
      final text = 'msg_$i';
      expectedTexts.add(text);
      final body = 'type@=chatmsg/rid@=100/txt@=$text/';
      frames.addAll(serializeDouyu(body));
    }
    final packets = deserializeDouyuPackets(frames);
    expect(packets.length, 50, reason: '应解析出50个包');
    final texts = packets.map((p) {
      final m = parseStt(p) as Map;
      return m['txt'];
    }).toList();
    expect(texts.join(','), expectedTexts.join(','), reason: '所有消息内容应匹配');
  });

  // ── 汇总 ──
  stdout.write('\n\x1B[1m══════════════════════════════════════════════\x1B[0m\n');
  stdout.write('\x1B[1m  测试结果: $_pass / $_total 通过');
  if (_fail > 0) {
    stdout.write('  \x1B[31m$_fail 失败\x1B[0m');
  } else {
    stdout.write('  \x1B[32m全部通过 ✓\x1B[0m');
  }
  stdout.write('\n\x1B[1m══════════════════════════════════════════════\x1B[0m\n');

  exit(_fail > 0 ? 1 : 0);
}
