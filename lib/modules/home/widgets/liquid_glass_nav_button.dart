import 'package:flutter/material.dart';
import 'package:flutter_liquid_glass/liquid_glass.dart';

/// 首页导航的液态玻璃按钮（单枚）。
///
/// 玻璃态使用 [LiquidGlassContainer]：其内置按压缩放（1 → 0.95）、悬停高光与
/// 视差动效，无需自行实现。选中态通过调整玻璃配置（更高不透明度 + 主题强调色
/// 基底）与内容色来体现；非选中态保持克制通透。
class LiquidGlassNavButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Color accent;

  /// 固定高度。包内 LiquidGlassEffect 的 Stack 含多个空 Container()，
  /// 在松高度约束下会撑满最大可用空间（把 bottomNavigationBar 撑成整屏），
  /// 必须用 tight 高度锁死。平板侧栏与手机底栏统一 72。
  final double height;

  const LiquidGlassNavButton({
    super.key,
    required this.icon,
    required this.label,
    this.selected = false,
    required this.accent,
    this.onTap,
    this.height = 72,
  });

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    final LiquidGlassConfig config = selected
        ? LiquidGlassConfig(
            baseColor: accent.withOpacity(0.35),
            opacity: 0.30,
            blurAmount: 16,
            refractionIntensity: 0.7,
            borderRadius: BorderRadius.circular(22),
            enableSpecularHighlight: true,
            enableParallax: true,
            parallaxIntensity: 0.12,
          )
        : LiquidGlassConfig(
            opacity: 0.12,
            blurAmount: 10,
            refractionIntensity: 0.5,
            borderRadius: BorderRadius.circular(22),
            enableParallax: true,
            parallaxIntensity: 0.10,
          );

    final Color contentColor = selected
        ? accent
        : (isDark ? Colors.white.withOpacity(0.85) : Colors.black87);

    return LiquidGlassContainer(
      onTap: onTap,
      config: config,
      height: height,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 24, color: contentColor),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: contentColor,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
