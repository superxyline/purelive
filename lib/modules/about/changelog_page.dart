import 'package:pure_live/common/index.dart';

/// 更新日志页面，与关于页样式保持一致。
class ChangelogPage extends StatelessWidget {
  const ChangelogPage({super.key});

  static const List<({String version, List<String> items})> _changelog = [
    (
      version: '1.1.0（构建号 25）',
      items: [
        '新增"赛事"首页标签：展示从昨天到 7 天后的电竞赛事日程，支持按日期分组展示',
        '赛事数据源（实测打通）：CS2 使用完美世界电竞官方数据中心接口（HMAC 签名），英雄联盟、瓦罗兰特使用 Riot 官方赛事官网赛程数据',
        '赛事页支持三级筛选：游戏（全部/英雄联盟/Dota2/CS/瓦罗兰特）、日期（昨天~7 天后，点某天只看当天）、赛事名（当前游戏下的赛事列表）',
        '修复队伍队标不显示：队标 URL 明文 http 自动转 https，并携带防盗链 Referer 请求头',
        '修复赛事页加载后灰屏：游戏筛选条 GetX 订阅问题（Rx 访问需在 Obx 顶层）',
        '修复赛事卡片对齐：阶段名（如 Playoffs）与中间的时间/比分同列居中显示，不再错位',
        '修复未开始比赛时间/阶段名偏左：中间列内容用 Center 包裹，确保时间位于卡片正中（两个队标正中间）',
        '修复 CS 即将开始的比赛误显示 LIVE：完美世界接口未开始比赛状态为 2，改为按时间窗口判断状态（未开始/进行中/已结束）',
        '下拉刷新改为后台刷新：保留当前列表内容，新数据加载完成后自动覆盖，不再整页变加载圈',
        'Dota2 赛事数据源暂未接入（完美世界 web 端无 Dota2 赛事接口），筛选时显示占位提示，待后续方案',
      ],
    ),
    (
      version: '1.0.0（构建号 24）',
      items: [
        '修复从搜索进入直播间后返回键失效：输入法状态残留会拦截返回键，进入直播间前主动断开输入法连接，播放器键盘层接管返回键（与左上角返回箭头同一路由，全屏时先退全屏再退直播间）',
        '修复直播间音量键失效：物理音量键在直播间无反应的问题，播放器键盘层接管音量键，自行调整系统音量并同步播放器、弹出音量条',
        'Android 层返回键兜底：统一返回入口直通 Flutter 路由，兼容 MIUI 返回键双路径，防重复退出',
        '修复直播间系统返回键失效：移除播放器控制条强制焦点抢占（autofocus）',
        '修复全屏退出后返回键偶发失灵、进入直播间加载中返回偶发闪退',
        '音量优化：进直播间不再闪现音量条；房间记忆音量真正生效；修复音量条提示不显示',
        '物理音量键同步：按音量键同步调整播放器音量并记忆该房间音量（静音时保持静音）',
        '双开副窗口支持双指捏合缩放：中心锚点、16:9 联动，宽度 130~600；单指仍可拖动位置',
        '双开小窗放大 1.5 倍、可自由拖动；新增双开观看（主+小窗，静音小窗可互换主副）',
        '修复多平台搜索失败：B站改用 WBI 签名接口规避风控；斗鱼改用稳定 Cookie 并给出风控提示；抖音搜索需登录并明确提示',
        '关注页新增"已开播时长"角标（B站/斗鱼/虎牙/抖音）与"已关注"标签；新增"显示开播时长"开关',
        '新增跨端数据传输：备份页可扫码发送/接收关注与登录数据',
        '新增多平台关注同步：登录 B站/斗鱼/虎牙后可一键同步平台关注到收藏（自动去重、只增不删）',
        '新增斗鱼/虎牙网页登录（WebView 内嵌 + Cookie 抓取）；虎牙弹幕协议修复',
        'B站新增醒目留言（SC）显示、全屏 SC 弹层、弹幕发送',
        '全面屏手势返回恢复稳定；手机全屏自动横屏、退出恢复竖屏，平板全程横屏',
        '移除历史记录与桌面端支持（专注 Android/Android TV）；GetX 改用官方 pub 包、抖音签名 JS 抽离等优化',
      ],
    ),
    (
      version: '0.1.6（构建号 12）',
      items: [
        '修复全面屏手势返回：普通状态交还系统原生返回，仅在全屏/半屏/画中画等需要拦截的状态由应用先处理，简化返回处理链路',
        '主界面左上角按钮直达设置页',
        '关于入口移入设置页底部；移除历史记录功能（页面、控制器、路由及记录逻辑）',
        '设置页菜单重组：刷新、导航栏显示、平台显示与授权、自定义网络代理并入通用设置，播放器内核并入视频设置',
      ],
    ),
    (
      version: '0.1.5.3（构建号 11）',
      items: [
        '移除内置苹果字体，改用系统默认字体，安装包更小',
        '直播间右上角菜单文字垂直对齐；投屏按钮移至右上角菜单并直接投当前直播地址',
        '关于页项目声明与开源许可证更新，新增更新日志入口',
      ],
    ),
    (
      version: '0.1.5.2（构建号 10）',
      items: [
        '新增 B站直播间弹幕发送：播放器底部控制条内置输入框（与弹幕开关/设置同排，随控制条自动隐藏），发送纯文本弹幕，颜色与官方 APP 一致',
        '修复全屏播放时返回键退出失灵的问题',
      ],
    ),
    (
      version: '0.1.5.1（构建号 9）',
      items: ['新增 B站全屏 SC 弹层：全屏播放时醒目留言在屏幕左下角弹出，按 SC 有效时间自动消失'],
    ),
    (
      version: '0.1.5（构建号 8）',
      items: [
        '新增 B站醒目留言（SC）显示：弹幕列表以 SC 卡片展示，进房自动加载历史醒目留言',
        '弹幕设置新增"显示醒目留言"开关（默认开启）',
      ],
    ),
    (
      version: '0.1.4.2（构建号 7）',
      items: ['修复手机/平板横竖屏切换：手机进全屏自动横屏、退出恢复竖屏，平板全程横屏平板模式'],
    ),
    (
      version: '0.1.4.1（构建号 6）',
      items: ['移除 Windows / macOS / Linux 桌面端支持，专注 Android（含 Android TV）'],
    ),
    (
      version: '0.1.4（构建号 5）',
      items: [
        '修复退出直播间后残留后台音频的问题',
        'GetX 改用官方 pub 包、抖音签名 JS 抽离、JS 运行时复用',
        '依赖升级与整体优化',
      ],
    ),
    (
      version: '0.1.3 及更早版本',
      items: [
        '移除应用内更新、IPTV/M3U、网易 CC、快手、直播录制、Firebase 登录',
        '安全加固：独立签名密钥、本地数据加密、备份脱敏、权限精简、默认仅 HTTPS',
        'APK 体积优化与代码结构整理',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dotColor = theme.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(title: Text(i18n('update_log'))),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          for (final entry in _changelog) ...[
            context.buildGroupTitle(entry.version),
            const SizedBox(height: 8),
            context.buildModernCard([
              for (final item in entry.items)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 9,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 7),
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: dotColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item,
                          style: AppTextStyles.t13.copyWith(
                            height: 1.45,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.88,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ]),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }
}
