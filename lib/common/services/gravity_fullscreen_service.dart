import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

import 'package:pure_live/common/index.dart';

/// 手机握持姿态（由加速度计的重力分量判定）。
enum DeviceTilt {
  /// 竖持：重力主要沿屏幕纵轴
  portrait,

  /// 横持：重力主要沿屏幕横轴
  landscape,

  /// 不确定：平放桌面、异常读数，或正处在横竖临界角（迟滞区）
  unknown,
}

/// 重力感应自动全屏的传感器层。
///
/// 只负责「读加速度计 → 判定稳定后的姿态变化 → 回调」，是否启用、当前是否全屏、
/// 进入/退出全屏的动作全部由播放页决定，避免本服务反向依赖播放模块。
///
/// 设计约束（2026-09-27 与用户确认）：
/// - 只认**姿态变化**：首次拿到的明确姿态只作基线，不触发（进直播间时已是横持不会立刻全屏）。
/// - **任何**全屏状态变化（手动点按钮、自动触发、进房间自动全屏）都刷新 10 秒冷却；
///   冷却结束后需要一次新的姿态变化才触发，不会因"当前恰好横持"就立刻弹回全屏。
/// - 平放桌面与临界角（约 45°）视为不确定，不触发。
///
/// 为什么必须读加速度计：全屏时 App 会 `SystemChrome.setPreferredOrientations`
/// 把方向锁死，`MediaQuery` / `physicalSize` 不再随真实握持变化，只有传感器能反映。
class GravityFullscreenService {
  GravityFullscreenService._();

  static final GravityFullscreenService instance = GravityFullscreenService._();

  factory GravityFullscreenService() => instance;

  /// 全屏状态变化后的冷却时长：期间忽略姿态变化
  static const Duration coolDown = Duration(seconds: 10);

  /// 新姿态需稳定这么久才认定，避免临界角来回抖动误触发
  static const Duration stableWindow = Duration(milliseconds: 400);

  /// 平放判定：归一化重力 z 分量超过该值视为平放桌面
  static const double _flatThreshold = 0.75;

  /// 迟滞区：横竖分量差小于该值时不改变判定
  static const double _hysteresis = 0.25;

  /// 总重力低于该值视为异常读数（自由落体 / 传感器未就绪）
  static const double _minGravity = 4.0;

  StreamSubscription<AccelerometerEvent>? _subscription;
  void Function(DeviceTilt tilt)? _onTiltChanged;

  DeviceTilt? _baseline;
  DeviceTilt? _pending;
  DateTime? _pendingSince;
  DateTime? _coolDownUntil;

  bool _running = false;

  bool get isRunning => _running;

  /// 设置开关（默认关闭）
  bool get isEnabled => SettingsService.to.player.gravityAutoFullscreen.v;

  /// 开始监听；重复调用会先停掉上一次。
  Future<void> start({required void Function(DeviceTilt tilt) onTiltChanged}) async {
    stop();
    _onTiltChanged = onTiltChanged;
    _baseline = null;
    _pending = null;
    _pendingSince = null;
    _coolDownUntil = null;
    _subscription = accelerometerEventStream(
      samplingPeriod: SensorInterval.normalInterval,
    ).listen(
      _onAccelerometer,
      onError: (_) => stop(),
      cancelOnError: true,
    );
    _running = true;
  }

  /// 停止监听并清空状态。
  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _onTiltChanged = null;
    _baseline = null;
    _pending = null;
    _pendingSince = null;
    _coolDownUntil = null;
    _running = false;
  }

  /// 全屏状态发生变化时调用：刷新 10 秒冷却并清空基线。
  void markFullscreenChanged() {
    _coolDownUntil = DateTime.now().add(coolDown);
    _pending = null;
    _pendingSince = null;
    _baseline = null;
  }

  bool _inCoolDown(DateTime now) {
    final until = _coolDownUntil;
    return until != null && now.isBefore(until);
  }

  void _onAccelerometer(AccelerometerEvent event) {
    final tilt = _classify(event);
    if (tilt == DeviceTilt.unknown) {
      _pending = null;
      _pendingSince = null;
      return;
    }

    // 首个明确姿态只作基线，不触发（"只认变化"）。
    if (_baseline == null) {
      _baseline = tilt;
      _pending = null;
      _pendingSince = null;
      return;
    }
    if (_baseline == tilt) {
      _pending = null;
      _pendingSince = null;
      return;
    }

    final now = DateTime.now();
    if (_pending != tilt) {
      _pending = tilt;
      _pendingSince = now;
      return;
    }
    final since = _pendingSince;
    if (since == null) {
      _pendingSince = now;
      return;
    }
    if (now.difference(since) < stableWindow) return;
    if (_inCoolDown(now)) return;

    _baseline = tilt;
    _pending = null;
    _pendingSince = null;
    _onTiltChanged?.call(tilt);
  }

  /// 由重力分量判定握持姿态，含平放与临界角迟滞处理。
  DeviceTilt _classify(AccelerometerEvent event) {
    final g = math.sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
    if (g < _minGravity) return DeviceTilt.unknown;

    final nx = event.x / g;
    final ny = event.y / g;
    final nz = event.z / g;

    // 屏幕朝上/朝下平放：横竖都谈不上，不触发
    if (nz.abs() >= _flatThreshold) return DeviceTilt.unknown;

    final portraitScore = ny.abs();
    final landscapeScore = nx.abs();
    // 迟滞区（约 45° 附近）：维持现状，避免临界角来回抖动
    if ((landscapeScore - portraitScore).abs() < _hysteresis) {
      return DeviceTilt.unknown;
    }
    return landscapeScore > portraitScore ? DeviceTilt.landscape : DeviceTilt.portrait;
  }
}
