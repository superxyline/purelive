import 'package:pure_live/common/index.dart';
import 'package:pure_live/player/adapters/media_kit_adapter.dart';
import 'package:pure_live/modules/live_play/live_play_controller.dart';

/// 双开副播放器服务。
///
/// 负责"主+小窗"双开模式下，用独立的播放器实例渲染副直播间：
/// - 副窗口始终静音，音频只来自主窗口；
/// - 点副窗口可"互换主副"：主窗口切到副房间出声，副窗口切回原主房间静音；
/// - "换一个"只替换副房间，不影响主窗口。
class SecondaryPlayerService {
  SecondaryPlayerService._();
  static final SecondaryPlayerService instance = SecondaryPlayerService._();

  MediaKitAdapter? _adapter;

  /// 副窗口是否在显示中
  final RxBool isActive = false.obs;

  /// 副窗口是否正在加载
  final RxBool isLoading = false.obs;

  /// 副窗口是否加载失败/未开播
  final RxBool isFailed = false.obs;

  /// 副窗口当前房间
  final Rx<LiveRoom?> room = Rx<LiveRoom?>(null);

  /// 副窗口渲染组件
  Widget get videoWidget =>
      _adapter?.getVideoWidget() ?? const SizedBox.shrink();

  /// 启动或替换副房间。
  Future<void> loadRoom(LiveRoom target) async {
    if (target.roomId == null || target.platform == null) {
      isFailed.value = true;
      return;
    }
    isLoading.value = true;
    isFailed.value = false;
    try {
      final adapter = await _ensureAdapter();
      final platform = target.platform!;
      final site = Sites.of(platform);
      final detail = await site.liveSite.getRoomDetail(
        roomId: target.roomId!,
        platform: platform,
      );
      final roomId = detail.roomId;
      if (detail.status != true || roomId == null || roomId.isEmpty) {
        isFailed.value = true;
        return;
      }
      final qualites = await site.liveSite.getPlayQualites(detail: detail);
      if (qualites.isEmpty) {
        isFailed.value = true;
        return;
      }
      // 副窗口较小，默认取最低清晰度以节省流量与解码开销
      final urls = await site.liveSite.getPlayUrls(
        detail: detail,
        quality: qualites.first,
      );
      if (urls.isEmpty) {
        isFailed.value = true;
        return;
      }
      final headers = _buildStreamHeaders(platform);
      await adapter.setDataSource(urls.first, urls, headers, room: detail);
      await adapter.setVolume(0); // 副窗口静音，音频只来自主窗口
      await adapter.play();
      room.value = detail;
      isActive.value = true;
    } catch (_) {
      isFailed.value = true;
    } finally {
      isLoading.value = false;
    }
  }

  /// 互换主副：主窗口切到副房间出声，副窗口切回原主房间静音。
  Future<void> swapWithMain(LivePlayController controller) async {
    final secondary = room.value;
    final main = controller.detail.value;
    if (secondary == null ||
        main == null ||
        secondary.roomId == null ||
        main.roomId == null ||
        secondary.roomId == main.roomId) {
      return;
    }
    controller.switchRoom(secondary);
    await loadRoom(main);
  }

  /// 关闭副窗口并释放播放器。
  Future<void> close() async {
    await _adapter?.hardDispose();
    _adapter = null;
    isActive.value = false;
    isLoading.value = false;
    isFailed.value = false;
    room.value = null;
  }

  Future<MediaKitAdapter> _ensureAdapter() async {
    final existing = _adapter;
    if (existing != null) return existing;
    final adapter = MediaKitAdapter();
    await adapter.init();
    _adapter = adapter;
    return adapter;
  }

  /// 构造直播流请求头（与主播放器保持一致）。
  Map<String, String> _buildStreamHeaders(String platform) {
    switch (platform) {
      case Sites.bilibiliSite:
        return {
          "cookie": SettingsService.to.cookieManager.bilibiliCookie.v,
          "user-agent":
              "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
          "referer": "https://live.bilibili.com",
        };
      case Sites.huyaSite:
        return {
          "user-agent": "webh5&0.1.0&websocket",
          "origin": "https://www.huya.com",
        };
      default:
        return {};
    }
  }
}
