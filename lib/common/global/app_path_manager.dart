import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';


/// 应用数据目录管理。
///
/// Android-only 精简版：数据统一存放在 {Documents}/PURE_LIVE 下，
/// 不再包含 Windows 便携版/注册表/旧版数据迁移逻辑。
class AppPathManager {
  static final AppPathManager _instance = AppPathManager._internal();
  factory AppPathManager() => _instance;
  AppPathManager._internal();

  static const String softNameDir = 'PURE_LIVE';
  static const String dirIptvCache = 'IPTV_CACHE';
  static const String iptvTable = 'pure_live_tv';
  static const String dirDownload = 'DOWNLOADS';
  static const String dirLogs = 'LOGS';
  static const String dirHiveDB = 'HIVE_DB';
  static const String dirImageCache = 'IMAGE_CACHE';
  static const String dirRecords = 'RECORDS';
  static const String dirEmojiCache = 'EMOJI_CACHE';
  static const String dirMigrationBackup = 'MIGRATION_BACKUP';
  static const String fontCacheDir = 'fontsDir';
  static const String iptvCategoryFile = 'categories.json';
  static const String iptvHotFile = 'hot.m3u';
  static const String iptvHotRemoteFile = 'https://raw.githubusercontent.com/YueChan/Live/main/GNTV.m3u';

  String? _basePath;

  /// Android 上始终为空：无 Windows 旧版 Hive 数据需要迁移。
  List<String> get legacyHiveFiles => const [];

  Future<void> initialize({String instanceId = ''}) async {
    final sanitizedInstanceId = instanceId.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '');
    final appDir = await getApplicationDocumentsDirectory();
    var rootPath = p.join(appDir.path, softNameDir);
    if (sanitizedInstanceId.isNotEmpty) {
      rootPath = p.join(rootPath, sanitizedInstanceId);
    }
    await Directory(rootPath).create(recursive: true);
    _basePath = rootPath;
  }

  Future<Directory> getDir(String segment) async {
    final targetPath = p.join(basePath, segment);
    final directory = Directory(targetPath);
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<Directory> get iptvCacheDir => getDir(dirIptvCache);
  Future<Directory> get downloadDir => getDir(dirDownload);
  Future<Directory> get logsDir => getDir(dirLogs);
  Future<Directory> get hiveDbDir => getDir(dirHiveDB);
  Future<Directory> get imageCacheDir => getDir(dirImageCache);
  Future<Directory> get recordsDir => getDir(dirRecords);
  Future<Directory> get emojiCacheDir => getDir(dirEmojiCache);
  Future<Directory> get migrationWorkingDir => getDir(p.join(dirMigrationBackup, 'working'));

  String get basePath => _basePath ?? (throw StateError('AppPathManager 尚未初始化'));

  Future<String> getFontFamilyFolderPath(String id) async {
    final downloadDir = await getDir(dirDownload);
    return p.join(downloadDir.path, fontCacheDir, id);
  }
}
