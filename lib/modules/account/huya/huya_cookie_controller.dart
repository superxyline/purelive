import 'package:pure_live/common/index.dart';

class HuyaCookieController extends GetxController {
  final TextEditingController cookieController = TextEditingController();

  @override
  void onInit() {
    super.onInit();
    cookieController.text = SettingsService.to.cookieManager.huyaCookie.v;
  }

  void setCookie(String cookie) {
    cookieController.text = cookie;
    SettingsService.to.cookieManager.huyaCookie.v = cookie;
    // 通知 NAS 补推登录态
    SettingsService.to.cookieManager.notifyLoginChanged();
  }
}
