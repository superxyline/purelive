import 'package:flutter/services.dart';
import 'package:pure_live/common/global/platform_utils.dart';

/// Android 16（API 36）起，应用访问局域网设备（NAS、电脑代理）必须先拿到
/// `ACCESS_LOCAL_NETWORK` 运行时权限；没有它时系统会直接拒绝连接，且抛出的只是
/// 普通的连接失败，从日志里根本看不出是权限问题。
///
/// 目标 SDK 已经是 37，所以这里在"保存 NAS 地址 / 启用局域网代理"这类明确的
/// 局域网动作前申请一次，避免用户升级系统后发现同步和代理莫名失效。
class LocalNetworkPermission {
  LocalNetworkPermission._();

  static const MethodChannel _channel = MethodChannel('pure_live/local_network');

  static bool _requested = false;
  static bool _granted = false;

  /// 已授权返回 true；未授权时会弹出系统授权框并返回 false（不阻塞调用方）。
  static Future<bool> ensure() async {
    if (!PlatformUtils.isAndroid) return true;
    if (_requested) return _granted;
    _requested = true;
    try {
      _granted = await _channel.invokeMethod<bool>('ensure') ?? true;
    } catch (_) {
      // 通道不可用（旧系统/桌面/测试环境）视为已授权
      _granted = true;
    }
    return _granted;
  }

  /// 只查询当前状态，不弹框。
  static Future<bool> isGranted() async {
    if (!PlatformUtils.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('granted') ?? true;
    } catch (_) {
      return true;
    }
  }
}
