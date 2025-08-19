import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:pure_live/common/l10n/generated/l10n.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/core/site/bilibili_site.dart';
import 'package:pure_live/core/site/cc_site.dart';
import 'package:pure_live/core/site/iptv_site.dart';
import 'package:pure_live/core/site/kuaishou_site.dart';
import 'package:pure_live/core/site/soop_site.dart';

import '../generated/iconfont.dart';
import 'interface/live_site.dart';
import 'site/douyin_site.dart';
import 'site/douyu_site.dart';
import 'site/huya_site.dart';

class Sites {
  static const String allSite = "all";
  static const String bilibiliSite = "bilibili";
  static const String douyuSite = "douyu";
  static const String huyaSite = "huya";
  static const String douyinSite = "douyin";
  static const String kuaishouSite = "kuaishou";
  static const String ccSite = "cc";
  static const String iptvSite = "iptv";
  static const String soopSite = "soop";
  static List<Site> supportSites = [
    Site(
      id: bilibiliSite,
      name: "哔哩",
      logo: "assets/images/bilibili_2.png",
      liveSite: BiliBiliSite(),
      iconData: IconFont.iconBilibiliSquare,
    ),
    Site(
      id: douyuSite,
      name: "斗鱼",
      logo: "assets/images/douyu.png",
      liveSite: DouyuSite(),
      iconData: IconFont.douyu,
    ),
    Site(
      id: huyaSite,
      name: "虎牙",
      logo: "assets/images/huya.png",
      liveSite: HuyaSite(),
      iconData: IconFont.huyaxianxing,
    ),
    Site(
      id: douyinSite,
      name: "抖音",
      logo: "assets/images/douyin.png",
      liveSite: DouyinSite(),
      iconData: IconFont.douyin,
    ),
    Site(
      id: kuaishouSite,
      name: "快手",
      logo: "assets/images/kuaishou.png",
      liveSite: KuaishowSite(),
      iconData: IconFont.kuaishou,
    ),
    Site(
      id: ccSite,
      name: "网易CC",
      logo: "assets/images/cc.png",
      liveSite: CCSite(),
      iconData: IconFont.creativeCommons,
    ),
    Site(
      id: soopSite,
      name: "SOOP",
      logo: "assets/images/soop.png",
      liveSite: SoopSite(),
      iconData: IconFont.soopLogo,
    ),
    Site(
      id: iptvSite,
      name: "网络",
      logo: "assets/images/iptv.png",
      liveSite: IptvSite(),
      iconData: IconFont.dianshi,
    ),
  ];

  static Site of(String id) {
    // return supportSites.firstWhere((e) => id == e.id) ?? supportSites[supportSites.length - 1];
    // return supportSites.firstWhereOrNull((e) => id == e.id) ?? supportSites[supportSites.length - 1];
    return siteMap[id] ?? supportSites[supportSites.length - 1];
  }

  static Map<String, Site>? _map;

  static Map<String, Site> get siteMap {
    if (_map == null) {
      var list = Sites.supportSites.map((e) => MapEntry(e.id, e)).toList();
      var map = Map.fromEntries(list);
      map[Sites.allLiveSite.id] = Sites.allLiveSite;
      _map = map;
    }
    return _map!;
  }

  static Site allLiveSite = Site(id: allSite, name: "全部", logo: "assets/images/all.png", liveSite: LiveSite());

  static String getSiteName(String siteId) {
    switch (siteId) {
      case allSite:
        return S.current.all;
      case bilibiliSite:
        return S.current.bilibili;
      case douyuSite:
        return S.current.douyu;
      case huyaSite:
        return S.current.huya;
      case douyinSite:
        return S.current.douyin;
      case kuaishouSite:
        return S.current.kuaishou;
      case ccSite:
        return S.current.cc;
      case iptvSite:
        return S.current.iptv;
      case soopSite:
        return S.current.soop;
    }
    return S.current.all;
  }

  List<Site> availableSites({bool containsAll = false}) {
    final SettingsService settingsService = Get.find<SettingsService>();
    if (containsAll) {
      var result = supportSites.where((element) => settingsService.hotAreasList.value.contains(element.id)).toList();
      result.insert(0, allLiveSite);
      return result;
    }
    return supportSites.where((element) => settingsService.hotAreasList.value.contains(element.id)).toList();
  }
}

class Site {
  final String id;
  final String name;
  final String logo;
  final LiveSite liveSite;
  IconData? iconData;

  Site({
    required this.id,
    required this.liveSite,
    required this.logo,
    required this.name,
    this.iconData,
  });
}
