import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/widgets/utils.dart';

class SiteAccountController extends GetxController {
  @override
  void onInit() {
    super.onInit();
    initAllSiteCookie();
  }

  SettingsService settings = Get.find<SettingsService>();

  /// 初始化所有站点的cookie
  void initAllSiteCookie() {
    var siteCookies = settings.siteCookies;
    for (var key in siteCookies.keys) {
      var cookie = siteCookies[key] ?? "";
      var site = Sites.of(key);
      site.liveSite.loadUserInfo(site, cookie);
    }
  }

  /// 跳转至直播平台登录
  Future toSiteLogin(Site site) async {
    Utils.showRightOrBottomSheet(
      title: "登录${site.name}",
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Visibility(
            visible: site.liveSite.isSupportWebLogin(),
            child: ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: const Text("Web登录"),
              subtitle: const Text("填写用户名密码登录"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(Get.context!).pop();
                Get.toNamed(RoutePath.kSiteWebLogin, parameters: {"site": site.id});
              },
            ),
          ),
          Visibility(
              visible: site.liveSite.isSupportQrLogin(),
              child: ListTile(
                leading: const Icon(Icons.qr_code),
                title: const Text("扫码登录"),
                subtitle: const Text("使用哔哩哔哩APP扫描二维码登录"),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(Get.context!).pop();
                  Get.toNamed(RoutePath.kSiteQRLogin, parameters: {"site": site.id});
                },
              )),
          Visibility(
              visible: site.liveSite.isSupportCookieLogin(),
              child: ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text("Cookie登录"),
                subtitle: const Text("手动输入Cookie登录"),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(Get.context!).pop();
                  doCookieLogin(site);
                },
              )),
        ],
      ),
    );
  }

  /// cookie登录
  void doCookieLogin(Site site) async {
    var cookie = await Utils.showEditTextDialog(
      "",
      title: "请输入Cookie",
      hintText: "请输入Cookie",
    );
    if (cookie == null || cookie.isEmpty) {
      return;
    }
    bool flag = await site.liveSite.loadUserInfo(site, cookie);
    if (!flag) {
      Utils.showAlertDialog("Cookie校验失败！");
    }
  }

  /// 点击
  void onTap(Site site) async {
    if (site.liveSite.isLogin.value) {
      var result =
          await Utils.showAlertDialog("确定要退出 ${site.name} 账号吗？", title: "退出登录");
      if (result) {
        site.liveSite.logout(site);
      }
    } else {
      toSiteLogin(site);
    }
  }
}
