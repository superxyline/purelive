import 'dart:async';

import 'package:remixicon/remixicon.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/account/account_controller.dart';
import 'package:pure_live/core/site/douyu/douyu_utils.dart';
import 'package:pure_live/common/services/settings/bilibili_account_service.dart';

class AccountPage extends GetView<AccountController> {
  const AccountPage({super.key});

  /// 虎牙昵称懒查防重标志：一个 App 生命周期内只补查一次（登录时会主动查）。
  static bool _huyaNickLazyFetched = false;

  @override
  Widget build(BuildContext context) {
    final cookie = controller.cookie;

    return Scaffold(
      appBar: AppBar(title: Text(i18n('third_party_auth'))),
      body: ListView(
        physics: const PureLiveScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          context.buildGroupTitle(i18n('third_party_auth')),
          context.buildModernCard([
            Obx(() {
              final isLogined = BiliBiliAccountService.instance.logined.v;
              final accountName = BiliBiliAccountService.instance.name.v;
              return _buildAccountTile(
                context,
                logo: 'assets/images/bilibili_2.png',
                platformId: 'bilibili',
                title: i18n("site_bilibili"),
                subtitle: isLogined ? accountName : i18n("not_logged_in"),
                isLogined: isLogined,
                onSync: () => FollowSyncService.runAndShowResult(
                  task: FollowSyncService.syncBilibili,
                  loadingMsg: i18n("follow_syncing"),
                ),
                onTap: () => isLogined ? _showLogoutDialog(context) : controller.bilibiliTap(),
              );
            }),

            Obx(() {
              final isLogined = cookie.huyaCookie.v.isNotEmpty;
              // 昵称懒查：存量登录没有存过昵称（hive 为空）时进页面补查一次，
              // 接口结果落 hive 后 Rx 变化会自动刷新显示；失败静默回退 UID。
              if (isLogined && cookie.huyaNick.v.isEmpty && !_huyaNickLazyFetched) {
                _huyaNickLazyFetched = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  unawaited(FollowSyncService.fetchHuyaSelfNick());
                });
              }
              return _buildAccountTile(
                context,
                logo: 'assets/images/huya.png',
                platformId: 'huya',
                title: i18n("site_huya"),
                subtitle: isLogined ? _accountLabel(cookie.huyaNick.v, cookie.huyaCookie.v, 'yyuid') : i18n("not_logged_in"),
                isLogined: isLogined,
                onSync: () => FollowSyncService.runAndShowResult(
                  task: FollowSyncService.syncHuya,
                  loadingMsg: i18n("follow_syncing"),
                ),
                onTap: () => isLogined
                    ? _showPlatformLogoutDialog(context, () => cookie.huyaCookie.v = "")
                    : _showLoginChoiceDialog(
                        context,
                        onWebLogin: () => Get.toNamed(RoutePath.kHuyaWebLogin),
                        onManual: () => Get.toNamed(RoutePath.kHuyaCookie),
                      ),
              );
            }),

            Obx(() {
              final isLogined = cookie.douyinCookie.v.isNotEmpty;
              return _buildAccountTile(
                context,
                logo: 'assets/images/douyin.png',
                platformId: 'douyin',
                title: i18n("site_douyin"),
                subtitle: isLogined
                    ? controller.douyinNickName.value.isNotEmpty
                          ? controller.douyinNickName.value
                          : i18n("logined")
                    : i18n("not_logged_in"),
                isLogined: isLogined,
                onSync: () => FollowSyncService.runAndShowResult(
                  task: FollowSyncService.syncDouyin,
                  loadingMsg: i18n("follow_syncing"),
                ),
                onTap: () => isLogined
                    ? _showPlatformLogoutDialog(context, () => cookie.douyinCookie.v = "")
                    : _showLoginChoiceDialog(
                        context,
                        onWebLogin: () => Get.toNamed(RoutePath.kDouyinWebLogin),
                        onManual: () => Get.toNamed(RoutePath.kDouyinCookie),
                      ),
              );
            }),

            Obx(() {
              final isLogined = cookie.kuaishouCookie.v.isNotEmpty;
              return _buildAccountTile(
                context,
                logo: 'assets/images/kuaishou.png',
                platformId: 'kuaishou',
                title: i18n("site_kuaishou"),
                subtitle: isLogined ? _accountLabel(cookie.kuaishouNick.v, cookie.kuaishouCookie.v, 'userId') : i18n("not_logged_in"),
                isLogined: isLogined,
                onSync: () => FollowSyncService.runAndShowResult(
                  task: FollowSyncService.syncKuaishou,
                  loadingMsg: i18n("follow_syncing"),
                ),
                onTap: () => isLogined
                    ? _showPlatformLogoutDialog(context, () => cookie.kuaishouCookie.v = "")
                    : _showLoginChoiceDialog(
                        context,
                        onWebLogin: () => Get.toNamed(RoutePath.kKuaishouWebLogin),
                        onManual: () => Get.toNamed(RoutePath.kKuaishouCookie),
                      ),
              );
            }),
            Obx(() {
              final isLogined = cookie.douyuCookie.v.isNotEmpty;
              // 斗鱼会话是有期限的（网页版 7 天、H5 版看 JWT），过期后只表现为
              // 「原画被降成蓝光4M」，所以这里直接显示昵称 + 剩余时间/续期状态。
              final douyuState = DouyuUtils.sessionState(cookie.douyuCookie.v);
              final douyuExpiry = DouyuUtils.sessionExpiry(
                cookie.douyuCookie.v,
                savedAt: DouyuUtils.storedSessionSavedAt(),
              );
              final douyuNick = DouyuUtils.accountNick(cookie.douyuCookie.v);
              final stateLabel = switch (douyuState) {
                DouyuSessionState.none => i18n("not_logged_in"),
                DouyuSessionState.guest => 'Cookie 无登录令牌（等同未登录）',
                DouyuSessionState.valid => _douyuValidLabel(cookie.douyuCookie.v, douyuExpiry),
                DouyuSessionState.expiredRefreshable => '登录已过期 · 下次播放会自动续期',
                DouyuSessionState.expired => '登录已过期 · 请重新登录',
              };
              final subtitle = douyuNick.isEmpty ? stateLabel : '$douyuNick · $stateLabel';
              return _buildAccountTile(
                context,
                logo: 'assets/images/douyu.png',
                platformId: 'douyu',
                title: i18n("site_douyu"),
                subtitle: subtitle,
                isLogined: isLogined,
                onSync: () => FollowSyncService.runAndShowResult(
                  task: FollowSyncService.syncDouyu,
                  loadingMsg: i18n("follow_syncing"),
                ),
                onTap: () => isLogined
                    ? _showPlatformLogoutDialog(context, () => cookie.douyuCookie.v = "")
                    : Get.toNamed(RoutePath.kDouyuWebLogin),
              );
            }),
          ]),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// 账号名展示：已存的昵称优先（虎牙 getUserProfile / 快手页面提取），
  /// 昵称为空回退 UID——至少能区分是哪个号，比统一的「已登录」信息量多。
  String _accountLabel(String nick, String cookie, String field) {
    final trimmed = nick.trim();
    return trimmed.isNotEmpty ? trimmed : _uidLabel(cookie, field);
  }

  /// 虎牙/快手的昵称要私有签名接口才能拿到，cookie 里只有账号 ID：
  /// 退化为显示 UID，至少能区分是哪个号，比统一的「已登录」信息量多。
  String _uidLabel(String cookie, String field) {
    final match = RegExp('(?:^|;)\\s*$field=(\\d+)').firstMatch(cookie);
    return match != null ? 'UID ${match.group(1)}' : i18n('logined');
  }

  /// 斗鱼登录剩余时间文案。
  String _douyuRemainingLabel(DateTime expiry) {
    final left = expiry.difference(DateTime.now());
    if (left.isNegative) return '已到期';
    if (left.inDays >= 1) return '剩余 ${left.inDays} 天';
    if (left.inHours >= 1) return '剩余 ${left.inHours} 小时';
    return '剩余 ${left.inMinutes} 分钟';
  }

  /// 斗鱼登录有效时的文案：有无续期密钥（LTP0+dy_did）表现完全不同——
  /// 有则到期前自动续、无限滚动；没有则到期必须重新扫码。
  String _douyuValidLabel(String cookie, DateTime? expiry) {
    final canRenew = DouyuUtils.canRefreshSession(cookie);
    if (expiry == null) return canRenew ? '已登录 · 可自动续期' : i18n("logined");
    final until = '至 ${_douyuExpiryTime(expiry)}';
    return canRenew ? '已登录 · 自动续期 $until' : '剩余 ${_douyuRemainingLabel(expiry)} · 到期需重新扫码';
  }

  /// 续期边界时间（本地时区 yyyy-MM-dd HH:mm）。
  String _douyuExpiryTime(DateTime expiry) {
    final local = expiry.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  Widget _buildAccountTile(
    BuildContext context, {
    required String logo,
    required String title,
    required String subtitle,
    required bool isLogined,
    required VoidCallback onTap,
    VoidCallback? onSync,
    bool isEnabled = true,
    String? platformId,
  }) {
    final theme = Theme.of(context);
    final accent = PlatformAccent.of(platformId);
    final isDark = theme.brightness == Brightness.dark;
    return ListTile(
      enabled: isEnabled,
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          // 登录态用平台色淡底衬托 logo，未登录弱化为中性底
          color: isLogined && isEnabled
              ? accent.withValues(alpha: isDark ? 0.22 : 0.13)
              : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Opacity(opacity: isLogined && isEnabled ? 1 : 0.5, child: Image.asset(logo, width: 24, height: 24)),
        ),
      ),
      title: Text(
        title,
        style: AppTextStyles.t15.copyWith(fontWeight: FontWeight.w600, color: isEnabled ? null : theme.disabledColor),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          subtitle,
          style: AppTextStyles.t12.copyWith(
            color: isLogined && isEnabled ? accent : theme.hintColor.withValues(alpha: 0.75),
            fontWeight: isLogined ? FontWeight.w600 : FontWeight.normal,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      trailing: isLogined
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onSync != null)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onSync,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Remix.refresh_line, color: theme.colorScheme.primary.withValues(alpha: 0.85), size: 18),
                    ),
                  ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Remix.logout_box_r_line, color: theme.colorScheme.error.withValues(alpha: 0.8), size: 18),
                  ),
                ),
              ],
            )
          : Icon(Icons.chevron_right_rounded, color: theme.hintColor.withValues(alpha: 0.4), size: 20),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    );
  }

  /// 未登录时选择登录方式：网页登录（自动取 cookie）或手动填写 cookie
  void _showLoginChoiceDialog(
    BuildContext context, {
    required VoidCallback onWebLogin,
    VoidCallback? onManual,
  }) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(i18n("choose_login_method")),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Remix.global_line, color: theme.colorScheme.primary),
              title: Text(i18n("web_login")),
              subtitle: Text(i18n("web_login_desc")),
              onTap: () {
                Navigator.pop(context);
                onWebLogin();
              },
            ),
            if (onManual != null)
              ListTile(
                leading: const Icon(Remix.clipboard_line),
                title: Text(i18n("manual_input")),
                subtitle: Text(i18n("set_cookie")),
                onTap: () {
                  Navigator.pop(context);
                  onManual();
                },
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(i18n("cancel"))),
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(i18n("logout")),
        content: Text(i18n("confirm_logout")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(i18n("cancel"))),
          TextButton(
            onPressed: () {
              BiliBiliAccountService.instance.logout();
              Navigator.pop(context);
            },
            child: Text(i18n("confirm"), style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showPlatformLogoutDialog(BuildContext context, VoidCallback onConfirm) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(i18n("logout")),
        content: Text(i18n("confirm_logout")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(i18n("cancel"))),
          TextButton(
            onPressed: () {
              onConfirm();
              Navigator.pop(context);
            },
            child: Text(i18n("confirm"), style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
