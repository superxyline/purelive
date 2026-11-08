import 'package:flutter/material.dart';

/// TV 模式视觉常量（对齐 pure_live_TV 实测设计，全部自写实现）。
///
/// - 深色固定：TV 上"跟随系统"一律解析为深色；
/// - 字号基准 1080p：物理高度不足时整体放大补偿（上限 1.6），
///   用法 `context.tvSp(18)`；
/// - 统一动画：聚焦 120ms easeOutCubic、失焦零时长（快速连按不留拖尾）。
class TvTheme {
  TvTheme._();

  // ---- 颜色 ----
  static const Color background = Color(0xFF121212);
  static const Color card = Color(0xFF1F1F1F);
  static const Color focusedCard = Color(0xFFFFFFFF);
  static const Color focusColor = Color(0xFF00A1FF);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xB3FFFFFF);
  static const Color subtleFill = Color(0x0FFFFFFF);
  static const Color divider = Color(0x1FFFFFFF);

  /// 聚焦光晕参数（focusColor @0.75、blur 18、spread 1.5）
  static List<BoxShadow> get focusGlow => [
        BoxShadow(
          color: focusColor.withValues(alpha: 0.75),
          blurRadius: 18,
          spreadRadius: 1.5,
        ),
      ];

  // ---- 几何 ----
  static const double cardRadius = 24;
  static const double panelRadius = 20;
  static const double dialogRadius = 12;

  /// 卡片网格：默认 6 列，间距 16；纵横比 1.0（封面约 16:9 + 信息区）
  static const int gridColumns = 4;
  static const double gridSpacing = 16;
  static const double gridChildAspectRatio = 1.0;

  // ---- 动画 ----
  static const Duration focusDuration = Duration(milliseconds: 120);
  static const Duration unfocusDuration = Duration.zero;
  static const Duration pageTransitionDuration = Duration(milliseconds: 250);
  static const Duration navExpandDuration = Duration(milliseconds: 150);

  static const double focusScale = 1.05;
  static const double pressedScale = 0.97;

  static const Curve focusCurve = Curves.easeOutCubic;

  static ThemeData themeData() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: Colors.transparent,
      colorScheme: base.colorScheme.copyWith(
        primary: focusColor,
        surface: card,
        onSurface: textPrimary,
      ),
      splashFactory: NoSplash.splashFactory,
    );
  }

  /// 全局背景：底色向 focusColor lerp 10% 的对角渐变
  static Widget scaffoldBackground({required Widget child}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [background, Color.lerp(background, focusColor, 0.10)!],
        ),
      ),
      child: child,
    );
  }
}

/// 缩放策略（单一基准，文字与几何同向，避免互相打架）：
/// - 几何 = 物理高 / 1080（clamp 0.7~1.6）：1080p=1.0、810p=0.75；
/// - 文字 = 几何 × 1.25 提升可读性（clamp 1.0~1.6）：
///   810p 下文字 0.94、几何 0.75，比例失衡可控。
double tvGeoScale(BuildContext context) {
  final height = MediaQuery.sizeOf(context).height;
  if (height <= 0) return 1.0;
  return (height / 1080).clamp(0.7, 1.6);
}

double tvTextScale(BuildContext context) {
  return (tvGeoScale(context) * 1.25).clamp(1.0, 1.6);
}

/// `context.tvSp(18)`：TV 字号（设计稿 1080p 基准 + 可读性提升）
extension TvTextScaleExt on BuildContext {
  double tvSp(double size) => size * tvTextScale(this);

  /// 几何尺寸按高度缩放
  double tvDp(double size) => size * tvGeoScale(this);
}
