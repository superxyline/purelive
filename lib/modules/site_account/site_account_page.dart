import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pure_live/core/sites.dart';
import 'package:pure_live/modules/site_account/site_account_controller.dart';

class SiteAccountPage extends GetView<SiteAccountController> {
  const SiteAccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("三方认证"),
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              "哔哩哔哩账号需要登录才能看高清晰度的直播，其他平台暂无此限制。",
              textAlign: TextAlign.center,
            ),
          ),
          ...Sites.supportSites
              .where((site) =>
                  !([Sites.iptvSite, Sites.allSite].contains(site.id)))
              .map((site) => site.liveSite.isSupportLogin()
                  ? Obx(
                      () => ListTile(
                        leading: ExtendedImage.asset(
                          site.logo,
                          width: 36,
                          height: 36,
                        ),
                        title: Text("${site.name} 直播"),
                        subtitle: Text(site.liveSite.userName.value),
                        trailing: site.liveSite.isLogin.value
                            ? const Icon(Icons.logout)
                            : const Icon(Icons.chevron_right),
                        onTap: () {
                          controller.onTap(site);
                        },
                      ),
                    )
                  : ListTile(
                      leading: ExtendedImage.asset(
                        site.logo,
                        width: 36,
                        height: 36,
                      ),
                      title: Text("${site.name} 直播"),
                      subtitle: const Text("尚不支持"),
                      enabled: false,
                      trailing: const Icon(Icons.chevron_right),
                    )),
        ],
      ),
    );
  }
}
