import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:pure_live/common/index.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/tv_theme.dart';

/// TV 扫码同步关注页：
///
/// 电视在本机起一次性 HTTP 服务并显示二维码，手机端用
/// 「备份 → 扫码推送」（现有流程，零改动）扫描后，会把
/// exportToTVSettings() 载荷（含 favoriteRooms 完整列表）POST 过来；
/// 本页做**并集合并**（按 platform+roomId 去重，保留电视已有+新增手机多出的），
/// 成功后自动刷新开播状态。其余设置项（弹幕等）不导入。
///
/// 服务只在局域网可达、URL 含一次性随机 token（校验路径第一段），
/// 收到一次成功推送即自动关闭。
class TvSyncPage extends StatefulWidget {
  const TvSyncPage({super.key, this.onSynced});

  /// 同步成功后回调（宿主刷新开播状态）
  final VoidCallback? onSynced;

  @override
  State<TvSyncPage> createState() => _TvSyncPageState();
}

class _TvSyncPageState extends State<TvSyncPage> {
  HttpServer? _server;
  String _url = '';
  String _status = '正在启动同步服务...';
  bool _done = false;
  bool _failed = false;
  int _added = 0;
  int _total = 0;
  Timer? _expireTimer;

  @override
  void initState() {
    super.initState();
    _startServer();
  }

  Future<void> _startServer() async {
    try {
      final token = _randomToken();
      final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      _server = server;
      final port = server.port;
      final ip = await _lanIpv4();
      if (ip.isEmpty) {
        setState(() {
          _status = '获取局域网地址失败，请确认电视已连 Wi-Fi';
          _failed = true;
        });
        return;
      }
      _url = 'http://$ip:$port/tv/$token';
      debugPrint('[TvSync] url=$_url');
      setState(() => _status = '等待手机扫码推送...');

      // 5 分钟无人推送自动过期
      _expireTimer = Timer(const Duration(minutes: 5), () {
        if (!_done) _stop('等待超时，服务已关闭（可重新进入重试）');
      });

      await for (final request in server) {
        _handleRequest(request, token);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = '同步服务启动失败：$e';
          _failed = true;
        });
      }
    }
  }

  Future<String> _lanIpv4() async {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
    for (final itf in interfaces) {
      for (final addr in itf.addresses) {
        final octets = addr.address.split('.');
        if (octets.length != 4) continue;
        final isPrivate = octets[0] == '192' && octets[1] == '168' ||
            octets[0] == '10' ||
            (octets[0] == '172' && int.parse(octets[1]) >= 16 && int.parse(octets[1]) <= 31);
        if (isPrivate) return addr.address;
      }
    }
    return '';
  }

  String _randomToken() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List.generate(8, (_) => chars[random.nextInt(chars.length)]).join();
  }

  Future<void> _handleRequest(HttpRequest request, String token) async {
    try {
      // 路径校验：/tv/<token>/api/setSettings（/tv 前缀是手机端识别电视的标记）
      final segments = request.uri.pathSegments;
      final tokenOk = segments.length >= 4 &&
          segments[0] == 'tv' &&
          segments[1] == token &&
          segments.last == 'setSettings';
      if (!tokenOk) {
        request.response.statusCode = 404;
        await request.response.close();
        return;
      }

      // 载荷读请求体（手机端 pushDataToTv 以 body 发送，规避 URL 长度上限）
      final body = await utf8.decoder.bind(request).join();
      if (body.isEmpty) {
        request.response.statusCode = 400;
        await request.response.close();
        return;
      }
      final data = jsonDecode(body) as Map<String, dynamic>;

      final roomsJson = _extractFavoriteRooms(data);
      final added = _mergeFavorites(roomsJson);

      // 登录态随载荷带入（cookie 字段存在才导入，缺失不动本地）
      var cookieImported = false;
      try {
        final cookie = data['cookie'];
        if (cookie is Map && cookie.isNotEmpty) {
          SettingsService.to.cookieManager.fromJson(Map<String, dynamic>.from(cookie));
          cookieImported = true;
        }
      } catch (_) {}

      _added = added;
      _total = SettingsService.to.fav.favoriteRooms.v.length;
      _done = true;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'data': true, 'added': added, 'total': _total, 'cookie': cookieImported}));
      await request.response.close();

      if (mounted) {
        setState(() {
          _status = '同步成功：新增 $added 个关注，当前共 $_total 个'
              '${cookieImported ? '，登录态已导入' : ''}';
        });
      }
      widget.onSynced?.call();
      // 稍等片刻让手机收到响应，再关闭服务
      Timer(const Duration(seconds: 2), () {
        if (mounted) _stop(null);
      });
    } catch (e) {
      try {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'data': false, 'error': e.toString()}));
        await request.response.close();
      } catch (_) {}
      if (mounted) {
        setState(() => _status = '推送处理失败：$e');
      }
    }
  }

  /// 从设置载荷提取关注列表（兼容 favoriteRooms.{list|直接数组} 两种结构）
  List<dynamic> _extractFavoriteRooms(Map<String, dynamic> data) {
    final fav = data['favoriteRooms'];
    if (fav is Map) {
      final list = fav['list'];
      if (list is List) return list;
    }
    if (fav is List) return fav;
    // 兜底：跨端传输载荷 data['favorite'] = FavoriteRoomController.toJson()，
    // 其中 favoriteRooms 是直接数组（与 hive 层的 {list:[]} 形态不同）
    final legacy = data['favorite'];
    if (legacy is Map) {
      final legacyRooms = legacy['favoriteRooms'];
      if (legacyRooms is List) return legacyRooms;
      if (legacyRooms is Map && legacyRooms['list'] is List) return legacyRooms['list'] as List;
    }
    return const [];
  }

  /// 并集合并：按 platform+roomId 去重，新增的用手机端完整数据
  int _mergeFavorites(List<dynamic> roomsJson) {
    final current = SettingsService.to.fav.favoriteRooms.v;
    final existing = current.map((r) => '${r.platform}|${r.roomId}').toSet();
    final merged = List<LiveRoom>.from(current);
    var added = 0;
    for (final item in roomsJson) {
      if (item is! Map) continue;
      try {
        final room = LiveRoom.fromJson(Map<String, dynamic>.from(item));
        if ((room.platform?.isEmpty ?? true) || (room.roomId?.isEmpty ?? true)) continue;
        final key = '${room.platform}|${room.roomId}';
        if (existing.contains(key)) continue;
        existing.add(key);
        merged.add(room);
        added++;
      } catch (_) {
        // 单条解析失败跳过
      }
    }
    if (added > 0) {
      SettingsService.to.fav.favoriteRooms.v = merged;
    }
    return added;
  }

  void _stop(String? message) {
    _expireTimer?.cancel();
    _server?.close(force: true);
    _server = null;
    if (mounted && message != null) {
      setState(() => _status = message);
    }
  }

  @override
  void dispose() {
    _expireTimer?.cancel();
    _server?.close(force: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Padding(
        padding: EdgeInsets.all(context.tvDp(24)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 左：二维码
            Container(
              width: context.tvDp(280),
              height: context.tvDp(280),
              padding: EdgeInsets.all(context.tvDp(12)),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(context.tvDp(16)),
              ),
              child: _url.isEmpty
                  ? Center(
                      child: SizedBox(
                        width: context.tvDp(28),
                        height: context.tvDp(28),
                        child: const CircularProgressIndicator(color: TvTheme.focusColor),
                      ),
                    )
                  : QrImageView(data: _url, version: QrVersions.auto, gapless: false),
            ),
            SizedBox(width: context.tvDp(28)),
            // 右：说明与状态
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '扫码同步手机关注',
                    style: TextStyle(fontSize: context.tvSp(26), fontWeight: FontWeight.w700, color: TvTheme.textPrimary),
                  ),
                  SizedBox(height: context.tvDp(14)),
                  Text(
                    '1. 手机与电视连同一 Wi-Fi\n'
                    '2. 打开手机端「我的 → 备份 → 扫码推送」\n'
                    '3. 扫描左侧二维码，手机关注的直播间将合并到电视（已有的不重复）',
                    style: TextStyle(fontSize: context.tvSp(15), color: TvTheme.textSecondary, height: 1.7),
                  ),
                  SizedBox(height: context.tvDp(18)),
                  Row(
                    children: [
                      if (_done)
                        Icon(Icons.check_circle_rounded, size: context.tvDp(22), color: Colors.greenAccent)
                      else if (_failed)
                        Icon(Icons.error_rounded, size: context.tvDp(22), color: Colors.redAccent)
                      else
                        SizedBox(
                          width: context.tvDp(18),
                          height: context.tvDp(18),
                          child: const CircularProgressIndicator(strokeWidth: 2, color: TvTheme.focusColor),
                        ),
                      SizedBox(width: context.tvDp(8)),
                      Flexible(
                        child: Text(
                          _status,
                          style: TextStyle(
                            fontSize: context.tvSp(16),
                            color: _done ? Colors.greenAccent : (_failed ? Colors.redAccent : TvTheme.textPrimary),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: context.tvDp(14)),
                  Text(
                    '按返回键结束同步',
                    style: TextStyle(fontSize: context.tvSp(13), color: TvTheme.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
