import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';

mixin class SiteAccount {
  /// 是否登录
  var isLogin = false.obs;

  /// cookie 内容
  var userCookie = "".obs;

  /// 用户ID
  var uid = 0;

  /// 用户名
  var userName = "未登录".obs;

  /// 是否支持登录
  bool isSupportLogin() => false;

  /// 是否支持Web登录
  bool isSupportWebLogin() => true;

  /// 是否支持二维码登录
  bool isSupportQrLogin() => true;

  /// 是否支持Cookie登录
  bool isSupportCookieLogin() => true;

  /// 退出登录
  Future<void> logout(Site site) async {
    userCookie.value = "";
    uid = 0;
    userName.value = "未登录";
    isLogin.value = false;
    SettingsService settings = Get.find<SettingsService>();
    var siteCookies = settings.siteCookies.value;
    siteCookies.remove(site.id);
    CookieManager cookieManager = CookieManager.instance();
    await cookieManager.deleteAllCookies();
  }

  /// 加载用户信息
  Future<bool> loadUserInfo(Site site, String cookie) async {
    userCookie.value = "";
    uid = 0;
    userName.value = "未登录";
    isLogin.value = false;
    return false;
  }

  /// web登录请求
  URLRequest webLoginURLRequest()=> URLRequest(headers: {}, url: WebUri(""),);

  /// web登录处理，判断是否成功
  bool webLoginHandle(WebUri? uri)=> false;

  /// 加载二维码
  Future<QRBean> loadQRCode() async{
    return QRBean();
  }

  ///  获取二维码扫描状态
  Future<QRBean> pollQRStatus(QRBean qrBean) async{
    return qrBean;
  }

}

/// 二维码状态
enum QRStatus {
  /// 加载中
  loading,
  /// 没有使用
  unscanned,
  /// 扫描中
  scanned,
  /// 过期
  expired,
  /// 失败
  failed,
  /// 成功
  success,
}

/// 二维码实体
class QRBean{
  /// 二维码状态
  QRStatus qrStatus=QRStatus.loading;
  /// 二维码链接
  var qrcodeUrl = "";
  /// 二维码验证秘钥
  var qrcodeKey = "";
}
