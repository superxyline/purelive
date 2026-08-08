import 'dart:convert';
import 'dart:developer';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pro_mpack/pro_mpack.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/global/platform_utils.dart';

class ShareCommandCodec {
  static const String _magic = 'pure_live';

  static String encodeShort(Map<String, dynamic> data) {
    try {
      final mpack = MessagePack();
      final d = data['d'] ?? data;
      final map = {
        'm': _magic,
        'p': d['platform'] ?? '',
        'r': d['roomId'] ?? '',
        'ti': d['title'] ?? '',
        'n': d['nick'] ?? '',
        'l': d['link'] ?? '',
        'c': d['cover'] ?? '',
        'a': d['avatar'] ?? '',
      };
      final bytes = mpack.pack(map);
      return base64.encode(bytes).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
    } catch (_) {
      return '';
    }
  }

  static Map<String, dynamic>? decodeShort(String code) {
    try {
      final mpack = MessagePack();
      code = code.replaceAll('-', '+').replaceAll('_', '/');
      code = code.padRight(code.length + (4 - code.length % 4) % 4, '=');
      final bytes = base64.decode(code);
      final unpacked = mpack.unpack<Map>(bytes);
      if (unpacked['m'] != _magic) return null;
      return {
        'platform': unpacked['p'] ?? '',
        'roomId': unpacked['r'] ?? '',
        'title': unpacked['ti'] ?? '',
        'nick': unpacked['n'] ?? '',
        'link': unpacked['l'] ?? '',
        'cover': unpacked['c'] ?? '',
        'avatar': unpacked['a'] ?? '',
      };
    } catch (_) {
      return null;
    }
  }

  static bool isMyCommand(String text) {
    return decodeShort(text) != null;
  }
}

class ShareCommandHandler {
  static final ShareCommandHandler instance = ShareCommandHandler._internal();

  ShareCommandHandler._internal();

  final Set<String> _blacklistHashes = {};
  String _lastProcessedHashInLifecycle = "";

  String _getMd5(String text) {
    return md5.convert(utf8.encode(text.trim())).toString();
  }

  void resetLifecycleCache() {
    _lastProcessedHashInLifecycle = "";
  }

  Future<void> checkClipboard(Function(String roomInfo) onMatchFound) async {
    try {
      ClipboardData? clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipboardData == null || clipboardData.text == null) return;

      String currentText = clipboardData.text!.trim();
      if (currentText.isEmpty) return;

      final currentHash = _getMd5(currentText);

      if (_blacklistHashes.contains(currentHash)) {
        return;
      }

      if (currentHash == _lastProcessedHashInLifecycle) {
        return;
      }

      final isMyCommand = ShareCommandCodec.isMyCommand(currentText);
      if (!isMyCommand) return;

      _lastProcessedHashInLifecycle = currentHash;
      onMatchFound(currentText);
    } catch (e) {
      log(e.toString(), name: 'ShareCommandHandler');
    }
  }

  Future<void> onShareRoomPressed(LiveRoom room) async {
    final Map<String, dynamic> shareMap = {
      'platform': room.platform,
      'roomId': room.roomId,
      'title': room.title,
      'link': room.link,
      'cover': room.cover,
      'avatar': room.avatar,
      'nick': room.nick,
    };
    final String secret = ShareCommandCodec.encodeShort(shareMap);

    _blacklistHashes.add(_getMd5(secret));
    _blacklistHashes.add(_getMd5("$secret "));
    _blacklistHashes.add(_getMd5("\n$secret"));

    if (PlatformUtils.isDesktop) {
      await Clipboard.setData(ClipboardData(text: secret));
      SnackBarUtil.success(i18n('copied_to_clipboard'));
    } else {
      await SharePlus.instance.share(ShareParams(text: secret));
      try {
        ClipboardData? postShareData = await Clipboard.getData(Clipboard.kTextPlain);
        if (postShareData?.text != null) {
          _blacklistHashes.add(_getMd5(postShareData!.text!));
        }
      } catch (_) {}
    }
  }
}
