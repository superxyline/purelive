import 'package:remixicon/remixicon.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/account/account_controller.dart';
import 'package:pure_live/common/services/settings/bilibili_account_service.dart';
import 'package:pure_live/common/services/follow_sync_service.dart';

class AccountPage extends GetView<AccountController> {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cookie = controller.cookie;

    return Scaffold(
      appBar: AppBar(title: Text(i18n('third_party_auth'))),
      body: ListView(
        physics: const BouncingScrollPhysics(),
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
                title: i18n("site_bilibili"),
                subtitle: isLogined ? accountName : i18n("not_logged_in"),
                isLogined: isLogined,
                onSync: isLogined ? _syncBilibili : null,
                onTap: () => isLogined ? _showLogoutDialog(context) : controller.bilibiliTap(),
              );
            }),

            Obx(() {
              final isLogined = cookie.huyaCookie.v.isNotEmpty;
              return _buildAccountTile(
                context,
                logo: 'assets/images/huya.png',
                title: i18n("site_huya"),
                subtitle: isLogined ? i18n("logined") : i18n("set_cookie"),
                isLogined: isLogined,
                onSync: isLogined ? _syncHuya : null,
                onTap: () => isLogined
                    ? _showPlatformLogoutDialog(context, () => cookie.huyaCookie.v = "")
                    : controller.huyaTap(),
              );
            }),

            Obx(() {
              final isLogined = cookie.douyinCookie.v.isNotEmpty;
              return _buildAccountTile(
                context,
                logo: 'assets/images/douyin.png',
                title: i18n("site_douyin"),
                subtitle: isLogined
                    ? controller.douyinNickName.value.isNotEmpty
                          ? controller.douyinNickName.value
                          : i18n("logined")
                    : i18n("set_cookie"),
                isLogined: isLogined,
                onTap: () => isLogined
                    ? _showPlatformLogoutDialog(context, () => cookie.douyinCookie.v = "")
                    : Get.toNamed(RoutePath.kDouyinCookie),
              );
            }),

            Obx(() {
              final isLogined = cookie.douyuCookie.v.isNotEmpty;
              return _buildAccountTile(
                context,
                logo: 'assets/images/douyu.png',
                title: i18n("site_douyu"),
                subtitle: isLogined ? i18n("logined") : i18n("set_cookie"),
                isLogined: isLogined,
                onSync: isLogined ? _syncDouyu : null,
                onTap: () => isLogined
                    ? _showPlatformLogoutDialog(context, () => cookie.douyuCookie.v = "")
                    : controller.douyuTap(),
              );
            }),
          ]),
          const SizedBox(height: 32),
        ],
      ),
    );
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
  }) {
    final theme = Theme.of(context);
    return ListTile(
      enabled: isEnabled,
      leading: Image.asset(logo, width: 24, height: 24),
      title: Text(
        title,
        style: AppTextStyles.t15.copyWith(fontWeight: FontWeight.w600, color: isEnabled ? null : theme.disabledColor),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          subtitle,
          style: AppTextStyles.t12.copyWith(
            color: isLogined ? theme.colorScheme.primary : theme.hintColor.withValues(alpha: 0.75),
            fontWeight: isLogined ? FontWeight.w500 : FontWeight.normal,
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
                  InkWell(
                    onTap: onSync,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Remix.refresh_line, color: theme.colorScheme.primary, size: 15),
                          const SizedBox(width: 3),
                          Text(
                            i18n("sync_short"),
                            style: AppTextStyles.t12.copyWith(color: theme.colorScheme.primary),
                          ),
                        ],
                      ),
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

  void _syncBilibili() {
    FollowSyncService.runAndShowResult(
      task: FollowSyncService.syncBilibili,
      loadingMsg: i18n("follow_sync_loading_bilibili"),
    );
  }

  void _syncDouyu() {
    FollowSyncService.runAndShowResult(
      task: FollowSyncService.syncDouyu,
      loadingMsg: i18n("follow_sync_loading_douyu"),
    );
  }

  void _syncHuya() {
    FollowSyncService.runAndShowResult(
      task: FollowSyncService.syncHuya,
      loadingMsg: i18n("follow_sync_loading_huya"),
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
