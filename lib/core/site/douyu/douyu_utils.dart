import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/core/common/core_log.dart';
import 'package:pure_live/common/services/settings/cookie_value.dart';
import 'package:pure_live/common/services/settings_service.dart';

/// 斗鱼登录态，供账号页展示与续期判定使用。
enum DouyuSessionState {
  /// 完全没填 cookie
  none,

  /// 有 cookie 但没有会话令牌（只有设备号，等于未登录）
  guest,

  /// 登录有效
  valid,

  /// 已过期，但手上还有 LTP0 + dy_did，可以静默续期
  expiredRefreshable,

  /// 已过期且无法续期，只能重新登录
  expired,
}

class DouyuUtils {
  static const String defaultDeviceId = '10000000000000000000000000001501';
  static const String _apiDouyuEnc = 'https://www.douyu.com/wgapi/livenc/liveweb/websec/getEncryption';
  static const int _expirySafetySeconds = 30;
  static const int _maximumCacheAgeSeconds = 5 * 60;
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/128.0.0.0 Safari/537.36';

  static Map<String, dynamic> _encKey = <String, dynamic>{};
  static Future<void>? _encKeyRefresh;
  static int? _encKeyFetchedAtSeconds;
  static final String _sessionDeviceId = generateDeviceId();

  static String get deviceId => _sessionDeviceId;

  static int _nowSeconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  /// Validates the server encryption descriptor using second-based Unix time.
  static bool isEncryptionKeyUsable(
    Map<String, dynamic> value, {
    required int nowSeconds,
    int safetySeconds = _expirySafetySeconds,
  }) {
    final expiresAt = _asInt(value['expire_at']);
    final encTime = _asInt(value['enc_time']);
    return expiresAt != null &&
        expiresAt > nowSeconds + safetySeconds &&
        encTime != null &&
        encTime > 0 &&
        encTime <= 16 &&
        _nonEmpty(value['key']) &&
        _nonEmpty(value['rand_str']) &&
        _nonEmpty(value['enc_data']);
  }

  static bool _isCachedEncryptionKeyUsable(int nowSeconds) {
    final fetchedAt = _encKeyFetchedAtSeconds;
    return fetchedAt != null &&
        _encKeyDeviceId == effectiveDeviceId() &&
        nowSeconds - fetchedAt < _maximumCacheAgeSeconds &&
        isEncryptionKeyUsable(_encKey, nowSeconds: nowSeconds);
  }

  static Future<void> _encKeyUpdate({bool forceRefresh = false}) async {
    final nowSeconds = _nowSeconds();
    if (!forceRefresh && _isCachedEncryptionKeyUsable(nowSeconds)) return;

    final activeRefresh = _encKeyRefresh;
    if (activeRefresh != null) {
      await activeRefresh;
      if (_isCachedEncryptionKeyUsable(_nowSeconds())) return;
    }

    final refresh = _fetchEncryptionKey();
    _encKeyRefresh = refresh;
    try {
      await refresh;
    } finally {
      if (identical(_encKeyRefresh, refresh)) _encKeyRefresh = null;
    }
  }

  static Future<void> _fetchEncryptionKey() async {
    // 加密描述符是按设备签发的：这里、签名 query、请求 Cookie 三处必须同一个
    // did，否则斗鱼边车会直接 403（且不带 API 错误码，很难排查）。
    final did = effectiveDeviceId();
    final response = await HttpClient.instance.getJson(
      _apiDouyuEnc,
      queryParameters: {'did': did},
      header: requestHeaders(),
    );
    final rawData = response is Map ? response['data'] : null;
    if (rawData is! Map) {
      throw const FormatException('Douyu encryption response is missing data');
    }
    final data = Map<String, dynamic>.from(rawData);
    if (!isEncryptionKeyUsable(data, nowSeconds: _nowSeconds())) {
      throw const FormatException('Douyu encryption descriptor is incomplete or expired');
    }
    _encKey = data;
    _encKeyFetchedAtSeconds = _nowSeconds();
    _encKeyDeviceId = did;
  }

  /// Creates the browser DID used by a single app process.
  static String generateDeviceId({Random? random}) {
    final source = random ?? Random.secure();
    return List<String>.generate(32, (_) => source.nextInt(16).toRadixString(16)).join();
  }

  static Map<String, String> requestHeaders([String roomId = '']) {
    final referer = roomId.isEmpty ? 'https://www.douyu.com/' : 'https://www.douyu.com/$roomId';
    return <String, String>{
      'accept': 'application/json, text/plain, */*',
      'accept-language': 'zh-CN,zh;q=0.9,en;q=0.7',
      'origin': 'https://www.douyu.com',
      'referer': referer,
      'user-agent': userAgent,
      'cookie': cookieHeader(),
    };
  }

  /// Keep the signer DID consistent with its request Cookie, while appending
  /// optional account session fields to Douyu request/playback headers.
  static String cookieHeader({String? accountCookie}) {
    final stored = accountCookie ?? _configuredAccountCookie();
    final normalized = normalizeAccountCookie(stored).replaceFirst(RegExp(r'^Cookie:\s*', caseSensitive: false), '');
    // did 与签名保持一致：账号 cookie 自带 dy_did 时沿用它，不覆盖
    final did = effectiveDeviceId(accountCookie: normalized);
    final fields = <String>['dy_did=$did', 'acf_did=$did'];
    for (final piece in normalized.split(';')) {
      final separator = piece.indexOf('=');
      if (separator <= 0) continue;
      final name = piece.substring(0, separator).trim();
      if (!RegExp(r"^[A-Za-z0-9_!#$%&'*+.^`|~-]+$").hasMatch(name)) continue;
      if (name.toLowerCase() == 'dy_did' || name.toLowerCase() == 'acf_did') continue;
      // LTP0 属于 passport.douyu.com（续期密钥，不是会话字段），
      // 发给取流接口既没必要，也容易让边车直接 403。
      if (name.toLowerCase() == longTermTokenName.toLowerCase()) continue;
      fields.add('$name=${piece.substring(separator + 1).trim()}');
    }
    return fields.join('; ');
  }

  static String _configuredAccountCookie() {
    try {
      return SettingsService.to.cookieManager.douyuCookie.value;
    } catch (_) {
      return '';
    }
  }

  static Map<String, String> playbackHeaders(String roomId) => <String, String>{
    'origin': 'https://www.douyu.com',
    'referer': 'https://www.douyu.com/$roomId',
    'user-agent': userAgent,
    'cookie': cookieHeader(),
  };

  /// Builds the form body from an already validated encryption descriptor.
  /// Exposed as a deterministic unit-test seam for the platform signing path.
  static String buildSignedData({
    required Map<String, dynamic> encryptionKey,
    required String roomId,
    required int timestampSeconds,
    int rate = -1,
    String cdn = '',
    String deviceId = defaultDeviceId,
  }) {
    if (!isEncryptionKeyUsable(encryptionKey, nowSeconds: timestampSeconds, safetySeconds: 0)) {
      throw const FormatException('Douyu encryption descriptor is incomplete or expired');
    }
    final key = encryptionKey['key'].toString();
    final randStr = encryptionKey['rand_str'].toString();
    final encTime = _asInt(encryptionKey['enc_time'])!;
    final salt = _asInt(encryptionKey['is_special']) == 1 ? '' : '$roomId$timestampSeconds';

    var secret = randStr;
    for (var index = 0; index < encTime; index++) {
      secret = md5.convert(utf8.encode('$secret$key')).toString();
    }
    final auth = md5.convert(utf8.encode('$secret$key$salt')).toString();
    return Uri(
      queryParameters: <String, String>{
        'enc_data': encryptionKey['enc_data'].toString(),
        'tt': timestampSeconds.toString(),
        'did': deviceId,
        'auth': auth,
        'cdn': cdn,
        'rate': rate.toString(),
        'hevc': '0',
        'fa': '0',
        'ive': '0',
        'ver': 'Douyu_new',
        'iar': '0',
      },
    ).query;
  }

  static Future<String> sign(String roomId, {int rate = -1, String cdn = '', bool forceRefresh = false}) async {
    await _encKeyUpdate(forceRefresh: forceRefresh);
    return buildSignedData(
      encryptionKey: _encKey,
      roomId: roomId,
      timestampSeconds: _nowSeconds(),
      rate: rate,
      cdn: cdn,
      deviceId: effectiveDeviceId(),
    );
  }

  // ---------------------------------------------------------------------------
  // 账号会话：登录态判定 / 设备号对齐 / LTP0 自动续期
  // （移植自上游 pure_live 的 DouyuUtils，适配本项目的设置存储）
  // ---------------------------------------------------------------------------

  /// 网页版 `dy_auth` 的有效期。斗鱼发 7 天，这个值存在浏览器 Set-Cookie 属性里，
  /// 粘贴出来的字符串读不到，只能靠「保存时间 + 7 天」推算。
  static const Duration webCookieLifetime = Duration(days: 7);

  /// 提前一天续期：多一次请求，换播放中不会撞到过期。
  static const Duration refreshMargin = Duration(days: 1);

  static const String jwtTokenName = 'acf_jwt_token';
  static const String authTokenName = 'acf_auth';
  static const String webAuthTokenName = 'dy_auth';
  static const String longTermTokenName = 'LTP0';
  static const String deviceIdName = 'dy_did';

  /// 续期用的 passport 接口：只要 LTP0 + dy_did 就能换新 token，无需重新扫码。
  static const String _apiDouyuPassport = 'https://passport.douyu.com/lapi/passport/iframe/safeAuth';

  /// `Set-Cookie` 里长得和字段一样的属性，写回 Cookie 头会污染请求。
  static const Set<String> _setCookieAttributes = <String>{
    'path',
    'domain',
    'expires',
    'max-age',
    'samesite',
    'secure',
    'httponly',
  };

  /// 加密描述符是按设备签发的，切换账号（dy_did 变了）必须重新取。
  static String? _encKeyDeviceId;

  static List<({String name, String value})> parseCookieFields(String cookie) {
    final fields = <({String name, String value})>[];
    for (final piece in cookie.split(';')) {
      final separator = piece.indexOf('=');
      if (separator <= 0) continue;
      final name = piece.substring(0, separator).trim();
      if (name.isEmpty) continue;
      fields.add((name: name, value: piece.substring(separator + 1).trim()));
    }
    return fields;
  }

  /// 取某个 cookie 字段的值（名字不区分大小写）。
  static String? cookieField(String cookie, String name) {
    final wanted = name.toLowerCase();
    for (final field in parseCookieFields(cookie)) {
      if (field.name.toLowerCase() == wanted) return field.value;
    }
    return null;
  }

  /// 会话令牌：H5 版是 `acf_jwt_token`/`acf_auth`，网页版是 `dy_auth`。
  /// 只读 JWT 会把手动粘贴的网页登录误判成未登录。
  static String? sessionToken(String cookie) =>
      cookieField(cookie, jwtTokenName) ?? cookieField(cookie, authTokenName) ?? cookieField(cookie, webAuthTokenName);

  /// 解 JWT payload；不是 JWT 时返回 null（手工粘贴的 cookie 不该让请求崩）。
  static Map<String, dynamic>? decodeJwtPayload(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      switch (payload.length % 4) {
        case 2:
          payload += '==';
        case 3:
          payload += '=';
      }
      final decoded = jsonDecode(utf8.decode(base64.decode(payload)));
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  /// 会话到期时间：JWT 的 exp 优先；网页版 dy_auth 读不到，用保存时间 + 7 天。
  static DateTime? sessionExpiry(String cookie, {DateTime? now, DateTime? savedAt}) {
    final token = sessionToken(cookie);
    if (token == null || token.isEmpty) return null;

    final expiresAt = _asInt(decodeJwtPayload(token)?['exp']);
    if (expiresAt != null && expiresAt > 0) {
      return DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000);
    }
    return savedAt?.add(webCookieLifetime);
  }

  /// cookie 是否已经不能当登录用（没有令牌一律算过期：那就是游客请求）。
  static bool isSessionExpired(String cookie, {DateTime? now, DateTime? savedAt}) {
    if (sessionToken(cookie) == null) return true;
    final expiry = sessionExpiry(cookie, now: now, savedAt: savedAt ?? storedSessionSavedAt());
    return expiry != null && !expiry.isAfter(now ?? DateTime.now());
  }

  /// 是否已经到了该续期的时间点（到期前 [refreshMargin] 内）。
  static bool shouldRefreshSession(String cookie, {DateTime? now, DateTime? savedAt}) {
    if (sessionToken(cookie) == null) return true;
    final expiry = sessionExpiry(cookie, now: now, savedAt: savedAt ?? storedSessionSavedAt());
    if (expiry == null) return false;
    return !(now ?? DateTime.now()).isBefore(expiry.subtract(refreshMargin));
  }

  /// 续期需要的两样东西：LTP0 与登录设备号。
  /// cookie 里带、账号页单独填、上次存下来的，三者任一都算。
  static ({String? longTerm, String? did}) refreshCredentials(String cookie, {String? longTerm, String? did}) {
    final resolvedLongTerm = _nonBlank(longTerm) ?? _nonBlank(cookieField(cookie, longTermTokenName)) ?? _storedLtp0();
    // 这里不能回退到进程随机 did：续期必须使用登录签发时的设备号，
    // 现编一个只会让 passport 直接拒绝。
    final resolvedDid = _nonBlank(did) ?? _nonBlank(cookieField(cookie, deviceIdName)) ?? _storedDid();
    return (longTerm: resolvedLongTerm, did: resolvedDid);
  }

  static bool canRefreshSession(String cookie, {String? longTerm, String? did}) {
    final credentials = refreshCredentials(cookie, longTerm: longTerm, did: did);
    return credentials.longTerm != null && credentials.did != null;
  }

  /// 账号页展示用的登录态。
  static DouyuSessionState sessionState(String cookie, {DateTime? now, DateTime? savedAt}) {
    final normalized = normalizeAccountCookie(cookie);
    if (normalized.isEmpty) return DouyuSessionState.none;

    final at = now ?? DateTime.now();
    final expiry = sessionExpiry(normalized, now: at, savedAt: savedAt ?? storedSessionSavedAt());
    // 读不到 expiry 的令牌（网页版 dy_auth）是「有效但不知道何时结束」，
    // 不能当成游客，也不能当成过期。
    if (sessionToken(normalized) == null) return DouyuSessionState.guest;
    if (expiry == null || expiry.isAfter(at)) return DouyuSessionState.valid;
    return canRefreshSession(normalized) ? DouyuSessionState.expiredRefreshable : DouyuSessionState.expired;
  }

  /// 签名与 Cookie 头必须用同一个设备号。
  ///
  /// 账号 cookie 自带 `dy_did` 时优先用它——用别的设备号签名，斗鱼会把有效登录
  /// 当成游客（表现就是「登录了却只有蓝光4M」）。进程随机 did 只作兜底。
  static String effectiveDeviceId({String? accountCookie}) {
    final stored = accountCookie ?? _configuredAccountCookie();
    final did = cookieField(stored, deviceIdName);
    return did != null && did.isNotEmpty ? did : deviceId;
  }

  /// 把响应里的 `Set-Cookie` 合并进 cookie，保留响应没提到的字段。
  ///
  /// 直接拿响应字段覆盖整条 cookie 会丢掉 LTP0，续期就只能成功一次。
  static String mergeSetCookieLines(String cookie, Iterable<String> setCookieLines) {
    final fields = <String, String>{for (final field in parseCookieFields(cookie)) field.name: field.value};

    for (final line in setCookieLines) {
      final pair = line.split(';').first.trim();
      final separator = pair.indexOf('=');
      if (separator <= 0) continue;
      final name = pair.substring(0, separator).trim();
      final value = pair.substring(separator + 1).trim();
      if (name.isEmpty) continue;
      if (_setCookieAttributes.contains(name.toLowerCase())) continue;
      if (value.isEmpty) {
        // 空值＝斗鱼在清这个字段，保留旧值等于复活一个已被吊销的令牌
        fields.remove(name);
        continue;
      }
      fields[name] = value;
    }

    return fields.entries.map((entry) => '${entry.key}=${entry.value}').join('; ');
  }

  /// 用 LTP0 续期，返回续期后的 cookie；无法续期/服务端没给新 cookie 时返回 null。
  static Future<String?> refreshSession({
    String? accountCookie,
    DateTime? savedAt,
    bool force = false,
    String? longTerm,
    String? did,
  }) async {
    final stored = normalizeAccountCookie(accountCookie ?? _configuredAccountCookie());
    if (stored.isEmpty) return null;

    final credentials = refreshCredentials(stored, longTerm: longTerm, did: did);
    if (credentials.longTerm == null || credentials.did == null) return null;
    if (!force && !shouldRefreshSession(stored, savedAt: savedAt)) return null;

    final resolvedDid = credentials.did!;
    final resolvedLongTerm = credentials.longTerm!;
    final milliseconds = DateTime.now().millisecondsSinceEpoch.toString();
    final url = Uri.parse(_apiDouyuPassport).replace(
      queryParameters: <String, String>{
        'client_id': '1',
        't': milliseconds,
        '_': milliseconds,
        'callback': 'axiosJsonpCallback',
      },
    );

    // 这个请求就是 LTP0 存在的意义：没有它 passport 只会当游客处理。
    final setCookies = await _fetchSetCookies(url, <String, String>{
      ...requestHeaders(),
      'cookie': '$deviceIdName=$resolvedDid;$longTermTokenName=$resolvedLongTerm',
    });

    // 没有任何 Set-Cookie = 服务端没续期。这里必须保持无操作：
    // 记录一个续期时间会让快死的 cookie 又「看起来新鲜」七天。
    if (setCookies.isEmpty) return null;

    final renewed = mergeSetCookieLines(stored, setCookies);
    if (renewed.isEmpty) return null;
    if (sessionToken(renewed) == null) return null;

    await _persistCookie(renewed, DateTime.now());
    return renewed;
  }

  /// 需要时静默续期。永不抛出：续期失败最多是退回游客请求，比播放直接失败好。
  static Future<void> ensureFreshSession({
    String? accountCookie,
    DateTime? savedAt,
    bool force = false,
    String? longTerm,
    String? did,
  }) async {
    try {
      final stored = normalizeAccountCookie(accountCookie ?? _configuredAccountCookie());
      if (stored.isEmpty || !canRefreshSession(stored, longTerm: longTerm, did: did)) return;
      // force 是失败路径：请求已经被当成游客了，比任何时间戳都更能说明问题
      if (!force && !shouldRefreshSession(stored, savedAt: savedAt)) return;
      await refreshSession(accountCookie: stored, savedAt: savedAt, force: force, longTerm: longTerm, did: did);
    } catch (error) {
      CoreLog.w('斗鱼登录续期失败: $error');
    }
  }

  static Future<List<String>> _fetchSetCookies(Uri url, Map<String, String> headers) async {
    final response = await HttpClient.instance.dio.get<dynamic>(
      url.toString(),
      options: Options(responseType: ResponseType.plain, headers: headers, validateStatus: (_) => true),
    );
    final raw = response.headers['set-cookie'];
    if (raw == null) return const <String>[];
    return List<String>.from(raw);
  }

  static Future<void> _persistCookie(String cookie, DateTime savedAt) async {
    try {
      final cookies = SettingsService.to.cookieManager;
      cookies.douyuCookie.value = cookie;
      // 记住保存时间，否则网页版的七天规则没有起点
      cookies.douyuCookieSavedAt.value = savedAt.millisecondsSinceEpoch ~/ 1000;
      // 续期后的令牌也推给 NAS（常连同步），避免两端登录态不一致
      cookies.notifyLoginChanged();
    } catch (_) {
      // 设置不可用（测试/无头环境）：续期结果仍返回给调用方，本次请求照样受益
    }
  }

  /// 记录 cookie 的保存时间（秒）；没记录过返回 null，界面显示「未知」而不是编一个。
  static DateTime? storedSessionSavedAt({int? savedAtSeconds}) {
    try {
      final seconds = savedAtSeconds ?? SettingsService.to.cookieManager.douyuCookieSavedAt.value;
      return seconds > 0 ? DateTime.fromMillisecondsSinceEpoch(seconds * 1000) : null;
    } catch (_) {
      return null;
    }
  }

  /// 账号昵称：登录 cookie 里直接带着（URL 编码），不需要额外请求。
  static String accountNick(String cookie) {
    final raw = cookieField(cookie, 'acf_nickname') ?? cookieField(cookie, 'acf_username') ?? '';
    if (raw.isEmpty) return '';
    try {
      return Uri.decodeComponent(raw);
    } catch (_) {
      return raw;
    }
  }

  static String? _nonBlank(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static String? _storedLtp0() {
    try {
      return _nonBlank(SettingsService.to.cookieManager.douyuLtp0.value);
    } catch (_) {
      return null;
    }
  }

  static String? _storedDid() {
    try {
      return _nonBlank(SettingsService.to.cookieManager.douyuDid.value);
    } catch (_) {
      return null;
    }
  }

  static int? _asInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static bool _nonEmpty(dynamic value) => value?.toString().trim().isNotEmpty == true;
}
