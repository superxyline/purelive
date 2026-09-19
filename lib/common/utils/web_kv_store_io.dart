/// io 平台占位：web_kv_store 只在 Flutter Web 上被调用。
Future<String?> webKvGet(String key) async {
  throw UnsupportedError('webKvStore is only available on Flutter Web');
}

Future<void> webKvSet(String key, String value) async {
  throw UnsupportedError('webKvStore is only available on Flutter Web');
}
