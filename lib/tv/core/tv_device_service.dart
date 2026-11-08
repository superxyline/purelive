import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// TV 设备检测：原生侧 `UiModeManager==TELEVISION` 或 leanback feature
/// 命中其一即判 TV。启动时取一次并缓存；无该通道（桌面/iOS）恒 false。
class TvDeviceService {
  TvDeviceService._();
  static const MethodChannel _channel = MethodChannel('pure_live/device_type');

  static bool? _cached;
  static void Function()? _menuKeyCallback;

  /// 注册 TV 遥控菜单键处理（Kotlin onKeyDown 直达，不依赖 Flutter 键映射）。
  /// 仅播放页注册；callback 为空时菜单键无动作。
  static void setMenuKeyHandler(void Function()? handler) => _menuKeyCallback = handler;

  static bool get isTv {
    if (_cached != null) return _cached!;
    // 同步 getter 里取不到异步结果：先按 false 兜底，
    // main 入口在 runApp 前 await init()，因此实际入口总是缓存值。
    return _cached ?? false;
  }

  /// 在 main() 里 runApp 之前调用一次。
  /// 带重试：个别电视冷启动早期通道偶发不可达，误判 false 会落到手机 UI。
  static Future<void> init() async {
    for (var attempt = 1; attempt <= 5; attempt++) {
      try {
        final result = await _channel.invokeMethod<bool>('isTv') ?? false;
        debugPrint('[TvDeviceService] attempt#$attempt isTv=$result');
        // false 结果也重试一次确认（排除通道偶发异常的中间态），
        // 连续一致才采信；命中 true 立即返回。
        if (result) {
          _cached = true;
          return;
        }
        if (attempt >= 2) {
          _cached = false;
          return;
        }
      } catch (e) {
        debugPrint('[TvDeviceService] attempt#$attempt error: $e');
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
    _cached = false;
  }
}
