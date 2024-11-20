import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:pure_live/plugins/file_util.dart';

class CustomCache {
  static CustomCache get instance {
    return CustomCache();
  }

  final String cacheDir;

  CustomCache({this.cacheDir = 'cache_file'});

  Future<void> setCache(String key, dynamic value) async {
    final file = await _getFile(key);
    final json = jsonEncode(value);
    await file.writeAsString(json);
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
    var dir = '${baseDir.path}/$cacheDir';
    await Directory(dir).create(recursive: true);
    return File('$dir/$key');
  }

  /// 缓存目录大小
  Future<String> getCacheDirectorySize({String partPath = ""}) async {
    var baseDir = await getTemporaryDirectory();
    if (partPath.isNotEmpty) {
      baseDir = Directory("${baseDir.path}/$partPath");
    }
    // CoreLog.d("$partPath ${baseDir.path}");
    var size = await FileUtil.getTotalSizeOfFilesInDir(baseDir);
    return FileUtil.formatSize(size);
  }

  Future<Null> deleteCacheDirectory({var partPath = ""}) async {
    var baseDir = await getTemporaryDirectory();
    if (partPath.isNotEmpty) {
      baseDir = Directory("${baseDir.path}/$partPath");
    }
    return FileUtil.deleteDirectory(baseDir);
  }

  /// 图片缓存目录大小
  Future<String> getImageCacheDirectorySize() async {
    return getCacheDirectorySize(partPath: "cacheimage");
  }

  Future<Null> deleteImageCacheDirectory() {
    return deleteCacheDirectory(partPath: "cacheimage");
  }

  /// 分区缓存目录大小
  Future<String> getAreaCacheDirectorySize() async {
    return getCacheDirectorySize(partPath: "cache_file");
  }

  Future<Null> deleteAreaCacheDirectory() {
    return deleteCacheDirectory(partPath: "cache_file");
  }
}
