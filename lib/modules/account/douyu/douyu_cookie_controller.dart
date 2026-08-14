import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/services/follow_sync_service.dart';

class DouyuCookieController extends GetxController {
  final TextEditingController cookieController = TextEditingController();

  @override
  void onInit() {
    super.onInit();
    cookieController.text = SettingsService.to.cookieManager.douyuCookie.v;
  }

  void setCookie(String cookie) {
    cookieController.text = cookie;
    SettingsService.to.cookieManager.douyuCookie.v = cookie;
  }

  void syncFollows() {
    FollowSyncService.runAndShowResult(
      task: FollowSyncService.syncDouyu,
      loadingMsg: i18n("follow_sync_loading_douyu"),
    );
  }
}
