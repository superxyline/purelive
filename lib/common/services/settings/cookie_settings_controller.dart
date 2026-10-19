import 'package:pure_live/get/get.dart';
import 'package:pure_live/common/services/utils/hive_rx.dart';
import 'package:pure_live/plugins/event_bus.dart';
import 'package:pure_live/common/services/settings/bilibili_account_service.dart';

class CookieSettingsController extends GetxController {
  final RxString bilibiliCookie = hiveString('bilibiliCookie', '');
  final RxInt bilibiliUid = hiveInt('bilibiliUid', 0);
  final RxString huyaCookie = hiveString('huyaCookie', '');
  final RxString douyinCookie = hiveString('douyinCookie', '');
  final RxString douyuCookie = hiveString('douyuCookie', '');
  /// 斗鱼登录续期用的长期密钥（passport.douyu.com 的 LTP0）。
  final RxString douyuLtp0 = hiveString('douyuLtp0', '');
  /// 登录所属设备号（与 cookie 里的 dy_did 一致；续期与签名都用它）。
  final RxString douyuDid = hiveString('douyuDid', '');
  /// cookie 保存时间（秒）。网页版 dy_auth 读不出过期时间，靠它 + 7 天规则推算。
  final RxInt douyuCookieSavedAt = hiveInt('douyuCookieSavedAt', 0);
  final RxString kuaishouCookie = hiveString('kuaishouCookie', '');
  void clearAllCookies() {
    bilibiliCookie.v = '';
    huyaCookie.v = '';
    douyinCookie.v = '';
    douyuCookie.v = '';
    douyuLtp0.v = '';
    douyuDid.v = '';
    douyuCookieSavedAt.v = 0;
    kuaishouCookie.v = '';
    bilibiliUid.v = 0;
  }

  /// 登录态变更后广播一次：NAS 同步控制器会补推一次（关注列表没变也要推，
  /// 否则 App 重新登录后 NAS 端拿不到新 cookie）。
  void notifyLoginChanged() {
    try {
      EventBus.instance.emit('login_state_changed', null);
    } catch (_) {
      // 事件总线不可用时静默，不影响登录本身
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'bilibiliCookie': bilibiliCookie.v,
      'huyaCookie': huyaCookie.v,
      'douyinCookie': douyinCookie.v,
      'douyuCookie': douyuCookie.v,
      'douyuLtp0': douyuLtp0.v,
      'douyuDid': douyuDid.v,
      'douyuCookieSavedAt': douyuCookieSavedAt.v,
      'kuaishouCookie': kuaishouCookie.v,
      'bilibiliUid': bilibiliUid.v,
    };
  }

  void fromJson(Map<String, dynamic> json) {
    bilibiliCookie.v = json['bilibiliCookie'] ?? '';
    huyaCookie.v = json['huyaCookie'] ?? '';
    douyinCookie.v = json['douyinCookie'] ?? '';
    douyuCookie.v = json['douyuCookie'] ?? '';
    douyuLtp0.v = json['douyuLtp0'] ?? '';
    douyuDid.v = json['douyuDid'] ?? '';
    douyuCookieSavedAt.v = (json['douyuCookieSavedAt'] as num?)?.toInt() ?? 0;
    kuaishouCookie.v = json['kuaishouCookie'] ?? '';
    bilibiliUid.v = json['bilibiliUid'] ?? 0;

    BiliBiliAccountService.instance.setCookie(bilibiliCookie.v);
    BiliBiliAccountService.instance.loadUserInfo();
  }

  static Map<String, dynamic> extractConfig(Map<String, dynamic>? rootConfig) {
    final cookie = rootConfig?['cookie'] as Map<String, dynamic>? ?? {};
    return {
      'bilibiliCookie': cookie['bilibiliCookie'] ?? '',
      'huyaCookie': cookie['huyaCookie'] ?? '',
      'douyinCookie': cookie['douyinCookie'] ?? '',
      'douyuCookie': cookie['douyuCookie'] ?? '',
      'douyuLtp0': cookie['douyuLtp0'] ?? '',
      'douyuDid': cookie['douyuDid'] ?? '',
      'douyuCookieSavedAt': cookie['douyuCookieSavedAt'] ?? 0,
      'kuaishouCookie': cookie['kuaishouCookie'] ?? '',
      'bilibiliUid': cookie['bilibiliUid'] ?? 0,
    };
  }

  static Map<String, dynamic> mergeConfig(Map<String, dynamic> rootConfig, Map<String, dynamic> updateFields) {
    final cookie = Map<String, dynamic>.from(rootConfig['cookie'] ?? {});
    updateFields.forEach((k, v) => cookie[k] = v);
    rootConfig['cookie'] = cookie;
    return rootConfig;
  }
}
