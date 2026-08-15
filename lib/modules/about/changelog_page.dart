import 'package:pure_live/common/index.dart';

/// 更新日志页面，与关于页样式保持一致。
class ChangelogPage extends StatelessWidget {
  const ChangelogPage({super.key});

  static const List<({String version, List<String> items})> _changelog = [
    (version: '2.1.5（构建号 19）', items: ['双开副窗口放大至 1.5 倍：小窗更大更易看，默认停靠右下角、可自由拖动']),

    (
      version: '2.1.4（构建号 18）',
      items: [
        '双开小窗可拖动：副窗口支持按住拖动到任意位置（限定在播放页可视范围内），默认停靠右下角，不遮挡主画面与清晰度栏',
        '整窗轻点仍是互换主副，拖动与点击手势自动区分',
      ],
    ),

    (
      version: '2.1.3（构建号 17）',
      items: [
        '新增双开观看：播放页菜单"双开"选择一个副直播间，主+小窗同时观看（副窗口静音，音频始终来自主窗口）',
        '点副窗口互换主副：主窗口切到副房间出声，副窗口切回原主房间静音',
        '副窗口支持"换一个"替换副房间、"×"关闭退出双开',
        '选择面板提供 收藏 / 搜索 两种方式挑选副直播间（分区浏览待后续版本）',
      ],
    ),

    (
      version: '2.1.2（构建号 16）',
      items: [
        '关注页直播封面新增"已开播时长"角标：B站/斗鱼/虎牙/抖音正在直播的主播，封面左上角显示中文开播时长（精确到分钟，每分钟自动刷新）',
        '新增跨端数据传输：备份页"发送数据"扫码对方二维码，可将本机关注与登录数据完全覆盖到对方设备；"接收数据"生成二维码等待对方扫码',
        '角标优化：开播时长与热度值角标缩小为原来一半，时长角标移至封面左上角，窄屏卡片不再互相遮挡',
        '关注页新增"已关注"标签：列出全部关注主播（纯列表展示，不含热度/开播时长角标，无需刷新即可查看）',
        '修复虎牙开播时长不显示的问题（接口字段修正）',
        '修复B站开播时长不显示的问题（改用 room_init 接口获取开播时间）',
        '新增"显示开播时长"开关：设置 → 通用 可控制直播封面"已开播时长"角标的显示',
      ],
    ),
    (
      version: '2.1.1（构建号 15）',
      items: [
        '全新安装后的默认设置优化：开机动画默认关闭，首次启动直达首页',
        '弹幕默认显示优化：打开直播间弹幕速度默认为 100、透明度默认 70%、显示区域默认 70%',
      ],
    ),
    (
      version: '2.1.0（构建号 14）',
      items: [
        '新增多平台关注同步：账号页与 B站/斗鱼/虎牙 Cookie 设置页新增"同步关注主播"入口，可一键把平台关注的主播同步到应用收藏（按平台+房间号自动去重，只增不删）',
        'B站：通过关注接口分页拉取并批量解析直播间，保留开播状态',
        '斗鱼：通过斗鱼网页关注接口拉取（需登录 Cookie）',
        '虎牙：通过网页关注接口（TARS 协议）逐主播解析昵称/头像/房间号',
      ],
    ),
    (
      version: '2.0.0（构建号 13）',
      items: [
        '新增斗鱼网页登录：账户页支持网页内嵌登录（WebView）与手动设置 Cookie，登录态本地持久化并纳入备份恢复',
        '新增虎牙网页登录：账户页支持网页登录页内嵌登录，登录后自动抓取多域名 Cookie 并保存',
        '虎牙弹幕协议修复：同步上游心跳数据与加房数据结构，虎牙弹幕连接更稳定',
        '全屏交互优化：点击画面可切换控制栏显隐；弹幕输入框激活后点击画面可取消焦点并自动隐藏控制栏',
        '修复退出全屏后返回键偶发失灵、进入直播间加载中返回偶发闪退',
        '设置页菜单顺序调整：通用设置 → 视频设置 → 主题设置 → 数据管理 → 备份管理 → 关于',
        '首页收藏页移除"录播"标签；工具箱移除"支持解析列表"（快手/CC 相关文案清理）',
        '修复备份恢复时登录 Cookie 不生效的历史问题（B站/虎牙/抖音/斗鱼均正常恢复）',
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
