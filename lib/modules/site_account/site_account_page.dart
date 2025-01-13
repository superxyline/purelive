import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pure_live/common/l10n/generated/l10n.dart';
import 'package:pure_live/core/sites.dart';
import 'package:pure_live/modules/site_account/site_account_controller.dart';

class SiteAccountPage extends GetView<SiteAccountController> {
  const SiteAccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.of(Get.context!).three_party_authentication),
      ),
      body: ListView(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              S.of(Get.context!).bilibili_need_login_info,
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
                        title: Text("${site.name} ${S.of(Get.context!).live}"),
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
                      title: Text("${site.name} ${S.of(Get.context!).live}"),
                      subtitle: Text(S.of(Get.context!).not_supported),
                      enabled: false,
                      trailing: const Icon(Icons.chevron_right),
                    )),
        ],
      ),
    );
  }
}
