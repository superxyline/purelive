import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce/hive.dart';

class HivePrefUtil {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const String _encryptionKeyName = 'hive_encryption_key_v1';

  static late Box _box;

  static Future<void> init() async {
    if (!Hive.isBoxOpen('app_settings')) {
      final key = await _getOrCreateEncryptionKey();
      _box = await Hive.openBox('app_settings', encryptionCipher: HiveAesCipher(key));
    } else {
      _box = Hive.box('app_settings');
    }
  }

  /// 从系统安全存储获取（或首次生成并保存）Hive 加密密钥。
  static Future<List<int>> _getOrCreateEncryptionKey() async {
    final String? stored = await _secureStorage.read(key: _encryptionKeyName);
    if (stored != null && stored.isNotEmpty) {
      return base64Url.decode(stored);
    }

    final Random random = Random.secure();
    final List<int> key = List<int>.generate(32, (_) => random.nextInt(256));
    await _secureStorage.write(key: _encryptionKeyName, value: base64Url.encode(key));
    return key;
  }

  static dynamic getAnyPref(String key) {
    return _box.get(key);
  }

  static Future<bool> setAnyPref(String key, dynamic value) async {
    await _box.put(key, value);
    return true;
  }

  static bool? getBool(String key) {
    final value = _box.get(key);
    return value is bool ? value : null;
  }

  static Future<bool> setBool(String key, bool value) {
    _box.put(key, value);
    return Future.value(true);
  }

  static int? getInt(String key) {
    final value = _box.get(key);
    return value is int ? value : null;
  }

  static Future<bool> setInt(String key, int value) {
    _box.put(key, value);
    return Future.value(true);
  }

  static String? getString(String key) {
    final value = _box.get(key);
    return value is String ? value : null;
  }

  static Future<bool> setString(String key, String value) {
    _box.put(key, value);
    return Future.value(true);
  }

  static double? getDouble(String key) {
    final value = _box.get(key);
    return value is double ? value : null;
  }

  static Future<bool> setDouble(String key, double value) {
    _box.put(key, value);
    return Future.value(true);
  }

  static List<String>? getStringList(String key) {
    final value = _box.get(key);
    return value is List<String> ? value : null;
  }

  static Future<bool> setStringList(String key, List<String> value) {
    _box.put(key, value);
    return Future.value(true);
  }

  /// 删除指定 key
  static Future<bool> remove(String key) async {
    await _box.delete(key);
    return true;
  }

  /// 是否存在 key
  static bool containsKey(String key) {
    return _box.containsKey(key);
  }

  /// 清空全部
  static Future<bool> clear() async {
    await _box.clear();
    return true;
  }
}
