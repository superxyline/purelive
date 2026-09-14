import 'package:pure_live/model/live_category.dart';
import 'package:pure_live/model/live_anchor_item.dart';
import 'package:pure_live/common/models/live_area.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/common/models/live_message.dart';
import 'package:pure_live/core/interface/live_danmaku.dart';

class LiveSite {
  String id = "";
  String name = "";

  LiveDanmaku getDanmaku() {
    throw UnimplementedError();
  }

  Future<List<LiveCategory>> getCategores(int page, int pageSize) async {
    return Future.value(<LiveCategory>[]);
  }

  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) async {
    return Future.value(<LiveRoom>[]);
  }

  Future<List<LiveAnchorItem>> searchAnchors(String keyword, {int page = 1, int pageSize = 30}) async {
    return Future.value(<LiveAnchorItem>[]);
  }

  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async {
    return Future.value(<LiveRoom>[]);
  }

  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    return Future.value(<LiveRoom>[]);
  }

  /// 读取直播间详情。
  ///
  /// [light] 为 true 时只取"列表卡片需要的那几项"，跳过弹幕服务器发现、弹幕
  /// 签名、粉丝数抓取等只有进入房间才需要的请求（收藏 / 热门列表批量刷新用，
  /// 可显著减少每房间的请求数）。轻量详情**只交给卡片渲染**：进入房间时播放页
  /// 会重新拉一次完整详情（`onInitPlayerState` → `getRoomDetail`），弹幕与
  /// 播放流用的都是那份数据，因此不能把轻量详情当完整房间数据长期使用。
  Future<LiveRoom> getRoomDetail({
    required String roomId,
    required String platform,
    bool light = false,
  }) async {
    return Future.value(
      LiveRoom(
        cover: '',
        watching: '0',
        roomId: '',
        status: false,
        platform: platform,
        liveStatus: LiveStatus.offline,
        title: '',
        link: '',
        avatar: '',
        nick: '',
        isRecord: false,
      ),
    );
  }

  Future<List<LivePlayQuality>> getPlayQualites({required LiveRoom detail}) async {
    return Future.value(<LivePlayQuality>[]);
  }

  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async {
    return Future.value(<String>[]);
  }

  Future<bool> getLiveStatus({required String platform, required String roomId}) async {
    return Future.value(false);
  }

  Future<List<LiveSuperChatMessage>> getSuperChatMessage({required String roomId}) async {
    return Future.value([]);
  }

  /// 发送弹幕，返回 (是否成功, 提示信息)。
  Future<(bool, String)> sendDanmaku({required String roomId, required String message}) async {
    return (false, '当前平台暂不支持发送弹幕');
  }
}
