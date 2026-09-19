import 'dart:async';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/common/services/settings/bilibili_account_service.dart';

enum QRStatus { loading, unscanned, scanned, expired, failed }

class BiliBiliQRLoginController extends GetxController {
  @override
  void onInit() {
    loadQRCode();
    super.onInit();
  }

  Timer? timer;

  var qrcodeUrl = "".obs;
  var qrcodeKey = "";

  /// 二维码状态
  /// - [0] 加载中
  /// - [1] 未扫描
  /// - [2] 已扫描，待确认
  /// - [3] 二维码已经失效
  /// - [4] 登录失败
  Rx<QRStatus> qrStatus = QRStatus.loading.obs;

  void loadQRCode() async {
    try {
      qrStatus.value = QRStatus.loading;

      // Web 端：passport 接口无法在浏览器直连，由 NAS 后端代理，
      // cookie 成功后自动托管在 NAS 上。
      final String generateUrl = PlatformUtils.isWeb
          ? "/api/auth/bilibili/qrcode"
          : "https://passport.bilibili.com/x/passport-login/web/qrcode/generate";
      var result = await HttpClient.instance.getJson(generateUrl);
      if (result["code"] != 0) {
        throw result["message"];
      }
      qrcodeKey = result["data"]["qrcode_key"];
      qrcodeUrl.value = result["data"]["url"];
      qrStatus.value = QRStatus.unscanned;
      startPoll();
    } catch (e) {
      ToastUtil.show(e.toString());
      qrStatus.value = QRStatus.failed;
    }
  }

  void startPoll() {
    timer = Timer.periodic(const Duration(seconds: 3), (timer) {
      pollQRStatus();
    });
  }

  void pollQRStatus() async {
    try {
      final String pollUrl = PlatformUtils.isWeb
          ? "/api/auth/bilibili/qrcode/poll"
          : "https://passport.bilibili.com/x/passport-login/web/qrcode/poll";
      var response = await HttpClient.instance.get(
        pollUrl,
        queryParameters: {"qrcode_key": qrcodeKey},
      );
      if (response.data["code"] != 0) {
        throw response.data["message"];
      }
      var data = response.data["data"];
      var code = data["code"];
      if (code == 0) {
        if (PlatformUtils.isWeb) {
          // cookie 已由后端托管，本地只标记登录态并拉取会话信息
          final session = await HttpClient.instance.getJson("/api/auth/bilibili/session");
          if (session["ok"] == true) {
            BiliBiliAccountService.instance.setCookie("managed-by-nas");
            BiliBiliAccountService.instance.name.value = session["uname"]?.toString() ?? '';
            BiliBiliAccountService.instance.logined.value = true;
            Navigator.of(Get.context!).pop();
          }
        } else {
          var cookies = <String>[];
          response.headers["set-cookie"]?.forEach((element) {
            var cookie = element.split(";")[0];
            cookies.add(cookie);
          });
          if (cookies.isNotEmpty) {
            var cookieStr = cookies.join(";");
            BiliBiliAccountService.instance.setCookie(cookieStr);
            await BiliBiliAccountService.instance.loadUserInfo();
            Navigator.of(Get.context!).pop();
          }
        }
      } else if (code == 86038) {
        qrStatus.value = QRStatus.expired;
        qrcodeKey = "";
        timer?.cancel();
      } else if (code == 86090) {
        qrStatus.value = QRStatus.scanned;
      }
    } catch (e) {
      ToastUtil.show(e.toString());
    }
  }

  @override
  void onClose() {
    timer?.cancel();
    super.onClose();
  }
}
