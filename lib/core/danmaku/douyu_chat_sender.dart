import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:pure_live/core/common/binary_writer.dart';
import 'package:pure_live/core/common/core_log.dart';

/// 斗鱼弹幕发送器。
///
/// 独立于 [DouyuDanmaku] 实现，用于通过斗鱼 WebSocket 协议发送弹幕。
/// 发送流程：
///   1. 连接 `wss://danmuproxy.douyu.com:8506`
///   2. 发送 `loginreq` (带认证信息)
///   3. 接收 `loginres` (获取服务器分配的 uid)
///   4. 加入分组 `joingroup`
///   5. 发送 `chatmessage`
class DouyuChatSender {
  /// WebSocket 服务器地址
  final String serverUrl;

  /// 认证 Cookie 字符串 (包含 acf_uid, acf_stk, acf_aa1 等)
  final String cookie;

  /// 连接超时时间
  final Duration connectTimeout;

  /// 响应等待超时
  final Duration responseTimeout;

  DouyuChatSender({
    this.serverUrl = 'wss://danmuproxy.douyu.com:8506',
    required this.cookie,
    this.connectTimeout = const Duration(seconds: 10),
    this.responseTimeout = const Duration(seconds: 8),
  });

  /// 从 Cookie 中提取指定字段值
  static String extractCookieValue(String cookie, String name) {
    final regex = RegExp('(?:^|;\\s*)${RegExp.escape(name)}=([^;]*)');
    return regex.firstMatch(cookie)?.group(1) ?? '';
  }

  /// 生成设备ID (UUID without dashes)
  static String generateDeviceId() {
    final random = Random.secure();
    final values = List<int>.generate(16, (_) => random.nextInt(256));
    // Format as UUID
    final hex = values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  /// 生成 VK 验证密钥
  ///
  /// VK = md5(roomid + devid + rt + salt)
  static String generateVk(String roomId, String devid, String rt) {
    const salt = '123456789012345678901234567890';
    final raw = '$roomId$devid$rt$salt';
    // 使用 Dart 内置的 md5
    final bytes = utf8.encode(raw);
    // Simple MD5 implementation for compatibility
    return _md5Hex(bytes);
  }

  /// 简化的 MD5 哈希实现（返回十六进制字符串）
  static String _md5Hex(List<int> bytes) {
    // 使用 Dart 的加密库或手写 MD5
    // 这里使用一种简化方式 - 实际项目中应使用 crypto 包
    // 为了独立性，使用原生实现
    return _md5(bytes);
  }

  /// MD5 哈希计算（纯 Dart 实现）
  static String _md5(List<int> message) {
    // MD5 padding - use growable list
    final msg = List<int>.from(message);
    final originalLength = msg.length * 8;
    msg.add(0x80);
    while (msg.length % 64 != 56) {
      msg.add(0);
    }
    // Append original length as 64-bit little-endian
    final lenBytes = ByteData(8);
    lenBytes.setUint32(0, originalLength & 0xFFFFFFFF, Endian.little);
    lenBytes.setUint32(4, (originalLength >> 32) & 0xFFFFFFFF, Endian.little);
    msg.addAll(lenBytes.buffer.asUint8List());

    // Initialize hash values
    int a0 = 0x67452301;
    int b0 = 0xefcdab89;
    int c0 = 0x98badcfe;
    int d0 = 0x10325476;

    // Process each 64-byte block
    for (int i = 0; i < msg.length; i += 64) {
      final chunk = Uint8List.fromList(msg.sublist(i, i + 64));
      final m = List<int>.generate(16, (j) {
        final bd = ByteData.sublistView(chunk, j * 4, j * 4 + 4);
        return bd.getUint32(0, Endian.little);
      });

      int a = a0, b = b0, c = c0, d = d0;

      for (int j = 0; j < 64; j++) {
        int f, g;
        if (j < 16) {
          f = (b & c) | ((~b) & d);
          g = j;
        } else if (j < 32) {
          f = (d & b) | ((~d) & c);
          g = (5 * j + 1) % 16;
        } else if (j < 48) {
          f = b ^ c ^ d;
          g = (3 * j + 5) % 16;
        } else {
          f = c ^ (b | (~d));
          g = (7 * j) % 16;
        }
        f = (f + a + _md5K[j] + m[g]) & 0xFFFFFFFF;
        a = d;
        d = c;
        c = b;
        b = (b + _leftRotate32(f, _md5S[j])) & 0xFFFFFFFF;
      }
      a0 = (a0 + a) & 0xFFFFFFFF;
      b0 = (b0 + b) & 0xFFFFFFFF;
      c0 = (c0 + c) & 0xFFFFFFFF;
      d0 = (d0 + d) & 0xFFFFFFFF;
    }

    // Produce digest
    final digest = ByteData(16);
    digest.setUint32(0, a0, Endian.little);
    digest.setUint32(4, b0, Endian.little);
    digest.setUint32(8, c0, Endian.little);
    digest.setUint32(12, d0, Endian.little);
    return digest.buffer.asUint8List().map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static int _leftRotate32(int value, int shift) {
    return ((value << shift) | (value >>> (32 - shift))) & 0xFFFFFFFF;
  }

  static const List<int> _md5S = [
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
    5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
  ];

  static const List<int> _md5K = [
    0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
    0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
    0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
    0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
    0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
    0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
    0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
    0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
    0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
    0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
    0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
    0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
    0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
    0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
    0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
    0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
  ];

  /// 序列化 STT 消息为斗鱼二进制帧
  ///
  /// 帧结构:
  ///   [4 LE bytes] payload_len (header2 + body_bytes + trailing null)
  ///   [4 LE bytes] payload_len (duplicate)
  ///   [2 LE bytes] 689 (client→server magic)
  ///   [1 byte]    0 (encrypted flag)
  ///   [1 byte]    0 (reserved)
  ///   [N bytes]   UTF-8 encoded body
  ///   [1 byte]    0x00 (trailing null)
  static List<int> serializeDouyu(String body) {
    const int clientSendToServer = 689;
    const int encrypted = 0;
    const int reserved = 0;

    List<int> buffer = utf8.encode(body);
    // payload_len = len2(4) + magic(2) + encrypted(1) + reserved(1) + body(N) + null(1)
    final int payloadLen = 4 + 2 + 1 + 1 + buffer.length + 1;

    var writer = BinaryWriter([]);
    writer.writeInt(payloadLen, 4, endian: Endian.little);
    writer.writeInt(payloadLen, 4, endian: Endian.little);
    writer.writeInt(clientSendToServer, 2, endian: Endian.little);
    writer.writeInt(encrypted, 1, endian: Endian.little);
    writer.writeInt(reserved, 1, endian: Endian.little);
    writer.writeBytes(buffer);
    writer.writeInt(0, 1, endian: Endian.little);
    return writer.buffer;
  }

  /// 反序列化斗鱼二进制帧为 STT 字符串列表
  static List<String> deserializeDouyuPackets(List<int> buffer) {
    final packets = <String>[];
    try {
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
    } catch (e) {
      CoreLog.error(e);
    }
    return packets;
  }

  /// STT 字符串解析为 Map
  static dynamic parseStt(String str) {
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
        var v = _unescapeSlashAt(field.substring(separator + 2));
        result[k] = parseStt(v);
      }
      return result;
    } else if (str.contains('@A=')) {
      return parseStt(_unescapeSlashAt(str));
    } else {
      return _unescapeSlashAt(str);
    }
  }

  static String _unescapeSlashAt(String str) {
    return str.replaceAll('@S', '/').replaceAll('@A', '@');
  }

  /// 构建登录请求 STT
  static String buildLoginReq({
    required String roomId,
    String? uid,
    String? devid,
    String? rt,
    String? vk,
    String? stk,
    String? aa1,
  }) {
    final devidVal = devid ?? generateDeviceId();
    final rtVal = rt ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final vkVal = vk ?? generateVk(roomId, devidVal, rtVal);

    var body = 'type@=loginreq/'
        'roomid@=$roomId/'
        'devid@=$devidVal/'
        'rt@=$rtVal/'
        'ver@=21952015/'
        'vk@=$vkVal/'
        'ct@=1/';

    if (uid != null && uid.isNotEmpty) {
      body += 'uid@=$uid/';
    }
    if (stk != null && stk.isNotEmpty) {
      body += 'stk@=$stk/';
    }
    if (aa1 != null && aa1.isNotEmpty) {
      body += 'aa1@=$aa1/';
    }

    return body;
  }

  /// 构建加入分组请求 STT
  static String buildJoinGroup({required String roomId}) {
    return 'type@=joingroup/rid@=$roomId/gid@=-9999/';
  }

  /// 构建弹幕消息 STT
  ///
  /// [content] 弹幕内容
  /// [roomId] 房间号
  /// [uid] 用户ID (从 loginres 获取)
  /// [nickname] 用户昵称
  static String buildChatMessage({
    required String content,
    required String roomId,
    required String uid,
    String nickname = '',
    int color = 0,
  }) {
    final cst = DateTime.now().millisecondsSinceEpoch.toString();
    final safeNick = nickname.isEmpty ? 'guest' : nickname;
    return 'type@=chatmessage/'
        'roomid@=$roomId/'
        'content@=$content/'
        'col@=$color/'
        'pt@=0/'
        'ct@=$cst/'
        'sn@=0/'
        'ss@=0/'
        'uid@=$uid/'
        'nn@=$safeNick/'
        'txt@=$content/'
        'level@=1/'
        'dms@=5/'
        'cst@=$cst/';
  }

  /// 构建心跳请求 STT
  static String buildHeartbeat() {
    return 'type@=mrkl/';
  }

  /// 从 Cookie 中提取认证信息
  DouyuAuthInfo? extractAuthInfo() {
    if (cookie.isEmpty) return null;
    final uid = extractCookieValue(cookie, 'acf_uid');
    final stk = extractCookieValue(cookie, 'acf_stk');
    final aa1 = extractCookieValue(cookie, 'acf_aa1');
    if (uid.isEmpty) return null;
    return DouyuAuthInfo(uid: uid, stk: stk, aa1: aa1);
  }

  /// 发送弹幕（使用独立 WebSocket 连接）
  ///
  /// 这是核心方法：建立连接 → 登录 → 加入分组 → 发送弹幕
  /// 返回 (是否成功, 提示信息)
  Future<(bool, String)> send({
    required String roomId,
    required String content,
    String nickname = '',
  }) async {
    // 1. 验证认证信息
    final authInfo = extractAuthInfo();
    if (authInfo == null) {
      return (false, '未登录斗鱼账号，请先在设置中登录');
    }

    if (content.trim().isEmpty) {
      return (false, '弹幕内容不能为空');
    }

    // 2. 建立 WebSocket 连接
    WebSocket? ws;
    try {
      ws = await WebSocket.connect(
        serverUrl,
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      ).timeout(connectTimeout);
    } catch (e) {
      return (false, '连接斗鱼弹幕服务器失败: $e');
    }

    try {
      // 3. 发送登录请求
      final devid = generateDeviceId();
      final rt = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
      final loginBody = buildLoginReq(
        roomId: roomId,
        uid: authInfo.uid,
        devid: devid,
        rt: rt,
        stk: authInfo.stk,
        aa1: authInfo.aa1,
      );
      ws.add(serializeDouyu(loginBody));

      // 4. 等待登录响应
      final loginResponse = await _waitForResponse(ws, 'loginres');
      if (loginResponse == null) {
        return (false, '登录响应超时');
      }

      // 解析服务器分配的 uid
      final serverUid = loginResponse['userid']?.toString() ?? loginResponse['uid']?.toString() ?? '';
      if (serverUid.isEmpty || serverUid == '0') {
        if (authInfo.uid.isNotEmpty) { return (false, '登录失败：Cookie 可能已过期，请重新登录'); }
        return (false, '登录失败：服务器未返回有效用户ID');
      }

      // 5. 加入分组
      final joinBody = buildJoinGroup(roomId: roomId);
      ws.add(serializeDouyu(joinBody));

      // 等待加入响应 (可选，超时不报错)
      await _waitForResponse(ws, 'joingroup').timeout(
        const Duration(seconds: 3),
        onTimeout: () => null,
      );

      // 6. 发送弹幕
      final chatBody = buildChatMessage(
        content: content,
        roomId: roomId,
        uid: serverUid,
        nickname: nickname,
      );
      ws.add(serializeDouyu(chatBody));

      // 7. 等待确认
      // 斗鱼服务器可能返回错误消息或回显
      final confirmResponse = await _waitForAnyResponse(
        ws,
        timeout: const Duration(seconds: 5),
      );

      // 检查是否有错误
      if (confirmResponse != null) {
        final type = confirmResponse['type']?.toString() ?? '';
        if (type == 'error' || type == 'dimession') {
          final errorMsg = confirmResponse['msg']?.toString() ?? confirmResponse['txt']?.toString() ?? '未知错误';
          return (false, '发送失败: $errorMsg');
        }
      }

      // 如果没有收到错误，认为发送成功
      return (true, '发送成功');
    } catch (e) {
      CoreLog.error('斗鱼弹幕发送异常: $e');
      return (false, '发送异常: $e');
    } finally {
      // 8. 关闭连接
      try {
        await ws?.close();
      } catch (_) {}
    }
  }

  /// 等待指定类型的响应
  Future<Map<String, dynamic>?> _waitForResponse(WebSocket ws, String expectedType) async {
    final completer = Completer<Map<String, dynamic>?>();
    final subscription = ws.listen(
      (data) {
        if (completer.isCompleted) return;
        if (data is List<int>) {
          final packets = deserializeDouyuPackets(data);
          for (final packet in packets) {
            final parsed = parseStt(packet);
            if (parsed is Map) {
              final type = parsed['type']?.toString() ?? '';
              if (type == expectedType) {
                completer.complete(parsed.cast<String, dynamic>());
                return;
              }
            }
          }
        }
      },
      onError: (e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete(null);
      },
    );

    try {
      final result = await completer.future.timeout(responseTimeout);
      return result;
    } on TimeoutException {
      return null;
    } finally {
      await subscription.cancel();
    }
  }

  /// 等待任意响应（用于确认弹幕发送结果）
  Future<Map<String, dynamic>?> _waitForAnyResponse(
    WebSocket ws, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final completer = Completer<Map<String, dynamic>?>();
    Timer? timer;
    Map<String, dynamic>? lastResponse;

    final subscription = ws.listen(
      (data) {
        if (completer.isCompleted) return;
        if (data is List<int>) {
          final packets = deserializeDouyuPackets(data);
          for (final packet in packets) {
            final parsed = parseStt(packet);
            if (parsed is Map) {
              lastResponse = parsed.cast<String, dynamic>();
            }
          }
        }
      },
      onError: (e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
      onDone: () {
        if (!completer.isCompleted) {
          timer?.cancel();
          completer.complete(lastResponse);
        }
      },
    );

    timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.complete(lastResponse);
      }
    });

    try {
      return await completer.future;
    } finally {
      timer.cancel();
      await subscription.cancel();
    }
  }
}

/// 斗鱼认证信息
class DouyuAuthInfo {
  final String uid;
  final String stk;
  final String aa1;

  const DouyuAuthInfo({
    required this.uid,
    this.stk = '',
    this.aa1 = '',
  });

  bool get isValid => uid.isNotEmpty;

  @override
  String toString() => 'DouyuAuthInfo(uid: $uid, stk: ${stk.isNotEmpty ? "present" : "absent"})';
}
