import 'dart:io';

/// CDN 连接测速：对一组 host 做 TCP 连接计时，用于直播线路按延迟排序。
/// 只测 TCP 握手（不依赖 HTTP 层行为，避免 CDN 对 HEAD/GET 的差异）。
class CdnSpeedTest {
  CdnSpeedTest._();

  static const Duration _timeout = Duration(milliseconds: 1500);
  static const int _unreachable = 10000;

  /// 返回 host → 连接延迟（ms）。测不通的 host 记为不可达大值。
  /// 并发限制 6，避免同时大量握手触发 CDN 风控。
  static Future<Map<String, int>> measure(Iterable<String> hosts) async {
    final targets = hosts.toSet().toList();
    final results = <String, int>{};
    const concurrency = 6;
    for (var i = 0; i < targets.length; i += concurrency) {
      final batch = targets.skip(i).take(concurrency).toList();
      await Future.wait(batch.map((host) async {
        results[host] = await _measureOne(host);
      }));
    }
    return results;
  }

  static Future<int> _measureOne(String host) async {
    final (hostname, port) = _parseHostPort(host);
    final watch = Stopwatch()..start();
    Socket? socket;
    try {
      socket = await Socket.connect(hostname, port, timeout: _timeout);
      watch.stop();
      return watch.elapsedMilliseconds;
    } catch (_) {
      return _unreachable;
    } finally {
      socket?.destroy();
    }
  }

  /// host 可能形如 `cdn.example.com:443`、裸域名（默认 443）或 IPv6 字面量
  static (String, int) _parseHostPort(String host) {
    final trimmed = host.trim();
    // [ipv6]:port
    if (trimmed.contains(']:')) {
      final idx = trimmed.indexOf(']:');
      final port = int.tryParse(trimmed.substring(idx + 2));
      if (port != null && port > 0 && port <= 65535) {
        return (trimmed.substring(0, idx + 1), port);
      }
      return (trimmed, 443);
    }
    // host:port（单个冒号）
    if (!trimmed.contains(':')) return (trimmed, 443);
    final idx = trimmed.indexOf(':');
    final rest = trimmed.substring(idx + 1);
    if (!rest.contains(':')) {
      final port = int.tryParse(rest);
      if (port != null && port > 0 && port <= 65535) {
        return (trimmed.substring(0, idx), port);
      }
    }
    // IPv6 字面量（多个冒号、无端口）
    return (trimmed, 443);
  }
}
