import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/services/follow_sync_service.dart';

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
  }

  void syncFollows() {
    FollowSyncService.runAndShowResult(
      task: FollowSyncService.syncHuya,
      loadingMsg: i18n("follow_sync_loading_huya"),
    );
  }
}
