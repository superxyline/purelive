import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/models/index.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/core/danmaku/web_danmaku.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/model/live_anchor_item.dart';
import 'package:pure_live/model/live_category.dart';
import 'package:pure_live/model/live_play_quality.dart';

/// Web 端统一站点实现：不直连平台 API（CORS + 签名 + 风控都过不去），
/// 全部请求映射到 NAS 后端的 REST 接口，由后端聚合转发。
class ProxySite extends LiveSite {
  final String platform;

  ProxySite(this.platform) {
    id = platform;
    name = platform;
  }

  Future<dynamic> _get(String path, [Map<String, dynamic>? query]) {
    return HttpClient.instance.getJson('/api/sites/$platform/$path', queryParameters: query);
  }

  LiveRoom _room(Map<String, dynamic> json) => LiveRoom.fromJson(json);

  @override
  Future<List<LiveCategory>> getCategores(int page, int pageSize) async {
    final result = await _get('categories', {'page': '$page', 'size': '$pageSize'});
    final list = (result['data'] as List? ?? []);
    return list
        .map((e) => LiveCategory.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 20}) async {
    final result = await _get('categories/${category.areaId}/rooms', {
      'page': '$page',
      'size': '$pageSize',
      'typeName': category.typeName ?? '',
    });
    return ((result['data'] as List? ?? []).map((e) => _room(Map<String, dynamic>.from(e as Map)))).toList();
  }

  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 20}) async {
    final result = await _get('recommend', {'page': '$page', 'size': '$pageSize'});
    return ((result['data'] as List? ?? []).map((e) => _room(Map<String, dynamic>.from(e as Map)))).toList();
  }

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 20}) async {
    final result = await _get('search', {'q': keyword, 'page': '$page', 'size': '$pageSize'});
    return ((result['data'] as List? ?? []).map((e) => _room(Map<String, dynamic>.from(e as Map)))).toList();
  }

  @override
  Future<List<LiveAnchorItem>> searchAnchors(String keyword, {int page = 1, int pageSize = 20}) async {
    final result = await _get('search', {'q': keyword, 'page': '$page', 'size': '$pageSize', 'anchors': 'true'});
    final list = result['data'] as List? ?? [];
    return list.map((e) => LiveAnchorItem.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  @override
  Future<LiveRoom> getRoomDetail({required String roomId, required String platform, bool light = false}) async {
    final result = await _get('rooms/$roomId', {'light': light ? 'true' : 'false'});
    return _room(Map<String, dynamic>.from(result['data'] as Map));
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualites({required LiveRoom detail}) async {
    final result = await _get('rooms/${detail.roomId}/play-urls');
    final list = result['qualities'] as List? ?? [];
    return list
        .map((e) {
          final map = Map<String, dynamic>.from(e as Map);
          return LivePlayQuality(
            quality: map['quality']?.toString() ?? '',
            data: map['data'],
            sort: (map['sort'] as num?)?.toInt() ?? 0,
          );
        })
        .toList();
  }

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async {
    final result = await _get('rooms/${detail.roomId}/play-urls', {'quality': quality.quality});
    return (result['urls'] as List? ?? []).map((e) => e.toString()).toList();
  }

  @override
  Future<bool> getLiveStatus({required String platform, required String roomId}) async {
    final result = await _get('rooms/$roomId/live-status');
    return result['live'] == true;
  }

  @override
  Future<List<LiveSuperChatMessage>> getSuperChatMessage({required String roomId}) async {
    // SC 消息由弹幕流推送（superChat 类型），独立查询接口 web 端不提供。
    return [];
  }

  @override
  Future<(bool, String)> sendDanmaku({required String roomId, required String message}) async {
    final result = await HttpClient.instance.postJson(
      '/api/sites/$platform/danmaku/send',
      data: {'roomId': roomId, 'message': message},
    );
    final ok = result['ok'] == true;
    return (ok, result['message']?.toString() ?? '');
  }

  @override
  WebDanmaku getDanmaku() => WebDanmaku(platform);
}
