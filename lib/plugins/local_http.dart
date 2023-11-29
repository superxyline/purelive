import 'dart:io';

class LocalHttpServer {
  static late HttpServer httpServer;
  Uri get serverUrl => Uri.parse('http://localhost:${httpServer.port}');
  void startServer() async {
    httpServer = await HttpServer.bind(InternetAddress.anyIPv4, 8081, shared: true);
    httpServer.listen((request) {
      final path = request.uri.path;
      final response = request.response;
      if (path == '/error') {
        const content = 'error';
        response
          ..statusCode = 400
          ..contentLength = content.length
          ..write(content);
        response.close();
        return;
      }
    });
  }
}
