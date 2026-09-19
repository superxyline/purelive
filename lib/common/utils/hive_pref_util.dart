import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/global/platform_utils.dart';
import 'package:pure_live/common/utils/web_kv_store.dart';

class HivePrefUtil {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const String _encryptionKeyName = 'hive_encryption_key_v1';

  static late Box _box;

  static Future<void> init() async {
    if (Hive.isBoxOpen('app_settings')) {
      _box = Hive.box('app_settings');
      return;
    }
    final key = await _getOrCreateEncryptionKey();
    Box box;
    try {
      box = await Hive.openBox('app_settings',
          encryptionCipher: HiveAesCipher(key));
      // 探测读取：强制校验磁盘帧能否用该密钥解密。若磁盘上仍是旧版本地
      // 明文库（未加密），此处会在读取数据帧时抛出解密错误，从而触发
      // 【明文 → 加密】兼容迁移，避免升级后丢失用户设置。
      box.toMap();
    } catch (_) {
      box = await _migratePlaintextToEncrypted(key);
    }
    _box = box;
  }

  /// 从系统安全存储获取（或首次生成并保存）Hive 加密密钥。
  /// 密钥由 Android Keystore / iOS Keychain 等平台安全存储持久化，
  /// 避免把加密密钥与密文存放在同一明文文件中。
  ///
  /// Web 端例外：FlutterSecureStorage 的 Web 实现依赖 crypto.subtle，
  /// 在局域网 http://IP 直连（非安全上下文）下不可用，会直接导致启动崩溃。
  /// 因此 Web 端把密钥降级存 localStorage（随机生成逻辑不变）。
  static Future<List<int>> _getOrCreateEncryptionKey() async {
    if (PlatformUtils.isWeb) {
      final stored = await webKvGet(_encryptionKeyName);
      if (stored != null && stored.isNotEmpty) {
        return base64Url.decode(stored);
      }
      final random = Random.secure();
      final key = List<int>.generate(32, (_) => random.nextInt(256));
      await webKvSet(_encryptionKeyName, base64Url.encode(key));
      return key;
    }

    final String? stored = await _secureStorage.read(key: _encryptionKeyName);
    if (stored != null && stored.isNotEmpty) {
      return base64Url.decode(stored);
    }

    final Random random = Random.secure();
    final List<int> key = List<int>.generate(32, (_) => random.nextInt(256));
    await _secureStorage.write(key: _encryptionKeyName, value: base64Url.encode(key));
    return key;
  }

  /// 【明文 → 加密】兼容迁移：读取旧版未加密的 app_settings 数据，
  /// 删除旧明文文件，再以新密钥重新打开加密库并写回全部数据。
  static Future<Box> _migratePlaintextToEncrypted(List<int> key) async {
    // 1. 以明文方式打开旧库并读取全部数据（type 注册表开放，因此可存任意值）。
    final plain = await Hive.openBox('app_settings');
    final Map<dynamic, dynamic> data = Map<dynamic, dynamic>.from(plain.toMap());
    // 2. 关闭并删除旧明文库文件，避免与新加密库的 .hive 文件冲突。
    await Hive.deleteBoxFromDisk('app_settings');
    // 3. 以加密方式重建空库。
    final Box box = await Hive.openBox('app_settings',
        encryptionCipher: HiveAesCipher(key));
    if (data.isNotEmpty) {
      await box.putAll(data);
      await box.flush();
    }
    return box;
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

  static Future<bool> setBool(String key, bool value) async {
    await _box.put(key, value);
    return true;
  }

  static int? getInt(String key) {
    final value = _box.get(key);
    return value is int ? value : null;
  }

  static Future<bool> setInt(String key, int value) async {
    await _box.put(key, value);
    return true;
  }

  static String? getString(String key) {
    final value = _box.get(key);
    return value is String ? value : null;
  }

  static Future<bool> setString(String key, String value) async {
    await _box.put(key, value);
    return true;
  }

  static double? getDouble(String key) {
    final value = _box.get(key);
    return value is double ? value : null;
  }

  static Future<bool> setDouble(String key, double value) async {
    await _box.put(key, value);
    return true;
  }

  static List<String>? getStringList(String key) {
    final value = _box.get(key);
    return value is List<String> ? value : null;
  }

  static Future<bool> setStringList(String key, List<String> value) async {
    await _box.put(key, value);
    return true;
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

  /// Waits until all queued settings writes reach disk. Desktop shutdown uses
  /// this before destroying the native window so rapid final changes survive
  /// an application update or immediate exit.
  static Future<void> flush() => _box.flush();
}
