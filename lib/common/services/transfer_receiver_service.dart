import 'dart:io';
import 'dart:convert';

/// 跨端传输接收服务：在局域网内启动临时 HTTP 服务，
/// 接收发送方扫码后推送的关注与登录数据（POST /api/importData）。
class TransferReceiverService {
  HttpServer? _server;

  int get port => _server?.port ?? 0;
  bool get isRunning => _server != null;

  /// 启动服务，[onData] 收到数据后执行（返回是否成功）。
  Future<int> start(Future<bool> Function(Map<String, dynamic> data) onData) async {
    await stop();
    _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    _server!.listen((request) async {
      try {
        if (request.method == 'POST' && request.uri.path == '/api/importData') {
          final body = await utf8.decoder.bind(request).join();
          final decoded = jsonDecode(body);
          final ok = decoded is Map<String, dynamic> ? await onData(decoded) : false;
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'data': ok}));
        } else if (request.method == 'GET' && request.uri.path == '/health') {
          request.response.statusCode = 200;
          request.response.write('ok');
        } else {
          request.response.statusCode = 404;
        }
      } catch (_) {
        request.response.statusCode = 500;
        request.response.write(jsonEncode({'data': false}));
      } finally {
        await request.response.close();
      }
    });
    return port;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }
}
