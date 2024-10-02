import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:pure_live/core/sites.dart';

class SiteWidget {
  /// 所有站点的 logo
  static Map<String, Widget> get siteLogeImageMap {
    var list = Sites.supportSites
        .map((e) => MapEntry(
            e.id,
            ExtendedImage.asset(
              e.logo,
              width: 22,
              cacheRawData: true,
              enableMemoryCache: true,
            )))
        .toList();
    var map = Map.fromEntries(list);
    map[Sites.allLiveSite.id] = ExtendedImage.asset(
      Sites.allLiveSite.logo,
      width: 22,
      cacheRawData: true,
      enableMemoryCache: true,
    );
    return map;
  }

  /// 获取站点 logo Image
  static Widget? getSiteLogeImage(String siteId) {
    return siteLogeImageMap[siteId];
  }

  /// 获取站点 Tab
  static Tab getSiteTab(Site site) {
    return Tab(
      text: site.name,
      iconMargin: const EdgeInsets.all(0),
      icon: getSiteLogeImage(site.id),
    );
  }

  /// 获取 可用站点的 tab 包含一个所有站点的标志
  static List<Widget> get availableSitesWithAllTabList {
    return Sites()
        .availableSites(containsAll: true)
        .map((site) => getSiteTab(site))
        .toList();
  }

  /// 获取 可用站点的 tab
  static List<Widget> get availableSitesTabList {
    return Sites().availableSites().map((site) => getSiteTab(site)).toList();
  }

  static List<Widget> getAvailableSites({containsAll = false}) {
    if (containsAll) {
      return availableSitesWithAllTabList;
    }
    return availableSitesTabList;
  }
}
