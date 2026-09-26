import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/player/core/portrait_stream_support.dart';
import 'package:pure_live/player/global_player_service.dart';

/// 竖屏沉浸方向策略（上游 `PortraitFullscreenPolicy` / `PortraitOrientationOverride`
/// 的接线层）。决策优先级：每房间覆盖 > 全局策略（默认 landscape 保持旧行为）。
class OrientationPolicy {
  /// 覆盖值循环顺序：auto → portrait → landscape → auto
  static const List<String> _cycleOrder = ['auto', 'portrait', 'landscape'];

  static Map<String, String> _overrides() {
    try {
      final raw = jsonDecode(SettingsService.to.player.roomOrientationOverridesRaw.v);
      if (raw is Map) {
        return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    } catch (_) {
      // 损坏的覆盖表按空处理
    }
    return <String, String>{};
  }

  static String roomKey(String platform, String roomId) => '$platform:$roomId';

  /// 某房间当前覆盖值：auto（跟随全局策略）/ portrait / landscape
  static String overrideFor(String platform, String roomId) {
    return _overrides()[roomKey(platform, roomId)] ?? 'auto';
  }

  /// 循环切换某房间覆盖并持久化，返回新值。
  static String cycleOverride(String platform, String roomId) {
    final map = _overrides();
    final key = roomKey(platform, roomId);
    final next = _cycleOrder[(_cycleOrder.indexOf(map[key] ?? 'auto') + 1) % _cycleOrder.length];
    if (next == 'auto') {
      map.remove(key);
    } else {
      map[key] = next;
    }
    SettingsService.to.player.roomOrientationOverridesRaw.v = jsonEncode(map);
    return next;
  }

  /// 进入全屏时的目标方向：'landscape' | 'portrait'。
  static String resolveFullscreenOrientation({required String platform, required String roomId}) {
    final override = overrideFor(platform, roomId);
    if (override == 'portrait') return 'portrait';
    if (override == 'landscape') return 'landscape';

    switch (SettingsService.to.player.portraitFullscreenPolicy.v) {
      case 'followSystem':
        return systemIsPortrait() ? 'portrait' : 'landscape';
      case 'followSource':
        // 播放器已有的竖屏源信号（playerManager.isVerticalVideo，解码宽高 h>=w）
        final vertical = GlobalPlayerService.instance.playerManager.isVerticalVideo.value;
        return vertical ? 'portrait' : 'landscape';
      default:
        // 默认策略：竖屏源 + 手机 → 竖屏全屏（点全屏直接竖持观看）；
        // 平板保持横屏全屏、竖屏内容居中显示（横持看竖屏的既有习惯）。
        final vertical = GlobalPlayerService.instance.playerManager.isVerticalVideo.value;
        if (vertical && isPhoneSize) return 'portrait';
        return 'landscape';
    }
  }

  /// 当前窗口是否处于竖屏方向（physicalSize 随设备旋转实时变化）。
  static bool systemIsPortrait() {
    try {
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      return view.physicalSize.height > view.physicalSize.width;
    } catch (_) {
      return false;
    }
  }

  /// 手机 vs 平板：按物理对角线英寸判断（旋转/全屏都不改变对角线）。
  /// 阈值 6.5 英寸：手机（≤6.7" 主流在 6.5 内的 dpr 下约 ≤6.4"）判手机，
  /// 平板（≥8"）判平板。小米平板5（11"）≈6.9"、红米手机 6.6" 屏 ≈6.3"，
  /// 短边 dp 判定会把 11 寸平板误判成手机，故用对角线。
  static bool get isPhoneSize {
    try {
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      final dpr = view.devicePixelRatio;
      final size = view.physicalSize;
      if (dpr <= 0 || size.width <= 0 || size.height <= 0) return false;
      final diagonalInches = math.sqrt(
        size.width * size.width + size.height * size.height,
      ) / dpr / 160;
      return diagonalInches < 6.5;
    } catch (_) {
      return false;
    }
  }

  /// 源方向枚举快捷读取（对齐上游 VideoSourceOrientation 语义）。
  static VideoSourceOrientation get sourceOrientation {
    final vertical = GlobalPlayerService.instance.playerManager.isVerticalVideo.value;
    return vertical ? VideoSourceOrientation.portrait : VideoSourceOrientation.landscape;
  }
}
