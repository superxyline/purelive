import 'package:webdav_client_plus/webdav_client_plus.dart';

class WebDAVService {
  final String url;
  final String username;
  final String password;

  late final WebdavClient _client;

  WebdavClient get client => _client;

  WebDAVService({required this.url, required this.username, required this.password}) {
    _client = WebdavClient(
      url: url.trim(),
      auth: BasicAuth(user: username, pwd: password),
    );
  }

  Future<List<WebdavFile>> readDirectory(String path) async {
    try {
      final response = await _client.readDir(path);
      if (response.isEmpty) {
        throw Exception('Empty response from server');
      }
      return response;
    } catch (e) {
      rethrow;
    }
  }
}
