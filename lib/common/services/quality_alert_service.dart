import 'package:pure_live/common/index.dart';

/// 平台登录态降档告警。
///
/// 场景：本地已经存了该平台的登录 cookie，但取流时服务端仍把「最高清晰度」请求
/// 降成低档（斗鱼：原画 → 蓝光4M；B站：原画 10000 → 250）——这通常意味着 cookie
/// 已经过期，平台把请求当成匿名会话处理了。用户往往只会觉得"画面怎么不清晰"，
/// 很难意识到是登录态的问题。
///
/// 各站点在取流时一旦发现"请求最高档、服务端确认低档"且本地有该平台 cookie，
/// 就调用 [reportClamped]，这里统一做冷却与 toast 提醒。
class QualityAlertService extends GetxService {
  static QualityAlertService get to => Get.find();

  /// 同一平台的提醒冷却时间：换房间/换线路/切清晰度时不会反复弹。
  static const Duration cooldown = Duration(minutes: 10);

  final Map<String, DateTime> _lastAlertAt = {};

  /// 测试用：替换实际 toast 输出（默认走 [ToastUtil.show]）。
  @visibleForTesting
  void Function(String message)? toastOverride;

  /// [platform] 用 Sites 常量（douyu / bilibili …），[platformName] 为展示名。
  void reportClamped({
    required String platform,
    required String platformName,
    String requested = '最高清晰度',
    String actual = '较低档位',
  }) {
    final now = DateTime.now();
    final last = _lastAlertAt[platform];
    if (last != null && now.difference(last) < cooldown) return;
    _lastAlertAt[platform] = now;

    debugPrint('[quality-alert] $platform 降档: $requested -> $actual');
    final message = '$platformName最高清晰度被降级（$requested → $actual），登录态可能已失效，请到「我的 → 账号」重新登录';
    final show = toastOverride ?? ToastUtil.show;
    show(message);
  }

  /// 测试/退出登录后可清空冷却状态。
  void reset() => _lastAlertAt.clear();
}
