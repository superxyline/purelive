import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/danmaku/douyu_chat_sender.dart';
import 'package:pure_live/core/danmaku/douyu_danmaku.dart';

void main() {
  group('DouyuChatSender - 序列化协议测试', () {
    test('serializeDouyu 产生正确的二进制帧格式', () {
      final body = 'type@=mrkl/';
      final frame = DouyuChatSender.serializeDouyu(body);

      // 验证帧结构
      // [4 LE] payload_len = 4 + 4 + body.length + 1
      // [4 LE] payload_len (重复)
      // [2 LE] 689 (magic)
      // [1] 0 (encrypted)
      // [1] 0 (reserved)
      // [N] body UTF-8
      // [1] 0x00 (null terminator)
      final bodyBytes = utf8.encode(body);
      final expectedPayloadLen = 4 + 4 + bodyBytes.length + 1;
      final expectedFrameLen = 4 + expectedPayloadLen;

      expect(frame.length, equals(expectedFrameLen));

      // 验证 payload_len (little-endian uint32)
      final bd = ByteData.sublistView(Uint8List.fromList(frame));
      expect(bd.getUint32(0, Endian.little), equals(expectedPayloadLen));
      expect(bd.getUint32(4, Endian.little), equals(expectedPayloadLen));

      // 验证 magic number (689)
      expect(frame[8], equals(689 & 0xFF));
      expect(frame[9], equals((689 >> 8) & 0xFF));

      // 验证加密标志和保留字节
      expect(frame[10], equals(0)); // encrypted
      expect(frame[11], equals(0)); // reserved

      // 验证 body
      final extractedBody = utf8.decode(frame.sublist(12, 12 + bodyBytes.length));
      expect(extractedBody, equals(body));

      // 验证尾部 null
      expect(frame[12 + bodyBytes.length], equals(0));
    });

    test('deserializeDouyuPackets 正确解析单个包', () {
      final body = 'type@=chatmsg/rid@=100/txt@=hello/';
      final frame = DouyuChatSender.serializeDouyu(body);

      final packets = DouyuChatSender.deserializeDouyuPackets(frame);
      expect(packets.length, equals(1));
      expect(packets.first, equals(body));
    });

    test('deserializeDouyuPackets 正确解析多个包', () {
      final body1 = 'type@=chatmsg/rid@=100/txt@=hello/';
      final body2 = 'type@=dgb/rid@=100/gn@=gift/';
      final frame1 = DouyuChatSender.serializeDouyu(body1);
      final frame2 = DouyuChatSender.serializeDouyu(body2);

      final combined = [...frame1, ...frame2];
      final packets = DouyuChatSender.deserializeDouyuPackets(combined);

      expect(packets.length, equals(2));
      expect(packets[0], equals(body1));
      expect(packets[1], equals(body2));
    });

    test('deserializeDouyuPackets 处理空数据', () {
      final packets = DouyuChatSender.deserializeDouyuPackets([]);
      expect(packets, isEmpty);
    });

    test('deserializeDouyuPackets 处理截断数据', () {
      final body = 'type@=mrkl/';
      final frame = DouyuChatSender.serializeDouyu(body);
      // 截断最后一半
      final truncated = frame.sublist(0, frame.length ~/ 2);
      final packets = DouyuChatSender.deserializeDouyuPackets(truncated);
      expect(packets, isEmpty);
    });
  });

  group('DouyuChatSender - STT 解析测试', () {
    test('parseStt 正确解析键值对', () {
      final result = DouyuChatSender.parseStt('type@=chatmsg/rid@=100/');
      expect(result, isA<Map>());
      expect(result['type'], equals('chatmsg'));
      expect(result['rid'], equals('100'));
    });

    test('parseStt 处理转义字符', () {
      final result = DouyuChatSender.parseStt('txt@=hello@Sworld/');
      expect(result['txt'], equals('hello/world'));
    });

    test('parseStt 处理 @A 转义', () {
      final result = DouyuChatSender.parseStt('txt@=hello@A@A/');
      expect(result['txt'], equals('hello@@'));
    });

    test('parseStt 处理简单字符串（无 @=）', () {
      final result = DouyuChatSender.parseStt('hello');
      expect(result, equals('hello'));
    });
  });

  group('DouyuChatSender - 构建消息测试', () {
    test('buildLoginReq 生成正确的登录请求', () {
      final body = DouyuChatSender.buildLoginReq(
        roomId: '7777',
        devid: 'test-devid-1234',
        rt: '1700000000',
      );

      expect(body, contains('type@=loginreq'));
      expect(body, contains('roomid@=7777'));
      expect(body, contains('devid@=test-devid-1234'));
      expect(body, contains('rt@=1700000000'));
      expect(body, contains('ver@=21952015'));
      expect(body, contains('vk@='));
      expect(body, contains('ct@=1'));
    });

    test('buildLoginReq 包含 stk 和 aa1', () {
      final body = DouyuChatSender.buildLoginReq(
        roomId: '7777',
        stk: 'test_stk',
        aa1: 'test_aa1',
      );

      expect(body, contains('stk@=test_stk'));
      expect(body, contains('aa1@=test_aa1'));
    });

    test('buildLoginReq 不包含空的 stk', () {
      final body = DouyuChatSender.buildLoginReq(
        roomId: '7777',
        stk: '',
        aa1: '',
      );

      expect(body.contains('stk@='), isFalse);
      expect(body.contains('aa1@='), isFalse);
    });

    test('buildJoinGroup 生成正确的加入请求', () {
      final body = DouyuChatSender.buildJoinGroup(roomId: '7777');
      expect(body, equals('type@=joingroup/rid@=7777/gid@=-9999/'));
    });

    test('buildChatMessage 生成正确的弹幕请求', () {
      final body = DouyuChatSender.buildChatMessage(
        content: '测试弹幕',
        roomId: '7777',
        uid: '12345',
        nickname: '测试用户',
      );

      expect(body, contains('type@=chatmessage'));
      expect(body, contains('roomid@=7777'));
      expect(body, contains('content@=测试弹幕'));
      expect(body, contains('uid@=12345'));
      expect(body, contains('nn@=测试用户'));
      expect(body, contains('txt@=测试弹幕'));
      expect(body, contains('dms@=5'));
      expect(body, contains('col@=0'));
    });

    test('buildChatMessage 默认昵称为 guest', () {
      final body = DouyuChatSender.buildChatMessage(
        content: 'hello',
        roomId: '7777',
        uid: '12345',
      );

      expect(body, contains('nn@=guest'));
    });

    test('buildHeartbeat 生成正确的心跳', () {
      final body = DouyuChatSender.buildHeartbeat();
      expect(body, equals('type@=mrkl/'));
    });
  });

  group('DouyuChatSender - VK 计算测试', () {
    test('generateVk 产生一致的哈希值', () {
      final vk1 = DouyuChatSender.generateVk('7777', 'device-123', '1700000000');
      final vk2 = DouyuChatSender.generateVk('7777', 'device-123', '1700000000');
      expect(vk1, equals(vk2));
    });

    test('generateVk 不同输入产生不同输出', () {
      final vk1 = DouyuChatSender.generateVk('7777', 'device-123', '1700000000');
      final vk2 = DouyuChatSender.generateVk('8888', 'device-123', '1700000000');
      expect(vk1, isNot(equals(vk2)));
    });

    test('generateVk 产生32位十六进制字符串', () {
      final vk = DouyuChatSender.generateVk('7777', 'device-123', '1700000000');
      expect(vk.length, equals(32));
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(vk), isTrue);
    });
  });

  group('DouyuChatSender - Cookie 解析测试', () {
    test('extractCookieValue 正确提取值', () {
      expect(
        DouyuChatSender.extractCookieValue('acf_uid=12345; acf_stk=abc', 'acf_uid'),
        equals('12345'),
      );
    });

    test('extractCookieValue 不存在的字段返回空', () {
      expect(
        DouyuChatSender.extractCookieValue('acf_uid=12345', 'acf_stk'),
        equals(''),
      );
    });

    test('extractCookieValue 空 Cookie 返回空', () {
      expect(
        DouyuChatSender.extractCookieValue('', 'acf_uid'),
        equals(''),
      );
    });

    test('extractAuthInfo 从 Cookie 提取认证信息', () {
      final sender = DouyuChatSender(
        cookie: 'acf_uid=12345; acf_stk=abcdef; acf_aa1=xyz789',
      );
      final auth = sender.extractAuthInfo();
      expect(auth, isNotNull);
      expect(auth!.uid, equals('12345'));
      expect(auth.stk, equals('abcdef'));
      expect(auth.aa1, equals('xyz789'));
    });

    test('extractAuthInfo 空 Cookie 返回 null', () {
      final sender = DouyuChatSender(cookie: '');
      expect(sender.extractAuthInfo(), isNull);
    });

    test('extractAuthInfo 无 acf_uid 返回 null', () {
      final sender = DouyuChatSender(cookie: 'acf_stk=abc');
      expect(sender.extractAuthInfo(), isNull);
    });
  });

  group('DouyuChatSender - 与现有 DouyuDanmaku 协议兼容性测试', () {
    test('DouyuChatSender 和 DouyuDanmaku 使用相同的帧格式', () {
      final body = 'type@=chatmsg/rid@=100/txt@=hello/';
      final senderFrame = DouyuChatSender.serializeDouyu(body);
      final danmaku = DouyuDanmaku();
      final danmakuFrame = danmaku.serializeDouyu(body);

      expect(senderFrame, equals(danmakuFrame));
    });

    test('DouyuDanmaku 可以解析 DouyuChatSender 生成的帧', () {
      final body = 'type@=chatmsg/rid@=100/txt@=hello/';
      final frame = DouyuChatSender.serializeDouyu(body);
      final danmaku = DouyuDanmaku();

      final packets = danmaku.deserializeDouyuPackets(frame);
      expect(packets.length, equals(1));
      expect(packets.first, equals(body));
    });

    test('DouyuChatSender 可以解析 DouyuDanmaku 生成的帧', () {
      final body = 'type@=chatmsg/rid@=100/txt@=hello/';
      final danmaku = DouyuDanmaku();
      final frame = danmaku.serializeDouyu(body);

      final packets = DouyuChatSender.deserializeDouyuPackets(frame);
      expect(packets.length, equals(1));
      expect(packets.first, equals(body));
    });

    test('sttToJObject 和 parseStt 产生相同结果', () {
      final body = 'type@=chatmsg/rid@=100/txt@=hello/world/';
      final danmaku = DouyuDanmaku();

      final resultDanmaku = danmaku.sttToJObject(body);
      final resultSender = DouyuChatSender.parseStt(body);

      // Both should produce the same structure
      expect(resultDanmaku.toString(), equals(resultSender.toString()));
    });
  });

  group('DouyuChatSender - 发送消息端到端模拟测试', () {
    test('完整的登录→加入→发送消息帧序列', () {
      // 模拟完整的发送流程中的帧序列
      const roomId = '7777';
      const devid = 'test-device-1234';
      const rt = '1700000000';
      const uid = '99999';
      const message = '你好斗鱼';

      // 1. 登录请求
      final loginBody = DouyuChatSender.buildLoginReq(
        roomId: roomId,
        devid: devid,
        rt: rt,
      );
      final loginFrame = DouyuChatSender.serializeDouyu(loginBody);
      expect(loginFrame, isNotEmpty);

      // 2. 加入分组
      final joinBody = DouyuChatSender.buildJoinGroup(roomId: roomId);
      final joinFrame = DouyuChatSender.serializeDouyu(joinBody);
      expect(joinFrame, isNotEmpty);

      // 3. 发送弹幕
      final chatBody = DouyuChatSender.buildChatMessage(
        content: message,
        roomId: roomId,
        uid: uid,
        nickname: '测试用户',
      );
      final chatFrame = DouyuChatSender.serializeDouyu(chatBody);
      expect(chatFrame, isNotEmpty);

      // 4. 验证每个帧都可以被反序列化
      final loginPackets = DouyuChatSender.deserializeDouyuPackets(loginFrame);
      expect(loginPackets.first, contains('type@=loginreq'));

      final joinPackets = DouyuChatSender.deserializeDouyuPackets(joinFrame);
      expect(joinPackets.first, contains('type@=joingroup'));

      final chatPackets = DouyuChatSender.deserializeDouyuPackets(chatFrame);
      expect(chatPackets.first, contains('type@=chatmessage'));
      expect(chatPackets.first, contains('content@=$message'));

      // 5. 验证解析后的字段
      final parsed = DouyuChatSender.parseStt(chatPackets.first) as Map;
      expect(parsed['type'], equals('chatmessage'));
      expect(parsed['roomid'], equals(roomId));
      expect(parsed['content'], equals(message));
      expect(parsed['uid'], equals(uid));
      expect(parsed['nn'], equals('测试用户'));
    });

    test('generateDeviceId 返回有效的 UUID 格式', () {
      final devid1 = DouyuChatSender.generateDeviceId();
      final devid2 = DouyuChatSender.generateDeviceId();

      // UUID 格式: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
      final uuidRegex = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
      expect(uuidRegex.hasMatch(devid1), isTrue, reason: 'devid1 should match UUID format');
      expect(uuidRegex.hasMatch(devid2), isTrue, reason: 'devid2 should match UUID format');
      expect(devid1, isNot(equals(devid2)), reason: 'Each call should generate a unique ID');
    });
  });

  group('DouyuChatSender - 错误处理测试', () {
    test('serializeDouyu 处理空字符串', () {
      final frame = DouyuChatSender.serializeDouyu('');
      expect(frame, isNotEmpty); // 仍然有帧头和尾部null
    });

    test('serializeDouyu 处理 Unicode 内容', () {
      final body = 'type@=chatmessage/content@=你好世界🎉/';
      final frame = DouyuChatSender.serializeDouyu(body);
      final packets = DouyuChatSender.deserializeDouyuPackets(frame);
      expect(packets.first, equals(body));
    });

    test('deserializeDouyuPackets 处理不完整的帧头', () {
      // 只有3个字节，不足4字节帧头
      final packets = DouyuChatSender.deserializeDouyuPackets([1, 2, 3]);
      expect(packets, isEmpty);
    });
  });

  group('DouyuChatSender - DouyuAuthInfo 测试', () {
    test('isValid 检查', () {
      const valid = DouyuAuthInfo(uid: '12345');
      const invalid = DouyuAuthInfo(uid: '');
      expect(valid.isValid, isTrue);
      expect(invalid.isValid, isFalse);
    });

    test('toString 包含关键信息', () {
      const auth = DouyuAuthInfo(uid: '12345', stk: 'abc');
      expect(auth.toString(), contains('12345'));
      expect(auth.toString(), contains('present'));
    });
  });
}
