import 'package:pure_live/common/index.dart';

/// 更新日志页面，与关于页样式保持一致。
class ChangelogPage extends StatelessWidget {
  const ChangelogPage({super.key});

  static const List<({String version, List<String> items})> _changelog = [
    (
      version: '0.1.5.2（构建号 10）',
      items: [
        '新增 B站直播间弹幕发送：播放器底部控制条内置输入框（与弹幕开关/设置同排，随控制条自动隐藏），发送纯文本弹幕，颜色与官方 APP 一致',
        '修复全屏播放时返回键退出失灵的问题',
      ],
    ),
    (
      version: '0.1.5.1（构建号 9）',
      items: [
        '新增 B站全屏 SC 弹层：全屏播放时醒目留言在屏幕左下角弹出，按 SC 有效时间自动消失',
      ],
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
      items: [
        '修复手机/平板横竖屏切换：手机进全屏自动横屏、退出恢复竖屏，平板全程横屏平板模式',
      ],
    ),
    (
      version: '0.1.4.1（构建号 6）',
      items: [
        '移除 Windows / macOS / Linux 桌面端支持，专注 Android（含 Android TV）',
      ],
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
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 7),
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item,
                          style: AppTextStyles.t13.copyWith(
                            height: 1.45,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.88),
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
