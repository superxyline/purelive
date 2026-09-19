import 'site/huya_site.dart';
import 'site/douyu_site.dart';
import 'site/douyin_site.dart';
import 'site/kuaishou_site.dart';
import 'site/web/proxy_site.dart';
import 'interface/live_site.dart';

import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/global/platform_utils.dart';
import 'package:pure_live/core/site/bilibili_site.dart';

class Sites {
  static const String allSite = "all";
  static const String bilibiliSite = "bilibili";
  static const String douyuSite = "douyu";
  static const String huyaSite = "huya";
  static const String douyinSite = "douyin";
  static const String kuaishouSite = "kuaishou";
  static const Set<String> supportedSiteIds = {
    bilibiliSite,
    douyuSite,
    huyaSite,
    douyinSite,
    kuaishouSite,
  };

  static bool isSupported(String id) => supportedSiteIds.contains(id.trim().toLowerCase());

  /// Web 端全部走 NAS 后端代理（CORS/签名/风控都无法在浏览器内解决）；
  /// 原生端直连平台 API。
  static List<Site> get supportSites => [
    Site(
      id: bilibiliSite,
      name: i18n("site_bilibili"),
      logo: "assets/images/bilibili_2.png",
      liveSite: PlatformUtils.isWeb ? ProxySite(bilibiliSite) : BiliBiliSite(),
    ),
    Site(
      id: douyuSite,
      name: i18n("site_douyu"),
      logo: "assets/images/douyu.png",
      liveSite: PlatformUtils.isWeb ? ProxySite(douyuSite) : DouyuSite(),
    ),
    Site(
      id: huyaSite,
      name: i18n("site_huya"),
      logo: "assets/images/huya.png",
      liveSite: PlatformUtils.isWeb ? ProxySite(huyaSite) : HuyaSite(),
    ),
    Site(
      id: douyinSite,
      name: i18n("site_douyin"),
      logo: "assets/images/douyin.png",
      liveSite: PlatformUtils.isWeb ? ProxySite(douyinSite) : DouyinSite(),
    ),
    Site(
      id: kuaishouSite,
      name: i18n("site_kuaishou"),
      logo: "assets/images/kuaishou.png",
      liveSite: PlatformUtils.isWeb ? ProxySite(kuaishouSite) : KuaishowSite(),
    ),
  ];

  static Site of(String id) {
    return supportSites.firstWhere((e) => id == e.id);
  }

  List<Site> availableSites({bool containsAll = false}) {
    final List<String> savedIds = SettingsService.to.fav.hotAreasList.v;
    final supportedById = {for (final site in supportSites) site.id: site};
    final List<Site> result = [];
    for (String id in savedIds) {
      final match = supportedById[id];
      if (match != null) {
        result.add(match);
      }
    }
    if (containsAll) {
      result.insert(0, Site(id: allSite, name: i18n("site_all"), logo: "assets/images/all.png", liveSite: LiveSite()));
    }
    return result;
  }
}

class Site {
  final String id;
  final String name;
  final String logo;
  final LiveSite liveSite;
  Site({required this.id, required this.liveSite, required this.logo, required this.name});
}
