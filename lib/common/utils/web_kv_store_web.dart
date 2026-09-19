import 'package:web/web.dart' as web;

/// Web 实现：localStorage 键值存取。
Future<String?> webKvGet(String key) async {
  return web.window.localStorage.getItem(key);
}

Future<void> webKvSet(String key, String value) async {
  web.window.localStorage.setItem(key, value);
}
