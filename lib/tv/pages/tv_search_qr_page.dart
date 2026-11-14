import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/tv_theme.dart';

/// TV 搜索扫码输入页：电视起一次性 HTTP 服务并显示二维码，
/// 手机扫码后在手机上输入关键词，确定后 POST 回来，电视自动执行搜索。
///
/// URL 形如 http://<ip>:<port>/tv/<token>?action=search（action=search
/// 让手机端扫码分流走"输入搜索词"而不是"推送关注"）。
/// 端点：POST /tv/<token>/api/search，body {"keyword": "...", "platform": "bilibili"}
class TvSearchQrPage extends StatefulWidget {
  const TvSearchQrPage({super.key, required this.onSearch});

  /// 收到手机端输入后的回调：(keyword, platform)。platform 为空表示用电视当前选中的平台。
  final void Function(String keyword, String platform) onSearch;

  @override
  State<TvSearchQrPage> createState() => _TvSearchQrPageState();
}

class _TvSearchQrPageState extends State<TvSearchQrPage> {
  HttpServer? _server;
  String _url = '';
  String _status = '正在启动服务...';
  bool _received = false;
  bool _failed = false;
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
      final ip = await _lanIpv4();
      if (ip.isEmpty) {
        setState(() {
          _status = '获取局域网地址失败，请确认电视已连 Wi-Fi';
          _failed = true;
        });
        return;
      }
      _url = 'http://$ip:${server.port}/tv/$token?action=search';
      setState(() => _status = '等待手机扫码输入...');

      _expireTimer = Timer(const Duration(minutes: 5), () {
        if (!_received) _stop('等待超时，服务已关闭（可重新进入重试）');
      });

      await for (final request in server) {
        _handleRequest(request, token);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = '服务启动失败：$e';
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
      final segments = request.uri.pathSegments;
      final tokenOk = segments.length >= 4 && segments[0] == 'tv' && segments[1] == token && segments.last == 'search';
      if (!tokenOk) {
        request.response.statusCode = 404;
        await request.response.close();
        return;
      }
      final body = await utf8.decoder.bind(request).join();
      final data = body.isEmpty ? <String, dynamic>{} : jsonDecode(body) as Map<String, dynamic>;
      final keyword = (data['keyword']?.toString() ?? '').trim();
      final platform = (data['platform']?.toString() ?? '').trim();
      if (keyword.isEmpty) {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'data': false, 'error': 'empty keyword'}));
        await request.response.close();
        return;
      }

      _received = true;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'data': true}));
      await request.response.close();

      if (mounted) setState(() => _status = '已收到搜索词：$keyword');
      // 稍等片刻让手机收到响应，再回搜索页执行搜索
      Timer(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        _stop(null);
        Navigator.of(context).pop();
        widget.onSearch(keyword, platform);
      });
    } catch (e) {
      try {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'data': false, 'error': e.toString()}));
        await request.response.close();
      } catch (_) {}
      if (mounted) setState(() => _status = '处理失败：$e');
    }
  }

  void _stop(String? message) {
    _expireTimer?.cancel();
    _server?.close(force: true);
    _server = null;
    if (mounted && message != null) setState(() => _status = message);
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '手机扫码输入搜索词',
                    style: TextStyle(fontSize: context.tvSp(26), fontWeight: FontWeight.w700, color: TvTheme.textPrimary),
                  ),
                  SizedBox(height: context.tvDp(14)),
                  Text(
                    '1. 手机与电视连同一 Wi-Fi\n'
                    '2. 用手机端扫一扫扫描左侧二维码\n'
                    '3. 在手机上输入关键词，确定后电视自动开始搜索',
                    style: TextStyle(fontSize: context.tvSp(15), color: TvTheme.textSecondary, height: 1.7),
                  ),
                  SizedBox(height: context.tvDp(18)),
                  Row(
                    children: [
                      if (_received)
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
                            color: _received ? Colors.greenAccent : (_failed ? Colors.redAccent : TvTheme.textPrimary),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: context.tvDp(14)),
                  Text(
                    '按返回键取消',
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
