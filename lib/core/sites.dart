import 'package:pure_live/core/site/bilibili_site.dart';
import 'package:pure_live/core/site/iptv_site.dart';
import 'package:pure_live/core/site/kuaishou_site.dart';

import 'interface/live_site.dart';
import 'site/douyu_site.dart';
import 'site/huya_site.dart';
import 'site/douyin_site.dart';

class Sites {
  static List<Site> supportSites = [
    Site(
      id: "bilibili",
      name: "哔哩",
      logo: "assets/images/bilibili_2.png",
      liveSite: BiliBiliSite(),
    ),
    Site(
      id: "douyu",
      name: "斗鱼",
      logo: "assets/images/douyu.png",
      liveSite: DouyuSite(),
    ),
    Site(
      id: "huya",
      name: "虎牙",
      logo: "assets/images/huya.png",
      liveSite: HuyaSite(),
    ),
    Site(
      id: "douyin",
      name: "抖音",
      logo: "assets/images/douyin.png",
      liveSite: DouyinSite(),
    ),
    Site(
      id: "kuaishou",
      name: "快手",
      logo: "assets/images/kuaishou.png",
      liveSite: KuaishowSite(),
    ),
    Site(
      id: "iptv",
      name: "网络电视",
      logo: "assets/images/kuaishou.png",
      liveSite: IptvSite(),
    ),
  ];

  static Site of(String id) {
    return supportSites.firstWhere((e) => id == e.id);
  }
}

class Site {
  final String id;
  final String name;
  final String logo;
  final LiveSite liveSite;
  Site({
    required this.id,
    required this.liveSite,
    required this.logo,
    required this.name,
  });
}
