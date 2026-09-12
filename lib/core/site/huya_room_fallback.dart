import 'dart:async';
import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:pure_live/core/common/core_log.dart';

/// 虎牙房间信息回退获取。
///
/// mp.huya.com 的 profileRoom 接口在无 cookie（未登录虎牙）时对在播房间
/// 返回 liveStatus=OFF 且 stream 为空（风控）。此时用隐藏 WebView 加载
/// 房间页：真实浏览器 JS 环境可通过虎牙校验，页面内嵌的
/// hyPlayerConfig.stream 携带真实的开播状态与流列表（gameStreamInfoList，
/// 字段与 mp 接口 baseSteamInfoList 同构）。
class HuyaRoomPageData {
  /// 房间页的流列表，字段与 mp 接口 baseSteamInfoList 一致。
  final List<Map<dynamic, dynamic>> streamLines;

  final String nick;
  final String avatar;
  final String introduction;
  final String screenshot;
  final String gameFullName;
  final int uid;
  final int startTimeSec;
  final int totalCount;
  final int gid;

  const HuyaRoomPageData({
    required this.streamLines,
    required this.nick,
    required this.avatar,
    required this.introduction,
    required this.screenshot,
    required this.gameFullName,
    required this.uid,
    required this.startTimeSec,
    required this.totalCount,
    required this.gid,
  });

  static HuyaRoomPageData? fromMap(Map<dynamic, dynamic> map) {
    try {
      final live = map['live'];
      if (live is! Map) return null;
      final streams = (map['streams'] as List?) ?? const [];
      String textOf(dynamic v) => v?.toString() ?? '';
      return HuyaRoomPageData(
        streamLines: streams.whereType<Map<dynamic, dynamic>>().toList(),
        nick: textOf(live['nick']),
        avatar: textOf(live['avatar180']),
        introduction: textOf(live['introduction']),
        screenshot: textOf(live['screenshot']),
        gameFullName: textOf(live['gameFullName']),
        uid: (live['uid'] as num?)?.toInt() ?? 0,
        startTimeSec: (live['startTime'] as num?)?.toInt() ?? 0,
        totalCount: (live['totalCount'] as num?)?.toInt() ?? 0,
        gid: (live['gid'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}

const String _kExtractJs = '''
(function() {
  try {
    var room = (typeof TT_ROOM_DATA !== 'undefined') ? TT_ROOM_DATA : null;
    var data = (window.hyPlayerConfig && window.hyPlayerConfig.stream &&
                window.hyPlayerConfig.stream.data && window.hyPlayerConfig.stream.data[0])
        ? window.hyPlayerConfig.stream.data[0] : null;
    return JSON.stringify({
      isOn: room ? (room.isOn === true || room.state === 'ON') : false,
      live: data ? data.gameLiveInfo : null,
      streams: data ? (data.gameStreamInfoList || []) : []
    });
  } catch (e) { return JSON.stringify({ error: String(e) }); }
})();
''';

/// 用隐藏 WebView 抓取虎牙房间页数据；失败返回 null。
Future<HuyaRoomPageData?> fetchHuyaRoomInfoViaWebview(
  String roomId, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  HeadlessInAppWebView? headless;
  Timer? pollTimer;
  Timer? timeoutTimer;
  final completer = Completer<HuyaRoomPageData?>();
  try {
    headless = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri('https://www.huya.com/$roomId')),
      initialSettings: InAppWebViewSettings(
        userAgent:
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.43",
        javaScriptEnabled: true,
        domStorageEnabled: true,
      ),
      onLoadStop: (controller, url) {
        // 页面脚本异步填充 hyPlayerConfig，轮询提取直到拿到流数据或超时
        pollTimer?.cancel();
        pollTimer = Timer.periodic(const Duration(milliseconds: 800), (timer) async {
          if (completer.isCompleted) {
            timer.cancel();
            return;
          }
          try {
            final raw = await controller.evaluateJavascript(source: _kExtractJs);
            if (raw == null || raw.toString() == 'null' || raw.toString().isEmpty) return;
            final decoded = raw is Map ? raw : jsonDecode(raw.toString());
            if (decoded is! Map) return;
            final streams = (decoded['streams'] as List?) ?? const [];
            if (streams.isEmpty) return;
            final data = HuyaRoomPageData.fromMap(decoded);
            if (data != null && !completer.isCompleted) {
              completer.complete(data);
              timer.cancel();
            }
          } catch (_) {}
        });
      },
    );
    await headless.run();
    timeoutTimer = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete(null);
    });
    return await completer.future;
  } catch (e) {
    CoreLog.error('huya webview fallback failed: $e');
    if (!completer.isCompleted) completer.complete(null);
    return null;
  } finally {
    pollTimer?.cancel();
    timeoutTimer?.cancel();
    try {
      await headless?.dispose();
    } catch (_) {}
  }
}
