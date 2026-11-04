import 'dart:async';

import 'package:pure_live/common/index.dart';
import 'package:pure_live/player/adapters/media_kit_adapter.dart';
import 'package:pure_live/player/core/secondary_player_service.dart';

/// 副音轨：主窗口看 A 直播间的画面，声音来自 B 直播间的解说。
///
/// 与「双开」的区别：
/// - 双开是两路画面，副窗口恒静音、声音只来自主窗口；
/// - 副音轨平时只有一路画面（副播放器视频轨在解但不渲染，只在预览时显示），
///   声音全部来自副直播间。
///
/// 同步方案：**双画面对比 + 手动暂停**。
/// 直播流无法回溯（`audio-delay` 在无视频输出时被内核忽略、`adelay` 滤镜也不生效），
/// 所以不靠数值延迟，而是进对齐页把两路画面并排显示，暂停跑得快的那一路等另一路追上，
/// 两路播放位置一致后退出预览即长期同步。
///
/// 音频接管规则（保证"听起来还是一个直播间"）：
/// - 主播放器内核音量置 0，但**不动系统媒体音量**，所以手机音量键依然整体生效；
/// - 桌面端的内核音量调整由 [PlayerManager.setVolume] 转发到这里；
/// - 退出直播间时释放，副音轨不跨房间保留。
class AudioCompanionService {
  AudioCompanionService._();
  static final AudioCompanionService instance = AudioCompanionService._();

  MediaKitAdapter? _adapter;
  double _volume = 1.0;

  /// 是否已接管当前直播间的音频
  final RxBool isActive = false.obs;

  /// 副音轨是否正在加载
  final RxBool isLoading = false.obs;

  /// 最近一次失败原因（空 = 无错误）
  final RxString error = RxString('');

  /// 当前提供声音的直播间
  final Rx<LiveRoom?> room = Rx<LiveRoom?>(null);

  /// 是否正在"音画对齐预览"（预览时渲染副画面）
  final RxBool isPreviewing = false.obs;

  bool get hasRoom => room.value != null;

  /// 副画面组件（仅对齐预览页渲染）。
  Widget get videoWidget => _adapter?.getVideoWidget() ?? const SizedBox.shrink();

  /// 启动（或替换）副音轨。启动成功后由调用方直接进对齐页。
  Future<bool> start(LiveRoom target) async {
    if (target.roomId == null || target.platform == null) return false;
    isLoading.value = true;
    error.value = '';
    try {
      final adapter = await _ensureAdapter();
      final platform = target.platform!;
      final site = Sites.of(platform);
      final detail = await site.liveSite.getRoomDetail(roomId: target.roomId!, platform: platform);
      final roomId = detail.roomId;
      if (detail.status != true || roomId == null || roomId.isEmpty) {
        error.value = i18n('audio_companion_offline');
        isLoading.value = false;
        return false;
      }
      final qualities = await site.liveSite.getPlayQualites(detail: detail);
      if (qualities.isEmpty) {
        error.value = i18n('audio_companion_no_stream');
        isLoading.value = false;
        return false;
      }
      // 只看/只听最低清晰度：省流量，对齐页的小窗也够看清内容
      final urls = await site.liveSite.getPlayUrls(detail: detail, quality: qualities.last);
      if (urls.isEmpty) {
        error.value = i18n('audio_companion_no_stream');
        isLoading.value = false;
        return false;
      }
      final headers = SecondaryPlayerService.buildStreamHeaders(platform);
      await adapter.setDataSource(urls.first, urls, headers, room: detail);
      await adapter.setVolume(_volume);
      // 视频轨保持可用：关掉后再打开不可靠（会出现"只有声音没画面"）
      await adapter.setVideoDecodingEnabled(true);
      room.value = detail;
      isActive.value = true;
      await adapter.play();
      isLoading.value = false;
      return true;
    } catch (e) {
      error.value = e.toString();
      isLoading.value = false;
      return false;
    }
  }

  /// 打开/关闭对齐预览。视频轨始终开着，这里只记录状态，是否渲染画面由 UI 决定。
  Future<void> setPreview(bool enabled) async {
    isPreviewing.value = enabled;
  }

  /// 音量统一入口（桌面端内核音量转发到这里；移动端由系统音量决定）
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    if (!isActive.value) return;
    await _adapter?.setVolume(_volume);
  }

  /// 跟随主画面暂停：避免"画面停了声音还在"（含睡眠定时到点结束）。
  /// 用户在对齐页手动暂停时会跳过这里，声音要继续放。
  Future<void> pausePlayback() async {
    if (!isActive.value) return;
    await _adapter?.pause();
  }

  /// 跟随主画面恢复。
  Future<void> resumePlayback() async {
    if (!isActive.value) return;
    await _adapter?.play();
  }

  /// 关闭并释放副音轨。
  ///
  /// 纯音频/后台播放器在部分机型上 `dispose` 不会立刻拆掉 AudioTrack，
  /// 所以这里先把音量压到 0、再暂停，最后才销毁实例——保证关闭/退出后
  /// 用户立刻听不到声音，不会出现"画面关了声音还在"。
  Future<void> stop() async {
    final adapter = _adapter;
    _adapter = null;
    isActive.value = false;
    isLoading.value = false;
    isPreviewing.value = false;
    room.value = null;
    error.value = '';
    if (adapter == null) {
      debugPrint('[AudioCompanion] stop: adapter 为空，无播放器可释放');
      return;
    }
    debugPrint('[AudioCompanion] stop: 静音 -> 暂停 -> 销毁');
    try {
      await adapter.setVolume(0);
    } catch (_) {}
    try {
      await adapter.pause();
    } catch (_) {}
    try {
      // 某些机型 dispose 可能长时间不返回，加超时避免拖住调用方（退出直播间/恢复主音量）
      await adapter.hardDispose().timeout(const Duration(seconds: 3));
      debugPrint('[AudioCompanion] stop: 销毁完成');
    } catch (e) {
      debugPrint('[AudioCompanion] stop: 销毁异常 $e');
    }
  }

  Future<MediaKitAdapter> _ensureAdapter() async {
    final existing = _adapter;
    if (existing != null) {
      if (existing.isInitialized) return existing;
      // 上次初始化没完成：先彻底销毁再重建，避免旧实例继续出声却已丢失引用
      try {
        await existing.hardDispose();
      } catch (_) {}
    }
    final adapter = MediaKitAdapter();
    // 不用 audioOnly：那样创建的是 vo=null 的纯音频会话，永远出不了画面
    await adapter.init();
    _adapter = adapter;
    return adapter;
  }
}
