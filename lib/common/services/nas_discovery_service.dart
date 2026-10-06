import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pure_live/get/get.dart';

/// 局域网发现的 Pure Live 服务信息
class NasServiceInfo {
  final String ip;
  final int port;
  final int follows;
  final int shields;

  NasServiceInfo({required this.ip, required this.port, this.follows = 0, this.shields = 0});

  String get address => 'http://$ip:$port';
  String get label => 'Pure Live · $follows 个关注 · $ip:$port';
}

/// 局域网自动发现 NAS 上运行的 Pure Live 服务（fpk / docker / 便携版通吃）。
///
/// 原理：App 主动对所在 /24 网段的 8090 端口并发发 HTTP 探测——
/// 先 GET /api/health（所有版本都有）确认存活，再 GET /api/discover（新版本）
/// 取关注/屏蔽数量；discover 不存在的旧 server 只显示地址。
/// 不依赖 mDNS/组播，因此 docker bridge 网络也不受影响。
class NasDiscoveryService {
  /// 默认探测端口：fpk=8090、docker 版 nginx=8090、Windows 便携版=8090
  static const int defaultPort = 8090;

  /// 并发探测协程数（254 个地址分批跑，避免一次性开满 socket）
  static const int _concurrency = 50;

  /// 扫描本机所在 /24 网段，返回发现的服务列表（按关注数降序）。
  /// [onProgress] 0.0~1.0 进度回调（可选）。
  static Future<List<NasServiceInfo>> discover({
    int port = defaultPort,
    Duration timeout = const Duration(milliseconds: 600),
    void Function(double progress)? onProgress,
  }) async {
    final targets = <String>{};
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final itf in interfaces) {
        for (final addr in itf.addresses) {
          final octets = addr.address.split('.');
          if (octets.length != 4) continue;
          // 只扫常见家用网段（10./172.16-31./192.168.），公网地址不扫
          final isPrivate = octets[0] == '192' && octets[1] == '168' ||
              octets[0] == '10' ||
              (octets[0] == '172' && int.parse(octets[1]) >= 16 && int.parse(octets[1]) <= 31);
          if (!isPrivate) continue;
          final prefix = '${octets[0]}.${octets[1]}.${octets[2]}.';
          for (var i = 1; i <= 254; i++) {
            final ip = '$prefix$i';
            if (ip == addr.address) continue;
            targets.add(ip);
          }
        }
      }
    } catch (_) {
      return [];
    }
    if (targets.isEmpty) return [];

    final client = HttpClient()..connectionTimeout = timeout;
    final found = <NasServiceInfo>[];
    var done = 0;
    final ipList = targets.toList();

    Future<void> probe(String ip) async {
      final info = await _probe(client, ip, port, timeout);
      if (info != null) found.add(info);
      done++;
      onProgress?.call(done / ipList.length);
    }

    // 分批并发
    for (var i = 0; i < ipList.length; i += _concurrency) {
      final batch = <Future<void>>[];
      for (var j = i; j < i + _concurrency && j < ipList.length; j++) {
        batch.add(probe(ipList[j]));
      }
      await Future.wait(batch);
    }
    client.close(force: true);

    found.sort((a, b) => b.follows.compareTo(a.follows));
    return found;
  }

  static Future<NasServiceInfo?> _probe(
    HttpClient client,
    String ip,
    int port,
    Duration timeout,
  ) async {
    try {
      // 1. 存活探测（/api/health 所有部署形态都有）
      final health = await _getJson(client, ip, port, '/api/health', timeout);
      if (health == null || health['ok'] != true) return null;
      // 2. 服务信息（新版本才有；旧 server 显示默认标题）
      final disc = await _getJson(client, ip, port, '/api/discover', timeout);
      return NasServiceInfo(
        ip: ip,
        port: port,
        follows: disc?['follows'] is int ? disc!['follows'] as int : 0,
        shields: disc?['shields'] is int ? disc!['shields'] as int : 0,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> _getJson(
    HttpClient client,
    String ip,
    int port,
    String path,
    Duration timeout,
  ) async {
    try {
      final req = await client
          .getUrl(Uri.parse('http://$ip:$port$path'))
          .timeout(timeout);
      final resp = await req.close().timeout(timeout);
      if (resp.statusCode != 200) return null;
      final body = await resp.transform(utf8.decoder).join().timeout(timeout);
      final json = jsonDecode(body);
      return json is Map ? Map<String, dynamic>.from(json) : null;
    } catch (_) {
      return null;
    }
  }
}
