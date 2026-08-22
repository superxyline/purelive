import 'package:pure_live/common/index.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:remixicon/remixicon.dart'; // 🌟 Imported Remix Icons pack

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  static const String kProjectUrl = 'https://gitee.com/superxyline';
  String _version = '';
  /// 定制版特色功能介绍
  static const List<({IconData icon, String title, String desc})> _features = [
    (icon: Remix.apps_2_line, title: '四平台聚合', desc: '专注哔哩哔哩 / 斗鱼 / 虎牙 / 抖音四大直播平台'),
    (icon: Remix.heart_3_line, title: '关注三态页签', desc: '已开播 / 未开播 / 已关注三页签，已关注页纯净卡片展示'),
    (icon: Remix.time_line, title: '开播时长角标', desc: '关注列表实时显示主播已开播时长，可一键开关'),
    (icon: Remix.trophy_line, title: '赛事中心', desc: 'CS / LOL / VALORANT 赛程与赛果，支持关注比赛与筛选'),
    (icon: Remix.magic_line, title: '醒目留言', desc: 'B站 SuperChat 弹幕卡片展示与全屏醒目留言弹窗'),
    (icon: Remix.send_plane_line, title: '真实发送弹幕', desc: '登录 B站后可真实发送弹幕，不再只是本地回显'),
    (icon: Remix.layout_grid_line, title: '双开观看', desc: '副窗口同时观看两场直播，小窗可拖动缩放、点击互换主副'),
    (icon: Remix.picture_in_picture_2_line, title: 'PiP 小窗弹幕', desc: '悬浮小窗播放时继续看弹幕，样式可自定义'),
    (icon: Remix.emotion_line, title: '本地互动', desc: '本地用户资料、平台礼物、等级与经验经济体系'),
    (icon: Remix.shield_keyhole_line, title: '本地数据加密', desc: '设置与关注数据 AES + 系统密钥加密存储'),
    (icon: Remix.phone_line, title: '横竖屏适配', desc: '平板横屏观看，手机全屏/竖屏智能切换'),
    (icon: Remix.bar_chart_line, title: '观看数据口径', desc: '热度 / 真实在线人数按平台自由切换'),
    (icon: Remix.cloud_line, title: '备份与传输', desc: 'WebDAV 云端备份恢复，局域网扫码一键同步'),
    (icon: Remix.translate, title: '多语言', desc: '简体中文 / English 自由切换'),
    (icon: Remix.palette_line, title: '主题定制', desc: '明暗模式、主题色、动态取色、加载动画'),
    (icon: Remix.font_size, title: '字体与文字', desc: '字体库下载管理、字号精细调节、全局文字缩放'),
    (icon: Remix.chat_1_line, title: '弹幕深度定制', desc: '弹幕模板、位置、样式、速度、描边、透明度与手势互动'),
    (icon: Remix.play_circle_line, title: '播放器内核', desc: '多内核切换、首选清晰度、后台播放与悬浮窗'),
    (icon: Remix.star_line, title: '关注管理', desc: '标签分组、自动刷新、缩略图刷新与紧凑模式'),
    (icon: Remix.menu_line, title: '导航自定义', desc: '底部页签排序与显隐自由配置'),
    (icon: Remix.global_line, title: '网络代理', desc: '应用与播放器独立代理设置'),
    (icon: Remix.tools_line, title: '工具箱', desc: '剪贴板链接识别、直播源解析'),
    (icon: Remix.login_box_line, title: '多端网页登录', desc: 'B站 / 斗鱼 / 虎牙 / 抖音网页登录'),
    (icon: Remix.logout_box_r_line, title: '退出方式', desc: '桌面端支持最小化到后台或直接退出'),
  ];

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _version = info.version);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        physics: const PureLiveScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: <Widget>[
          Center(
            child: Column(
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 1000),
                  curve: Curves.elasticOut,
                  builder: (context, value, child) {
                    return Transform.scale(scale: value, child: child);
                  },
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.08), width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.primary.withValues(alpha: 0.06),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Image.asset('assets/icons/icon.png', fit: BoxFit.contain),
                  ),
                ),

                const SizedBox(height: 18),
                Text(
                  i18n("app_name"),
                  style: AppTextStyles.t18.copyWith(fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.dividerColor.withValues(alpha: 0.05), width: 0.5),
                  ),
                  child: Text(
                    'v$_version',
                    style: AppTextStyles.t11.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
              ],
            ),
          ),
          context.buildGroupTitle(i18n("features")),
          const SizedBox(height: 8),
          context.buildModernCard([
            for (final f in _features)
              buildTile(
                icon: f.icon,
                title: f.title,
                subtitle: f.desc,
                isLong: true,
              ),
          ]),
          const SizedBox(height: 24),
          context.buildGroupTitle(i18n("about")),
          const SizedBox(height: 8),
          context.buildModernCard([
            context.buildTile(icon: Remix.shield_user_line, title: i18n("license"), onTap: openLicensePage),
          ]),
          const SizedBox(height: 24),
          context.buildGroupTitle(i18n("project")),
          const SizedBox(height: 8),
          context.buildModernCard([
            context.buildTile(
              icon: Remix.code_s_slash_line,
              title: i18n("project_page"),
              subtitle: kProjectUrl,
              isLong: true,
              onTap: () {
                launchUrl(Uri.parse(kProjectUrl), mode: LaunchMode.externalApplication);
              },
            ),
            buildTile(
              icon: Remix.error_warning_line,
              title: i18n("project_alert"),
              subtitle: i18n("app_legalese"),
              isLong: true,
              iconColor: theme.colorScheme.error,
            ),
          ]),
        ],
      ),
    );
  }

  Widget buildTile({
    required String title,
    IconData? icon,
    String? subtitle,
    VoidCallback? onTap,
    Color? iconColor,
    Color? subtitleColor,
    Widget? trailing,
    bool isLong = false,
  }) {
    final theme = Get.theme;
    final bool hasSubtitle = subtitle != null && subtitle.isNotEmpty;

    return ListTile(
      leading: null,
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 3, right: 12),
              child: Icon(icon, color: iconColor ?? theme.colorScheme.primary, size: 22),
            ),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: AppTextStyles.t15.copyWith(fontWeight: FontWeight.w600, height: 1.2)),
                if (hasSubtitle) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      subtitle,
                      style: AppTextStyles.t12.copyWith(
                        color: subtitleColor ?? theme.hintColor.withValues(alpha: 0.75),
                        height: 1.3,
                      ),
                      maxLines: isLong ? null : 1,
                      overflow: isLong ? TextOverflow.visible : TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      trailing:
          trailing ??
          (onTap != null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(Icons.chevron_right_rounded, color: theme.hintColor.withValues(alpha: 0.4), size: 20),
                    ),
                  ],
                )
              : null),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    );
  }

  void openLicensePage() {
    showLicensePage(
      context: Get.context!,
      applicationName: i18n("app_name"),
      applicationLegalese: i18n("app_legalese"),
      applicationVersion: _version,
      useRootNavigator: true,
      applicationIcon: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(width: 60, child: Center(child: Image.asset('assets/icons/icon.png'))),
      ),
    );
  }
}
