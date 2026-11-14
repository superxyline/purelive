import 'dart:async';

import 'package:flutter/services.dart';
import 'package:pure_live/get/get.dart';

class DisplayModeInfo {
  const DisplayModeInfo({
    required this.enabled,
    required this.currentRefreshRate,
    required this.maxRefreshRate,
    required this.preferredRefreshRate,
    required this.supportedRefreshRates,
    this.requestedRefreshRate,
    this.displayId,
    this.width,
    this.height,
  });

  final bool enabled;
  final double currentRefreshRate;
  final double maxRefreshRate;
  final double preferredRefreshRate;
  final List<double> supportedRefreshRates;
  final double? requestedRefreshRate;
  final int? displayId;
  final int? width;
  final int? height;

  factory DisplayModeInfo.fromMap(Map<dynamic, dynamic> map) {
    double number(String key, [double fallback = 0]) {
      final value = map[key];
      return value is num ? value.toDouble() : fallback;
    }

    final rates = (map['supportedRefreshRates'] as List<dynamic>? ?? const [])
        .whereType<num>()
        .map((value) => value.toDouble())
        .toList(growable: false);

    return DisplayModeInfo(
      enabled: map['enabled'] == true,
      currentRefreshRate: number('currentRefreshRate'),
      maxRefreshRate: number('maxRefreshRate'),
      preferredRefreshRate: number('preferredRefreshRate'),
      supportedRefreshRates: rates,
      requestedRefreshRate: map['requestedRefreshRate'] is num ? number('requestedRefreshRate') : null,
      displayId: (map['displayId'] as num?)?.toInt(),
      width: (map['width'] as num?)?.toInt(),
      height: (map['height'] as num?)?.toInt(),
    );
  }
}

class DisplayModeService {
  DisplayModeService._();

  static const MethodChannel _channel = MethodChannel('pure_live/display_mode');
  static final Rx<DisplayModeInfo?> info = Rx<DisplayModeInfo?>(null);
  static bool _handlerInstalled = false;

  static void _ensureHandler() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'displayModeChanged' || call.arguments is! Map) return;
      info.value = DisplayModeInfo.fromMap(Map<dynamic, dynamic>.from(call.arguments as Map));
    });
  }

  /// 最近一次的全屏状态与用户开关，避免两个调用方互相依赖。
  static bool _fullscreen = false;
  static bool _followSetting = true;

  /// 全屏状态变化（由 GlobalPlayerState 调用）
  static void updateFullscreen(bool value) {
    _fullscreen = value;
    unawaited(applyEffectiveRefreshRate(fullscreen: value, followSetting: _followSetting));
  }

  /// 设置开关变化（由 AppSettingsController 调用）
  static void updateFollowSetting(bool value) {
    _followSetting = value;
    unawaited(applyEffectiveRefreshRate(fullscreen: _fullscreen, followSetting: value));
  }

  /// 统一刷新率策略：用户开启高刷时，**非全屏页面**（首页、列表、设置页、半屏小窗）
  /// 用屏幕最高刷新率保证滑动流畅；**全屏直播间**固定降到接近 60Hz 省电
  /// （直播流一般只有 60 帧，高刷只会白耗电）。用户关闭高刷则全程接近 60Hz。
  static Future<DisplayModeInfo?> applyEffectiveRefreshRate({
    required bool fullscreen,
    required bool followSetting,
  }) {
    return setHighRefreshRate(!fullscreen && followSetting);
  }

  static Future<DisplayModeInfo?> setHighRefreshRate(bool enabled) async {
    _ensureHandler();
    try {
      final result = await _channel.invokeMapMethod<dynamic, dynamic>('setHighRefreshRate', {'enabled': enabled});
      if (result == null) return null;
      final parsed = DisplayModeInfo.fromMap(result);
      info.value = parsed;
      return parsed;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static Future<DisplayModeInfo?> refreshInfo() async {
    _ensureHandler();
    try {
      final result = await _channel.invokeMapMethod<dynamic, dynamic>('getDisplayModeInfo');
      if (result == null) return null;
      final parsed = DisplayModeInfo.fromMap(result);
      info.value = parsed;
      return parsed;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
