import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class CustomCache {

  static CustomCache get instance {
    return CustomCache();
  }
  final String cacheDir;

  CustomCache({this.cacheDir = 'cache_file'});

  Future<void> setCache(String key, dynamic value) async {
    final file = await _getFile(key);
    final json = jsonEncode(value);
    file.writeAsString(json);
  }

  Future<bool> isExistCache<T>(String key) async {
    final file = await _getFile(key);
    return await file.exists();
  }

  Future<T?> getCache<T>(String key) async {
    final file = await _getFile(key);
    if (await file.exists()) {
      final json = await file.readAsString();
      return jsonDecode(json) as T;
    }
    return null;
  }

  Future<File> _getFile(String key) async {
    var baseDir = await getTemporaryDirectory();
    await Directory("${baseDir.path}/$cacheDir").create(recursive: true);
    return File('$cacheDir/$key');
  }
}