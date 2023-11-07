import 'package:pure_live/common/models/live_area.dart';
import 'package:pure_live/common/models/live_message.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/core/danmaku/empty_danmaku.dart';
import 'package:pure_live/core/interface/live_danmaku.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/core/iptv/iptv_utils.dart';
import 'package:pure_live/model/live_category.dart';
import 'package:pure_live/model/live_category_result.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/model/live_search_result.dart';

class IptvSite implements LiveSite {
  @override
  String id = 'iptv';

  @override
  String name = "网络直播";

  @override
  Future<List<LiveCategory>> getCategores(int page, int pageSize) async {
    List<IptvCategory> categories = await IptvUtils.readCategory();
    List<LiveCategory> categoryTypes = [];
    for (var item in categories) {
      var subCategory = await getSubCategores(item);
      LiveCategory liveCategory = LiveCategory(
          id: item.id,
          name: item.path.replaceAll(r'.txt', ''),
          children: subCategory);
      categoryTypes.add(liveCategory);
    }
    return categoryTypes;
  }

  Future<List<LiveArea>> getSubCategores(IptvCategory liveCategory) async {
    List<LiveArea> subs = [];
    List<IptvCategoryItem> lists =
        await IptvUtils.readCategoryItems(liveCategory.path);
    for (var item in lists) {
      subs.add(LiveArea(
        areaPic: 'https://i-1.lanrentuku.com/2020/11/18/c7069c3c-e9ca-46a1-9f29-10ef22bf109a.png',
        areaId: item.liveUrl,
        typeName: liveCategory.path.replaceAll(r'.txt', ''),
        areaType: liveCategory.id,
        platform: 'iptv',
        areaName: item.name,
      ));
    }

    return subs;
  }

  @override
  Future<LiveCategoryResult> getCategoryRooms(LiveArea category,
      {int page = 1}) {
    var items = <LiveRoom>[];
    var roomItem = LiveRoom(
      roomId: category.areaId,
      title: category.typeName,
      cover: 'https://i-1.lanrentuku.com/2020/11/18/c7069c3c-e9ca-46a1-9f29-10ef22bf109a.png',
      nick: category.areaName,
      watching: '',
      avatar: '',
      area: '',
      liveStatus: LiveStatus.live,
      status: true,
      platform: 'iptv',
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
  Future<List<String>> getPlayUrls(
      {required LiveRoom detail, required LivePlayQuality quality}) async {
    return quality.data as List<String>;
  }

  @override
  Future<LiveCategoryResult> getRecommendRooms({int page = 1}) async {
    List<IptvCategoryItem> lists = await IptvUtils.readRecommandsItems();
    var items = <LiveRoom>[];
    for (var item in lists) {
    var room =  LiveRoom(
        cover: 'https://i-1.lanrentuku.com/2020/11/18/c7069c3c-e9ca-46a1-9f29-10ef22bf109a.png',
        watching: '',
        roomId: item.liveUrl,
        area: '热门电视',
        title: item.name,
        nick: '网络电视',
        avatar: 'https://img95.699pic.com/xsj/0q/x6/7p.jpg%21/fw/700/watermark/url/L3hzai93YXRlcl9kZXRhaWwyLnBuZw/align/southeast',
        introduction: '',
        notice: '',
        status: true,
        liveStatus: LiveStatus.live,
        platform: 'iptv',
        link: item.liveUrl,
        data: item.liveUrl,
      );
      items.add(room);
    }
    return LiveCategoryResult(hasMore: false, items: items);
  }

  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) async {
    var data = [];
    data.add(roomId);
    return LiveRoom(
      cover: 'https://i-1.lanrentuku.com/2020/11/18/c7069c3c-e9ca-46a1-9f29-10ef22bf109a.png',
      watching: '',
      roomId: roomId,
      area: '',
      title: '',
      nick: 'https://img95.699pic.com/xsj/0q/x6/7p.jpg%21/fw/700/watermark/url/L3hzai93YXRlcl9kZXRhaWwyLnBuZw/align/southeast',
      avatar: '',
      introduction: '',
      notice: '',
      status: true,
      liveStatus: LiveStatus.live,
      platform: 'iptv',
      link: 'roomId',
      data: data,
    );
  }

  @override
  Future<List<LiveSuperChatMessage>> getSuperChatMessage(
      {required String roomId}) {
    //尚不支持
    return Future.value([]);
  }

  @override
  Future<LiveSearchAnchorResult> searchAnchors(String keyword,
      {int page = 1}) async {
    return LiveSearchAnchorResult(hasMore: false, items: []);
  }

  @override
  Future<LiveSearchRoomResult> searchRooms(String keyword,
      {int page = 1}) async {
    return LiveSearchRoomResult(hasMore: false, items: []);
  }
}
