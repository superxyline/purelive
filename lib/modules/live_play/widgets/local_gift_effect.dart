import 'dart:math' as math;

import 'package:pure_live/common/index.dart';

/// 本地礼物全屏动效。
///
/// 根据 [LiveMessage.data] 中的 `anim` 字段渲染四类动效：
/// - `float`  ：图标弹出 + 上浮 + 环绕粒子（小礼物默认）
/// - `launch` ：火箭自底部升空（火箭类）
/// - `fly`    ：飞机横穿画面（飞机/穿行类）
/// - `full`   ：全屏闪光 + 大字报 + 大图标弹出（高价值礼物）
///
/// 若缺少 `anim` 或为 `none`，回退为 `float`（兼容旧数据）。
class LocalGiftEffectView extends StatefulWidget {
  const LocalGiftEffectView({super.key, required this.message});

  final LiveMessage message;

  @override
  State<LocalGiftEffectView> createState() => _LocalGiftEffectViewState();
}

class _LocalGiftEffectViewState extends State<LocalGiftEffectView> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;

  Map get _data => widget.message.data is Map ? widget.message.data as Map : const {};

  String get _anim {
    final value = _data['anim'];
    if (value is String && value.isNotEmpty && value != 'none') return value;
    // 兼容旧数据：effect full 视为大字报。
    final effect = _data['effect'];
    if (effect == 'full') return 'full';
    return 'float';
  }

  String get _emoji {
    final value = _data['emoji'];
    if (value is String && value.isNotEmpty) return value;
    return '🎁';
  }

  String get _giftName {
    final value = _data['giftName'];
    if (value is String && value.isNotEmpty) return value;
    return i18n('local_gift_center');
  }

  Color get _color => Color.fromARGB(255, widget.message.color.r, widget.message.color.g, widget.message.color.b);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2700))..forward();
    _progress = CurvedAnimation(parent: _controller, curve: Curves.linear);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return switch (_anim) {
      'launch' => _buildLaunch(),
      'fly' => _buildFly(),
      'full' => _buildFull(),
      _ => _buildFloat(),
    };
  }

  // ---------------- float：弹出 + 上浮 + 粒子 ----------------

  Widget _buildFloat() {
    const particleCount = 7;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _progress.value;
        // 弹出：0~0.16 快速放大回弹。
        final pop = Curves.easeOutBack.transform((t / 0.16).clamp(0.0, 1.0));
        final scale = 0.3 + 0.7 * pop;
        // 上浮：0.16 后缓慢上移。
        final lift = Curves.easeOut.transform(((t - 0.16) / 0.6).clamp(0.0, 1.0)) * 46;
        // 淡出：最后 25% 消失。
        final fadeOut = ((1 - t) / 0.25).clamp(0.0, 1.0);
        return Stack(
          fit: StackFit.expand,
          children: [
            // 粒子：从中心散射。
            for (var i = 0; i < particleCount; i++)
              _Particle(seed: i, progress: t, color: _color, baseOffset: const Offset(0, -30)),
            Center(
              child: Transform.translate(
                offset: Offset(0, -lift - 24),
                child: Opacity(
                  opacity: fadeOut,
                  child: Transform.scale(
                    scale: scale.clamp(0.0, 1.2),
                    child: _GiftBubble(emoji: _emoji, caption: _caption(), color: _color),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ---------------- launch：自底部升空 ----------------

  Widget _buildLaunch() {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _progress.value;
        // 0~0.75 升空，末期淡出。
        final rise = Curves.easeIn.transform((t / 0.72).clamp(0.0, 1.0));
        final fade = t < 0.6 ? 1.0 : ((1 - t) / 0.4).clamp(0.0, 1.0);
        return Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Transform.translate(
                offset: Offset(0, (1 - rise) * 0.55 * MediaQuery.sizeOf(context).height),
                child: Opacity(
                  opacity: fade,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 尾迹：火箭下方渐隐光条。
                      Container(
                        width: 10,
                        height: 120,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Colors.transparent, _color.withValues(alpha: 0.8)],
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      Text(_emoji, style: const TextStyle(fontSize: 56)),
                      Text(
                        _caption(),
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ---------------- fly：横穿画面 ----------------

  Widget _buildFly() {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _progress.value;
        final size = MediaQuery.sizeOf(context);
        final x = (t / 0.8).clamp(0.0, 1.0) * (size.width + 160) - 80;
        final fade = t < 0.72 ? 1.0 : ((1 - t) / 0.28).clamp(0.0, 1.0);
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              top: size.height * 0.32,
              left: x,
              child: Opacity(
                opacity: fade,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 尾迹：左侧光条。
                    Container(
                      width: 90,
                      height: 8,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [Colors.transparent, _color.withValues(alpha: 0.7)]),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    Text(_emoji, style: const TextStyle(fontSize: 48)),
                    Text(
                      _caption(),
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ---------------- full：全屏闪光 + 大字报 ----------------

  Widget _buildFull() {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _progress.value;
        // 开场闪光：0~0.12。
        final flash = Curves.easeOut.transform((t / 0.12).clamp(0.0, 1.0));
        // 大字：0.12~0.3 弹出。
        final pop = Curves.easeOutBack.transform(((t - 0.12) / 0.18).clamp(0.0, 1.0));
        final fade = t < 0.7 ? 1.0 : ((1 - t) / 0.3).clamp(0.0, 1.0);
        // 光晕扩散。
        final halo = (t / 0.7).clamp(0.0, 1.0);
        return Stack(
          fit: StackFit.expand,
          children: [
            // 全屏闪光层。
            Container(color: Colors.white.withValues(alpha: 0.55 * flash * (1 - flash * 0.85))),
            // 中央光晕。
            Center(
              child: Container(
                width: 320 * halo + 40,
                height: 320 * halo + 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _color.withValues(alpha: 0.5 * (1 - halo)),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            // 中央大图标 + 文字。
            Center(
              child: Opacity(
                opacity: fade,
                child: Transform.scale(
                  scale: 0.4 + 0.8 * pop,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_emoji, style: const TextStyle(fontSize: 108)),
                      const SizedBox(height: 14),
                      _Banner(text: _caption(), color: _color),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _caption() {
    final name = widget.message.userName.trim();
    return name.isEmpty ? '$_giftName ×1' : '$name ${i18n('local_sent_gift')} $_giftName ×1';
  }
}

/// 单个散射粒子：seed 决定固定相位，随 progress 从中心飞出并淡出。
class _Particle extends StatelessWidget {
  const _Particle({required this.seed, required this.progress, required this.color, required this.baseOffset});

  final int seed;
  final double progress;
  final Color color;
  final Offset baseOffset;

  @override
  Widget build(BuildContext context) {
    final angle = seed * (2 * math.pi / 7);
    final radius = 24 + progress * 64;
    final dx = math.cos(angle) * radius;
    final dy = math.sin(angle) * radius * 0.62;
    final fade = progress < 0.15 ? progress / 0.15 : ((1 - progress) / 0.6).clamp(0.0, 1.0);
    final size = 6 + (seed % 3) * 3;
    return Positioned.fill(
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.center,
          child: Transform.translate(
            offset: baseOffset + Offset(dx, -dy),
            child: Opacity(
              opacity: fade.clamp(0.0, 1.0) * 0.85,
              child: Container(
                width: size.toDouble(),
                height: size.toDouble(),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.9),
                  boxShadow: [BoxShadow(color: color, blurRadius: 8)],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 礼物内容气泡（小礼物用）。
class _GiftBubble extends StatelessWidget {
  const _GiftBubble({required this.emoji, required this.caption, required this.color});

  final String emoji;
  final String caption;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color.withValues(alpha: 0.92), Colors.black.withValues(alpha: 0.72)]),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 26)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 46)),
          const SizedBox(height: 8),
          Text(
            caption,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// 大字报横幅（高价值礼物用）。
class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color.withValues(alpha: 0.95), Colors.black.withValues(alpha: 0.8)]),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.2),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 36)],
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 1.2),
      ),
    );
  }
}
