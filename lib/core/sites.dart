import 'interface/live_site.dart';
import 'site/bilibili_site.dart';
import 'site/douyu_site.dart';
import 'site/huya_site.dart';
import 'site/douyin_site.dart';
class Sites {
  static List<Site> supportSites = [
    Site(
      id: "bilibili",
      name: "哔哩",
      liveSite: BilibiliSite(),
    ),
    Site(
      id: "douyu",
      name: "斗鱼",
      liveSite: DouyuSite(),
    ),
    Site(
      id: "huya",
      name: "虎牙",
      liveSite: HuyaSite(),
    ),
    Site(
      id: "douyin",
      name: "抖音",
      liveSite: DouyinSite(),
    ),
  ];

  static Site of(String id) {
    return supportSites.firstWhere((e) => id == e.id);
  }
}

class Site {
  final String id;
  final String name;
  final LiveSite liveSite;
  Site({
    required this.id,
    required this.name,
    required this.liveSite,
  });
}
