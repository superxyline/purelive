import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/model/live_category.dart';
import 'package:pure_live/common/models/live_area.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/model/live_search_result.dart';
import 'package:pure_live/common/models/live_message.dart';
import 'package:pure_live/core/danmaku/empty_danmaku.dart';
import 'package:pure_live/model/live_category_result.dart';
import 'package:pure_live/core/interface/live_danmaku.dart';
import 'package:pure_live/custom/custom_site_providder.dart';

class CustomSite implements LiveSite {
  @override
  String id = 'custom';

  @override
  String name = "自定义";

  @override
  Future<List<LiveCategory>> getCategores(int page, int pageSize) async {
    List<LiveCategory> categoryTypes = [];
    var subCategory = await getSubCategores();
    LiveCategory liveCategory = LiveCategory(id: 'custom', name: '站点名称', children: subCategory);
    categoryTypes.add(liveCategory);
    return categoryTypes;
  }

  Future<List<LiveArea>> getSubCategores() async {
    List<LiveArea> subs = [];
    List<SiteInfoMation> lists = CustomSiteProvider.instance.querySite();
    for (var item in lists) {
      subs.add(LiveArea(
          areaPic: item.siteCover ?? '',
          areaId: item.id,
          typeName: '自定义',
          areaType: item.siteUrl,
          platform: 'custom',
          areaName: item.siteTitle,
          shortName: item.siteIsHot));
    }

    return subs;
  }

  @override
  Future<LiveCategoryResult> getCategoryRooms(LiveArea category, {int page = 1}) {
    var items = <LiveRoom>[];
    var roomItem = LiveRoom(
      roomId: category.areaName,
      title: category.typeName,
      cover: '',
      nick: category.typeName,
      watching: category.areaId,
      avatar:
          'https://img95.699pic.com/xsj/0q/x6/7p.jpg%21/fw/700/watermark/url/L3hzai93YXRlcl9kZXRhaWwyLnBuZw/align/southeast',
      area: category.areaType,
      liveStatus: LiveStatus.live,
      status: true,
      platform: 'custom',
    );
    items.add(roomItem);
    return Future.value(LiveCategoryResult(hasMore: false, items: items));
  }

  @override
  LiveDanmaku getDanmaku() => EmptyDanmaku();

  @override
  Future<bool> getLiveStatus({required String roomId}) {
    return Future.value(true);
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualites({required LiveRoom detail}) {
    List<LivePlayQuality> qualities = <LivePlayQuality>[];
    var qualityItem = LivePlayQuality(
      quality: '默认',
      sort: 1,
      data: <String>[detail.data[0]],
    );
    qualities.add(qualityItem);
    return Future.value(qualities);
  }

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async {
    return quality.data as List<String>;
  }

  @override
  Future<LiveCategoryResult> getRecommendRooms({int page = 1}) async {
    List<SiteInfoMation> sites = CustomSiteProvider.instance.querySite();

    // tvg-id: CCTV1, tvg-name: CCTV1, tvg-logo: https://live.fanmingming.com/tv/CCTV1.png, group-title: 央视
    var items = <LiveRoom>[];
    for (var item in sites) {
      var room = LiveRoom(
        cover: item.siteCover ?? '',
        watching: '',
        roomId: item.id,
        area: '',
        title: item.siteTitle,
        nick: item.siteIsHot == '1' ? '热门' : '自定义',
        avatar:
            'https://img95.699pic.com/xsj/0q/x6/7p.jpg%21/fw/700/watermark/url/L3hzai93YXRlcl9kZXRhaWwyLnBuZw/align/southeast',
        introduction: '',
        notice: '',
        status: true,
        liveStatus: LiveStatus.live,
        platform: 'custom',
        link: item.siteUrl,
        data: item.siteIsHot,
      );
      if (item.siteIsHot == '1') {
        items.add(room);
      }
    }
    return LiveCategoryResult(hasMore: false, items: items);
  }

  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) async {
    final SettingsService service = Get.find<SettingsService>();
    var siteIndex = service.customSites.indexWhere((item) => item.id == roomId);

    return LiveRoom(
      cover: '',
      watching: '',
      roomId: roomId,
      area: '',
      title: service.customSites[siteIndex].siteTitle,
      nick: service.customSites[siteIndex].siteIsHot == '1' ? '热门' : '自定义',
      avatar:
          'https://img95.699pic.com/xsj/0q/x6/7p.jpg%21/fw/700/watermark/url/L3hzai93YXRlcl9kZXRhaWwyLnBuZw/align/southeast',
      introduction: '',
      notice: '',
      status: true,
      liveStatus: LiveStatus.live,
      platform: 'custom',
      link: roomId,
      data: roomId,
    );
  }

  @override
  Future<List<LiveSuperChatMessage>> getSuperChatMessage({required String roomId}) {
    //尚不支持
    return Future.value([]);
  }

  @override
  Future<LiveSearchAnchorResult> searchAnchors(String keyword, {int page = 1}) async {
    return LiveSearchAnchorResult(hasMore: false, items: []);
  }

  @override
  Future<LiveSearchRoomResult> searchRooms(String keyword, {int page = 1}) async {
    return LiveSearchRoomResult(hasMore: false, items: []);
  }
}
