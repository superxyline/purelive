import 'package:pure_live/common/index.dart';
import 'package:remixicon/remixicon.dart';

/// 定制版特色功能介绍（关于页"功能介绍"入口的二级页面）
class FeaturesPage extends StatelessWidget {
  const FeaturesPage({super.key});

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
    (icon: Remix.logout_box_r_line, title: '退出方式', desc: '支持最小化到后台继续播放或直接退出'),
    (icon: Remix.user_3_line, title: '账号关注同步', desc: '登录 B站 / 斗鱼 / 虎牙 / 抖音后，一键把账号关注同步到本地'),
    (icon: Remix.bar_chart_grouped_line, title: '观看统计', desc: '本地累计观看时长，近 7 天趋势与最常观看主播'),
    (icon: Remix.information_line, title: '直播间信息', desc: '直播间菜单开启后悬浮显示清晰度 / 分辨率 / 音频码率'),
    (icon: Remix.layout_bottom_2_line, title: '桌面快捷方式', desc: '长按图标直达最近三个直播间与赛事中心'),
    (icon: Remix.fire_line, title: 'CS 热度筛选', desc: '赛事页默认选中当前热度最高的 CS 赛事，不错过焦点战'),
  ];

  static int get featureCount => _features.length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(i18n('features'))),
      body: ListView.builder(
        physics: const PureLiveScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: _features.length,
        itemBuilder: (context, index) {
          final f = _features[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: Icon(f.icon, color: theme.colorScheme.primary, size: 22),
                title: Text(f.title, style: AppTextStyles.t15.copyWith(fontWeight: FontWeight.w600, height: 1.2)),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    f.desc,
                    style: AppTextStyles.t12.copyWith(
                      color: theme.hintColor.withValues(alpha: 0.75),
                      height: 1.3,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
