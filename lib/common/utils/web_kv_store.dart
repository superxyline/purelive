import 'web_kv_store_io.dart'
    if (dart.library.js_interop) 'web_kv_store_web.dart' as impl;

/// 轻量键值存取：Web 端映射到 localStorage。
///
/// 用途：Flutter Web 的 [FlutterSecureStorage] 实现依赖 WebCrypto
/// （crypto.subtle），只在 HTTPS/localhost 安全上下文可用；局域网 IP 直连
/// （http://192.168.x.x）下不可用，会导致启动崩溃。因此 Web 端将 Hive
/// 加密密钥降级存 localStorage——同一部署者自用的 NAS 场景可接受，
/// 公网部署请务必走 HTTPS。
Future<String?> webKvGet(String key) => impl.webKvGet(key);

Future<void> webKvSet(String key, String value) => impl.webKvSet(key, value);
