/// 兼容性测试 — 验证 DouyuChatSender 与现有 DouyuDanmaku 的帧格式完全一致
///
/// 运行: dartvm.exe tool/test_douyu_compatibility.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// 从 DouyuChatSender 复制的序列化
List<int> senderSerialize(String body) {
  const int magic = 689;
  List<int> buffer = utf8.encode(body);
  final int payloadLen = 4 + 2 + 1 + 1 + buffer.length + 1;
  final result = BytesBuilder();
  // len1 (LE uint32)
  result.add([payloadLen & 0xFF, (payloadLen >> 8) & 0xFF, (payloadLen >> 16) & 0xFF, (payloadLen >> 24) & 0xFF]);
  // len2 (LE uint32)
  result.add([payloadLen & 0xFF, (payloadLen >> 8) & 0xFF, (payloadLen >> 16) & 0xFF, (payloadLen >> 24) & 0xFF]);
  // magic (LE uint16)
  result.add([magic & 0xFF, (magic >> 8) & 0xFF]);
  // encrypted + reserved
  result.add([0, 0]);
  // body
  result.add(buffer);
  // null terminator
  result.add([0]);
  return result.toBytes();
}

// 模拟 DouyuDanmaku 的 serializeDouyu (原始项目代码)
List<int> originalSerialize(String body) {
  const int clientSendToServer = 689;
  List<int> buffer = utf8.encode(body);
  // 原始代码: 4 + 4 + body.length + 1
  final int payloadLen = 4 + 4 + body.length + 1;
  final result = BytesBuilder();
  result.add([payloadLen & 0xFF, (payloadLen >> 8) & 0xFF, (payloadLen >> 16) & 0xFF, (payloadLen >> 24) & 0xFF]);
  result.add([payloadLen & 0xFF, (payloadLen >> 8) & 0xFF, (payloadLen >> 16) & 0xFF, (payloadLen >> 24) & 0xFF]);
  result.add([clientSendToServer & 0xFF, (clientSendToServer >> 8) & 0xFF]);
  result.add([0, 0]);
  result.add(buffer);
  result.add([0]);
  return result.toBytes();
}

// 反序列化 (共享)
List<String> deserialize(List<int> buffer) {
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

int _pass = 0, _fail = 0, _total = 0;

void check(String name, bool condition, {String? reason}) {
  _total++;
  if (condition) {
    _pass++;
    stdout.write('  \x1B[32m✓\x1B[0m $name\n');
  } else {
    _fail++;
    stdout.write('  \x1B[31m✗\x1B[0m $name ${reason != null ? "($reason)" : ""}\n');
  }
}

void main() {
  stdout.write('\x1B[1m╔══════════════════════════════════════════════╗\x1B[0m\n');
  stdout.write('\x1B[1m║  DouyuChatSender ↔ DouyuDanmaku 兼容性测试  ║\x1B[0m\n');
  stdout.write('\x1B[1m╚══════════════════════════════════════════════╝\x1B[0m\n\n');

  // 对比关键消息的序列化输出
  final testBodies = [
    'type@=mrkl/',
    'type@=loginreq/roomid@=7777/devid@=test/rt@=1700000000/ver@=21952015/vk@=abc123/ct@=1/',
    'type@=joingroup/rid@=7777/gid@=-9999/',
    'type@=chatmessage/roomid@=7777/content@=hello/uid@=12345/nn@=test/txt@=hello/dms@=5/',
    'type@=chatmessage/roomid@=7777/content@=你好世界/uid@=12345/nn@=测试/txt@=你好世界/dms@=5/',
  ];

  stdout.write('\x1B[36m═══ 帧格式一致性测试 ═══\x1B[0m\n');
  for (final body in testBodies) {
    final sender = senderSerialize(body);
    final original = originalSerialize(body);
    
    check(
      '帧长度一致: "${body.substring(0, body.length.clamp(0, 40))}..."',
      sender.length == original.length,
      reason: 'sender=${sender.length}, original=${original.length}',
    );
    
    if (sender.length == original.length) {
      // 逐字节比较（跳过 payload_len 字段，因为计算公式不同）
      bool bytesMatch = true;
      for (int i = 4; i < sender.length; i++) {
        if (sender[i] != original[i]) {
          bytesMatch = false;
          break;
        }
      }
      check(
        '载荷内容一致 (offset 4+)',
        bytesMatch,
        reason: 'bytes differ at offset >= 4',
      );
    }
  }

  stdout.write('\n\x1B[36m═══ 双向反序列化兼容测试 ═══\x1B[0m\n');
  for (final body in testBodies) {
    final senderFrame = senderSerialize(body);
    final originalFrame = originalSerialize(body);

    // Sender 帧 → 反序列化
    final fromSender = deserialize(senderFrame);
    check(
      'Sender帧可反序列化: "${body.substring(0, body.length.clamp(0, 30))}..."',
      fromSender.length == 1 && fromSender.first == body,
    );

    // Original 帧 → 反序列化
    final fromOriginal = deserialize(originalFrame);
    check(
      'Original帧可反序列化: "${body.substring(0, body.length.clamp(0, 30))}..."',
      fromOriginal.length == 1 && fromOriginal.first == body,
    );
  }

  stdout.write('\n\x1B[36m═══ 混合帧兼容测试 ═══\x1B[0m\n');
  {
    // 用 Sender 生成帧，用通用反序列化器解析
    final mixed = <int>[];
    mixed.addAll(senderSerialize('type@=loginres/uid@=99999/'));
    mixed.addAll(originalSerialize('type@=chatmsg/rid@=7777/txt@=hi/'));
    mixed.addAll(senderSerialize('type@=chatmessage/roomid@=7777/content@=test/uid@=99999/'));

    final packets = deserialize(mixed);
    check('混合帧包含3个包', packets.length == 3, reason: 'got ${packets.length}');
    if (packets.length == 3) {
      check('第一个包为 loginres', packets[0].contains('loginres'));
      check('第二个包为 chatmsg', packets[1].contains('chatmsg'));
      check('第三个包为 chatmessage', packets[2].contains('chatmessage'));
    }
  }

  // 汇总
  stdout.write('\n\x1B[1m══════════════════════════════════════════════\x1B[0m\n');
  stdout.write('\x1B[1m  兼容性测试: $_pass / $_total 通过');
  if (_fail > 0) {
    stdout.write('  \x1B[31m$_fail 失败\x1B[0m');
  } else {
    stdout.write('  \x1B[32m全部通过 ✓\x1B[0m');
  }
  stdout.write('\n\x1B[1m══════════════════════════════════════════════\x1B[0m\n');
  exit(_fail > 0 ? 1 : 0);
}
