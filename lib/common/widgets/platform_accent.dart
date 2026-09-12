import 'package:flutter/material.dart';
import 'package:pure_live/core/sites.dart';

/// 平台品牌色表：供卡片角标、页签点缀等 UI 使用。
/// 与本地互动礼包（LocalPlatformPack.accentColor）保持同一套色值。
class PlatformAccent {
  const PlatformAccent._();

  static const Map<String, Color> _colors = {
    Sites.bilibiliSite: Color(0xFF00AEEC),
    Sites.douyuSite: Color(0xFFFF6A00),
    Sites.huyaSite: Color(0xFFFF9800),
    Sites.douyinSite: Color(0xFFFE2C55),
    Sites.kuaishouSite: Color(0xFFFF7900),
  };

  static const Color fallback = Color(0xFF607D8B);

  static Color of(String? platform) => _colors[platform?.trim().toLowerCase()] ?? fallback;

  /// 平台显示名（取 Sites 注册名），未知平台返回空串。
  static String displayName(String? platform) {
    final id = platform?.trim().toLowerCase() ?? '';
    if (id.isEmpty) return '';
    try {
      return Sites.of(id).name;
    } catch (_) {
      return '';
    }
  }
}

/// 平台页签文字：选中时用平台品牌色加粗，未选中继承主题样式。
/// 用于热门/关注页的平台 TabBar，强化多平台聚合的辨识度。
class PlatformTab extends StatelessWidget {
  const PlatformTab({
    super.key,
    required this.siteId,
    required this.label,
    required this.tabController,
    required this.index,
  });

  final String siteId;
  final String label;
  final TabController tabController;
  final int index;

  @override
  Widget build(BuildContext context) {
    final accent = PlatformAccent.of(siteId);
    return AnimatedBuilder(
      animation: tabController,
      builder: (context, _) {
        final selected = tabController.index == index;
        return Text(
          label,
          style: TextStyle(
            color: selected ? accent : null,
            fontWeight: selected ? FontWeight.w700 : null,
          ),
        );
      },
    );
  }
}
