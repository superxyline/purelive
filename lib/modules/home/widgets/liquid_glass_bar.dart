import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// 液态玻璃导航栏（移植自 wzgrx/PureLive 的 live_ui/LiquidGlassBar，AGPL-3.0，
/// 同协议引用并保留原实现思路与调参）。
///
/// 一条浮动玻璃胶囊：fragment shader 对底栏后面的页面做边缘折射（厚透镜效果），
/// 选中项是一滴更清晰的"水珠"，切换时弹簧滑过去并拉伸变形；按住变成放大镜，
/// 横向栏还支持按住拖拽滑动换页（带橡皮筋阻尼）。shader 不可用时三级降级：
/// 磨砂玻璃 → 纯色 tint。
///
/// [LiquidGlassBarAxis.horizontal] 用于手机底栏（完整拖拽交互）；
/// [vertical] 用于平板侧栏（点按弹簧选中，不做拖拽）。

/// 玻璃栏尺寸常量（对齐 wzgrx GlassMetrics）。
abstract final class GlassBarMetrics {
  /// 磨砂降级时的模糊强度。
  static const double blurSigma = 14;

  /// 浮动底栏高度。
  static const double barHeight = 68;

  /// 浮动栏与屏幕左右边缘的间距，以及系统不给底部留白时的下边距。
  static const double barMargin = 12;

  /// 浮动栏最大宽度（平板横屏时胶囊居中而非铺满整屏）。
  static const double barMaxWidth = 560;

  /// 竖向侧栏的单项槽高。
  static const double railSlotHeight = 64;

  /// 浮动栏底部留空：在小白条/手势条上方露出（iOS 在 34 中底部绘制，
  /// Android 手势条在 inset 中间，故手势条模式只留一半 + 8）。
  static double barGap({required double safeBottom, required bool ios}) {
    if (safeBottom <= 0) return barMargin;
    if (ios) return barMargin > safeBottom - 14 ? barMargin : safeBottom - 14;
    if (safeBottom > 40) return safeBottom + barMargin;
    final half = safeBottom / 2 + 8;
    return barMargin > half ? barMargin : half;
  }
}

/// 玻璃水滴的弹簧参数（对齐 wzgrx AppMotion，横向移动与按压同频）。
abstract final class GlassBarMotion {
  /// 水滴在栏内移动。
  static final SpringDescription glassPlaceSpring = SpringDescription.withDampingRatio(mass: 1, stiffness: 1000);

  /// 按住时的放大：宽松（会胀过头再回来）。
  static final SpringDescription glassGrowXSpring = SpringDescription.withDampingRatio(mass: 1, stiffness: 250, ratio: 0.6);

  /// 按住时的放大：高稍紧。
  static final SpringDescription glassGrowYSpring = SpringDescription.withDampingRatio(mass: 1, stiffness: 250, ratio: 0.7);

  /// 水滴速度对形状的扰动：欠阻尼。
  static final SpringDescription glassSquashSpring = SpringDescription.withDampingRatio(mass: 1, stiffness: 300, ratio: 0.5);

  /// 拖拽后整条栏回正。
  static final SpringDescription glassLeanSpring = SpringDescription.withDampingRatio(mass: 1, stiffness: 300);

  /// 按住时水滴的放大倍数。
  static const double glassHeldScale = 1.15;

  /// 橡皮筋阻尼：越过端点后越拉越重（对齐 wzgrx rubberBand）。
  static double rubberBand(double overscroll, double extent) {
    if (extent <= 0 || overscroll == 0) return 0;
    final x = overscroll.abs() / extent;
    final clamped = x > 1 ? 1.0 : x;
    return overscroll.sign * extent * (clamped - clamped * clamped + clamped * clamped * clamped / 3);
  }
}

/// 液态玻璃 shader：加载一次；不支持 shader filter 的环境（无 Impeller、测试）
/// 返回 null，玻璃自动降级为磨砂/纯色。
abstract final class LiquidGlassShader {
  static Future<ui.FragmentProgram?>? _loading;
  static ui.FragmentProgram? _program;

  static ui.FragmentProgram? get program => _program;

  static Future<ui.FragmentProgram?> load() => _loading ??= _load();

  static Future<ui.FragmentProgram?> _load() async {
    if (!ui.ImageFilter.isShaderFilterSupported) {
      debugPrint('liquid glass: shader filter unsupported on this backend');
      _loading = null; // 后端切换（如 Impeller 就绪）后允许重试
      return null;
    }
    try {
      final program = await ui.FragmentProgram.fromAsset('shaders/liquid_glass.frag');
      _program = program;
      debugPrint('liquid glass: shader loaded');
      return program;
    } on Object catch (error) {
      debugPrint('liquid glass: shader not loaded: $error');
      _loading = null; // 失败不永久缓存，下次构建重试
      return null;
    }
  }
}

/// 导航栏的一个目的地。
class LiquidGlassBarItem {
  const LiquidGlassBarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.onTap,
    this.selectable = true,
  });

  /// 未选中图标。
  final IconData icon;

  /// 选中图标。
  final IconData selectedIcon;

  /// 图标下的文字。
  final String label;

  /// 点击回调。
  final VoidCallback? onTap;

  /// 是否为可选中的目的地（false = 动作项，如设置/搜索入口：点击后
  /// 水滴碰一下即弹回选中项，不改变选中态）。
  final bool selectable;
}

/// 玻璃栏方向。
enum LiquidGlassBarAxis { horizontal, vertical }

/// 浮动液态玻璃导航栏。
class LiquidGlassBar extends StatefulWidget {
  const LiquidGlassBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.axis = LiquidGlassBarAxis.horizontal,
    this.blur = true,
    this.refraction = true,
    this.height = GlassBarMetrics.barHeight,
    this.frost = 0.3,
    this.showLabels = true,
  });

  /// 各目的地。
  final List<LiquidGlassBarItem> items;

  /// 当前选中的下标。
  final int selectedIndex;

  /// 目的地被选中（点击或拖拽落定）。
  final ValueChanged<int> onSelected;

  /// 手机底栏横排 / 平板侧栏竖排。
  final LiquidGlassBarAxis axis;

  /// 是否模糊栏后的页面（低内存设备可关）。
  final bool blur;

  /// 是否允许 shader 折射。
  final bool refraction;

  /// 横向：整条栏的高度；竖向：每个槽位的高度（总高 = items × height）。
  final double height;

  /// 磨砂程度 0（通透）~ 1（浓霜）。
  final double frost;

  /// 是否显示文字标签。
  final bool showLabels;

  @override
  State<LiquidGlassBar> createState() => _LiquidGlassBarState();
}

class _LiquidGlassBarState extends State<LiquidGlassBar> with TickerProviderStateMixin {
  /// 水滴中心（沿栏轴的逻辑像素）；由弹簧驱动。
  late final AnimationController _drop = AnimationController.unbounded(vsync: this);

  /// 按住程度：0 静止药丸，1 放大镜。
  late final AnimationController _press = AnimationController.unbounded(vsync: this);

  /// 按住时水滴横纵的膨胀，各自弹簧。
  late final AnimationController _growX = AnimationController.unbounded(vsync: this, value: 1);
  late final AnimationController _growY = AnimationController.unbounded(vsync: this, value: 1);

  /// 水滴速度对形状的扰动（px/s，沿轴）。
  late final AnimationController _squash = AnimationController.unbounded(vsync: this);

  /// 拖拽时整条栏的倾斜量（px）。
  late final AnimationController _lean = AnimationController.unbounded(vsync: this);

  ui.FragmentProgram? _program = LiquidGlassShader.program;
  double _extent = 0;
  double _crossExtent = 0;
  bool _placed = false;
  int? _dragIndex;
  double _dragTarget = 0;
  bool _touching = false;
  double _heading = 1;
  final GlobalKey _barKey = GlobalKey(debugLabel: 'liquid glass bar');

  bool get _isHorizontal => widget.axis == LiquidGlassBarAxis.horizontal;

  @override
  void initState() {
    super.initState();
    _drop.addListener(_feelSpeed);
    if (_program == null && widget.refraction) {
      unawaited(
        LiquidGlassShader.load().then((program) {
          if (mounted && program != null) setState(() => _program = program);
        }),
      );
    }
  }

  @override
  void didUpdateWidget(LiquidGlassBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex && _dragIndex == null) _settle(widget.selectedIndex);
  }

  @override
  void dispose() {
    if (_arriving case final arriving?) _drop.removeListener(arriving);
    _drop.dispose();
    _press.dispose();
    _growX.dispose();
    _growY.dispose();
    _squash.dispose();
    _lean.dispose();
    super.dispose();
  }

  /// 单个槽位在轴向上的长度。
  double get _slot => _itemsLength == 0 ? 0 : _extent / _itemsLength;
  int get _itemsLength => widget.items.length;

  double _centreOf(int index) => _slot * (index + 0.5);

  int _indexAt(double x) => (x / (_slot == 0 ? 1 : _slot)).floor().clamp(0, _itemsLength - 1);

  bool get _still => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  static void _spring(AnimationController controller, SpringDescription spring, double target) {
    controller.animateWith(SpringSimulation(spring, controller.value, target, controller.velocity));
  }

  /// 形状随水滴速度经欠阻尼弹簧变化。
  void _feelSpeed() {
    final speed = _drop.velocity;
    if (speed.abs() > 1) _heading = speed.sign;
    if (_still) return;
    _spring(_squash, GlassBarMotion.glassSquashSpring, speed);
  }

  /// 按住：药丸变放大镜并膨胀；松开：缩回。
  void _hold(bool held) {
    if (_still) return;
    final grow = held ? GlassBarMotion.glassHeldScale : 1.0;
    _spring(_press, GlassBarMotion.glassPlaceSpring, held ? 1 : 0);
    _spring(_growX, GlassBarMotion.glassGrowXSpring, grow);
    _spring(_growY, GlassBarMotion.glassGrowYSpring, grow);
  }

  /// 跳到 [index]：水滴以放大镜形态出发，到达后变回药丸。
  void _settle(int index) {
    final target = _centreOf(index);
    if (_still || _extent == 0) {
      _drop.value = target;
      return;
    }
    _hold(true);
    _following = null;
    _drop.animateWith(SpringSimulation(GlassBarMotion.glassPlaceSpring, _drop.value, target, _drop.velocity));
    _letGoNear(target);
  }

  VoidCallback? _arriving;

  /// 水滴到目标 2.5% 槽距内就变回药丸（不等弹簧最后那点像素爬完）。
  void _letGoNear(double target) {
    if (_arriving case final previous?) _drop.removeListener(previous);
    final near = (_centreOf(_itemsLength - 1) - _centreOf(0)) * 0.025;
    void check() {
      if ((_drop.value - target).abs() > near && _drop.isAnimating) return;
      _drop.removeListener(check);
      if (identical(_arriving, check)) _arriving = null;
      if (mounted && !_touching && _dragIndex == null) _hold(false);
    }

    _arriving = check;
    _drop.addListener(check);
  }

  /// 手指按下的目的地，直到它被选中（tap）或拖走。
  int? _pressedIndex;

  void _onPointerDown(PointerDownEvent event) {
    _touching = true;
    _hold(true);
    if (_extent == 0) return;
    final position = _isHorizontal ? event.localPosition.dx : event.localPosition.dy;
    final index = _indexAt(position);
    _pressedIndex = index;
    if ((_drop.value - _centreOf(index)).abs() > 0.5) _goTo(index);
  }

  void _onPointerUp(PointerEvent event) {
    _touching = false;
    // 按下后既没成为点击也没成为拖拽（手指滑出、被系统接管）：水滴回选中项。
    // tap 回调在 pointerUp 之后到达，所以放到 microtask 里等它先处理。
    scheduleMicrotask(() {
      if (!mounted || _pressedIndex == null) return;
      _pressedIndex = null;
      if (_dragIndex == null) _settle(widget.selectedIndex);
    });
    // 松手时水滴还在路上：让它到达后再松开放大镜。
    if (_arriving == null && _dragIndex == null) _hold(false);
  }

  /// 按住期间跳到 [index]：到达时不松开放大镜。
  void _goTo(int index) {
    if (_still) {
      _drop.value = _centreOf(index);
      return;
    }
    _following = null;
    _drop.animateWith(SpringSimulation(GlassBarMotion.glassPlaceSpring, _drop.value, _centreOf(index), _drop.velocity));
    _letGoNear(_centreOf(index));
  }

  /// 拖拽累计位移。
  double _dragDistance = 0;

  /// 拖拽水滴用的"终点可动的弹簧"：移动终点时从上一帧的位置与速度续跑
  /// （每帧新建弹簧会导致每帧落回时间 0，手指动水滴反而不动）。
  _MovingSpring? _following;

  void _follow(double target) {
    if (_following case final spring? when _drop.isAnimating) {
      spring.target = target;
      return;
    }
    final spring = _following = _MovingSpring(GlassBarMotion.glassPlaceSpring, _drop.value, target, _drop.velocity);
    _drop.animateWith(spring);
  }

  void _onDragStart(DragStartDetails details) {
    _pressedIndex = null;
    _dragDistance = 0;
    _dragTarget = _drop.value;
    _dragIndex = _indexAt(_dragTarget);
    _hold(true);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final delta = _isHorizontal ? details.delta.dx : details.delta.dy;
    final min = _centreOf(0);
    final max = _centreOf(_itemsLength - 1);
    _dragTarget += delta;
    _dragDistance += delta.abs();
    // 越过两端后越拉越重（列表的橡皮筋手感）。
    final raw = _dragTarget;
    final next = raw < min
        ? min + GlassBarMotion.rubberBand(raw - min, _slot)
        : raw > max
        ? max + GlassBarMotion.rubberBand(raw - max, _slot)
        : raw;
    if (_still) {
      _drop.value = next;
    } else {
      _follow(next);
      _lean.value += delta;
    }
    final index = _indexAt(next);
    if (index != _dragIndex) {
      _dragIndex = index;
      unawaited(HapticFeedback.selectionClick());
    }
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = _isHorizontal ? details.velocity.pixelsPerSecond.dx : details.velocity.pixelsPerSecond.dy;
    // 位移小于滑动门槛且无甩动：不算选择，水滴回选中项。
    if (_dragDistance < kTouchSlop && velocity.abs() < kMinFlingVelocity) {
      _dragIndex = null;
      _touching = false;
      if (!_still) _spring(_lean, GlassBarMotion.glassLeanSpring, 0);
      _settle(widget.selectedIndex);
      return;
    }
    // 按甩动惯性外推 0.2 秒决定落点。
    var index = _indexAt(_dragTarget.clamp(_centreOf(0), _centreOf(_itemsLength - 1)) + velocity * 0.2);
    _dragIndex = null;
    _touching = false;
    if (!_still) _spring(_lean, GlassBarMotion.glassLeanSpring, 0);
    // 落点是动作项（设置/搜索入口）时水滴回选中项，不改变选中态。
    if (!widget.items[index].selectable) {
      _settle(widget.selectedIndex);
      return;
    }
    final moved = index != widget.selectedIndex;
    _settle(index);
    if (moved) widget.onSelected(index);
  }

  void _onTap(int index) {
    final item = widget.items[index];
    _pressedIndex = null;
    if (item.selectable) {
      if (index != widget.selectedIndex) _settle(index);
      widget.onSelected(index);
    } else {
      // 动作项：水滴碰一下弹回选中项。
      _settle(widget.selectedIndex);
    }
    item.onTap?.call();
  }

  double get _held => _press.value.clamp(0.0, 1.0);

  /// 拖拽时整条栏倾斜几像素再回正。
  double get _leanOffset {
    if (_extent == 0 || !_isHorizontal) return 0;
    final fraction = (_lean.value / _extent).clamp(-1.0, 1.0);
    return 4 * fraction.sign * Curves.easeOut.transform(fraction.abs());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final route = ModalRoute.of(context);
    // 玻璃按屏幕像素绘制：路由滑动时也要重绘，而不只是尺寸变化。
    final moves = Listenable.merge([
      _drop,
      _press,
      _growX,
      _growY,
      _squash,
      _lean,
      ?route?.animation,
      ?route?.secondaryAnimation,
    ]);
    return LayoutBuilder(
      builder: (context, constraints) {
        // 横向取可用宽度（可被调用方限制在 barMaxWidth 内），竖向取总高。
        _extent = _isHorizontal ? constraints.maxWidth : constraints.maxHeight;
        _crossExtent = _isHorizontal ? widget.height : constraints.maxWidth;
        if (!_placed && _extent > 0) {
          _placed = true;
          _drop.value = _centreOf(widget.selectedIndex);
        }
        final barContent = _LiquidGlass(
          program: widget.refraction ? _program : null,
          blur: widget.blur,
          dark: dark,
          frost: widget.frost,
          tint: scheme.surfaceContainerHighest,
          moves: moves,
          drop: _dropRect,
          held: () => _held,
          // 竖向必须锁宽：否则玻璃条宽度=最宽子项（长文字项），
          // 水滴却按约束宽度居中，两者错位（水滴偏右）。
          child: KeyedSubtree(
            key: _barKey,
            child: _isHorizontal
                ? Row(
                    children: [
                      for (final (index, item) in widget.items.indexed) Expanded(child: _destination(context, index, item, moves)),
                    ],
                  )
                : SizedBox(
                    width: constraints.maxWidth,
                    child: Column(
                      children: [
                        for (final (index, item) in widget.items.indexed) Expanded(child: _destination(context, index, item, moves)),
                      ],
                    ),
                  ),
          ),
        );
        final bar = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: _isHorizontal ? _onDragStart : null,
          onHorizontalDragUpdate: _isHorizontal ? _onDragUpdate : null,
          onHorizontalDragEnd: _isHorizontal ? _onDragEnd : null,
          onVerticalDragStart: _isHorizontal ? null : _onDragStart,
          onVerticalDragUpdate: _isHorizontal ? null : _onDragUpdate,
          onVerticalDragEnd: _isHorizontal ? null : _onDragEnd,
          child: barContent,
        );
        return Listener(
          onPointerDown: _onPointerDown,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerUp,
          child: AnimatedBuilder(
            animation: Listenable.merge([_press, _lean]),
            // 按住时整条栏微微胀大，拖拽时沿轴倾斜。
            builder: (context, child) => _isHorizontal
                ? Transform.translate(
                    offset: Offset(_leanOffset, 0),
                    child: Transform.scale(
                      scale: 1 + (_extent == 0 ? 0 : 16 / _extent) * _held,
                      child: child,
                    ),
                  )
                : Transform.scale(
                    scale: 1 + (_extent == 0 ? 0 : 12 / _extent) * _held,
                    child: child,
                  ),
            child: bar,
          ),
        );
      },
    );
  }

  /// 水滴矩形：按住膨胀，随速度沿运动方向拉伸、停止时反向压扁。
  Rect _dropRect() {
    if (_extent == 0) return Rect.zero;
    // 速度换算成槽位每秒的十分之一（对齐 wzgrx 的比例）。
    final speed = _slot == 0 ? 0.0 : _squash.value * _heading / _slot / 10;
    final across = _growX.value / (1 - (speed * 0.75).clamp(-0.2, 0.2));
    final up = _growY.value * (1 - (speed * 0.25).clamp(-0.2, 0.2));
    if (_isHorizontal) {
      final width = (_slot - 10) * across;
      final height = (widget.height - 12) * up;
      return Rect.fromCenter(center: Offset(_drop.value, widget.height / 2), width: width, height: height);
    }
    // 竖向：水滴宽沿交叉轴（栏宽），高沿槽位。
    final width = (_crossExtent - 12) * across;
    final height = (widget.height - 12) * up;
    return Rect.fromCenter(center: Offset(_crossExtent / 2, _drop.value), width: width, height: height);
  }

  Widget _destination(BuildContext context, int index, LiquidGlassBarItem item, Listenable moves) {
    final scheme = Theme.of(context).colorScheme;
    final chosen = index == widget.selectedIndex;
    // 图标画两遍：水滴外用普通色，水滴内用强调色——图标颜色恰好到水滴边界
    // 为止（水滴滑动时颜色跟着切）。
    Widget part({required bool inside, required Widget child}) =>
        _UnderDrop(bar: _barKey, drop: _dropRect, moves: moves, inside: inside, child: child);
    final icon = Stack(
      children: [
        part(inside: false, child: Icon(item.icon, size: 24, color: scheme.onSurfaceVariant)),
        // 按住的放大镜里图标随页面一起放大。
        part(
          inside: true,
          child: ExcludeSemantics(
            child: AnimatedBuilder(
              animation: _press,
              builder: (context, child) => Transform.scale(scale: 1 + 0.14 * _held, child: child),
              child: Icon(item.selectedIcon, size: 24, color: scheme.primary),
            ),
          ),
        ),
      ],
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: () => _onTap(index),
      child: SizedBox(
        height: _isHorizontal ? widget.height : widget.height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
          child: Semantics(
            container: true,
            button: true,
            selected: chosen,
            label: item.label,
            onTap: () => _onTap(index),
            excludeSemantics: true,
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    icon,
                    if (widget.showLabels) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: chosen ? FontWeight.w600 : FontWeight.w400,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 终点可移动的弹簧：移动终点时从上一帧的位置与速度、同一时钟上续跑。
class _MovingSpring extends Simulation {
  _MovingSpring(this._spring, double from, double to, double velocity)
    : _target = to,
      _run = SpringSimulation(_spring, from, to, velocity);

  final SpringDescription _spring;
  SpringSimulation _run;
  double _target;

  double _start = 0;
  double _now = 0;

  double get target => _target;
  set target(double value) {
    if (value == _target) return;
    final time = _now - _start;
    _run = SpringSimulation(_spring, _run.x(time), value, _run.dx(time));
    _start = _now;
    _target = value;
  }

  @override
  double x(double time) {
    _now = time;
    return _run.x(time - _start);
  }

  @override
  double dx(double time) => _run.dx(time - _start);

  @override
  bool isDone(double time) => _run.isDone(time - _start);
}

/// 只在水滴内部（[inside]=true）或外部显示 child，水滴矩形随移动重新裁剪。
class _UnderDrop extends SingleChildRenderObjectWidget {
  const _UnderDrop({required this.bar, required this.drop, required this.moves, required this.inside, required super.child});

  final GlobalKey bar;
  final Rect Function() drop;
  final Listenable moves;
  final bool inside;

  @override
  _RenderUnderDrop createRenderObject(BuildContext context) =>
      _RenderUnderDrop(bar: bar, drop: drop, moves: moves, inside: inside);

  @override
  void updateRenderObject(BuildContext context, _RenderUnderDrop renderObject) {
    renderObject
      ..bar = bar
      ..drop = drop
      ..moves = moves
      ..inside = inside;
  }
}

class _RenderUnderDrop extends RenderProxyBox {
  _RenderUnderDrop({required this.bar, required this.drop, required Listenable moves, required bool inside})
    : _moves = moves,
      _inside = inside;

  GlobalKey bar;
  Rect Function() drop;

  Listenable _moves;
  Listenable get moves => _moves;
  set moves(Listenable value) {
    if (value == _moves) return;
    if (attached) _moves.removeListener(markNeedsPaint);
    _moves = value;
    if (attached) _moves.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  bool _inside;
  bool get inside => _inside;
  set inside(bool value) {
    if (value == _inside) return;
    _inside = value;
    markNeedsPaint();
  }

  final LayerHandle<ClipPathLayer> _clip = LayerHandle();

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _moves.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _moves.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final box = bar.currentContext?.findRenderObject();
    final rect = drop();
    if (box is! RenderBox || !box.attached || rect.isEmpty) {
      _clip.layer = null;
      if (!_inside) super.paint(context, offset);
      return;
    }
    final toBar = getTransformTo(box);
    if (toBar.invert() == 0) {
      _clip.layer = null;
      if (!_inside) super.paint(context, offset);
      return;
    }
    final local = MatrixUtils.transformRect(toBar, rect);
    final bounds = Offset.zero & size;
    if (!local.overlaps(bounds)) {
      _clip.layer = null;
      if (!_inside) super.paint(context, offset);
      return;
    }
    final capsule = Path()..addRRect(RRect.fromRectAndRadius(local, Radius.circular(local.shortestSide / 2)));
    final path = _inside
        ? capsule
        : (Path()
            ..fillType = PathFillType.evenOdd
            ..addRect(bounds.inflate(1))
            ..addPath(capsule, Offset.zero));
    _clip.layer = context.pushClipPath(needsCompositing, offset, bounds, path, super.paint, oldLayer: _clip.layer);
  }
}

class _LiquidGlass extends SingleChildRenderObjectWidget {
  const _LiquidGlass({
    required this.program,
    required this.blur,
    required this.dark,
    required this.frost,
    required this.tint,
    required this.moves,
    required this.drop,
    required this.held,
    required super.child,
  });

  final ui.FragmentProgram? program;
  final bool blur;
  final bool dark;
  final double frost;
  final Color tint;
  final Listenable moves;
  final Rect Function() drop;
  final double Function() held;

  @override
  RenderLiquidGlass createRenderObject(BuildContext context) => RenderLiquidGlass(
    program: program,
    blur: blur,
    dark: dark,
    frost: frost,
    tint: tint,
    moves: moves,
    drop: drop,
    held: held,
    devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
  );

  @override
  void updateRenderObject(BuildContext context, RenderLiquidGlass renderObject) {
    renderObject
      ..program = program
      ..blur = blur
      ..dark = dark
      ..frost = frost
      ..tint = tint
      ..moves = moves
      ..drop = drop
      ..held = held
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
  }
}

/// 在 child 之下绘制玻璃：shader backdrop filter（裁到玻璃形状），或磨砂降级。
class RenderLiquidGlass extends RenderProxyBox {
  RenderLiquidGlass({
    required ui.FragmentProgram? program,
    required bool blur,
    required bool dark,
    required double frost,
    required Color tint,
    required Listenable moves,
    required Rect Function() drop,
    required double Function() held,
    required double devicePixelRatio,
  }) : _program = program,
       _blur = blur,
       _dark = dark,
       _frost = frost,
       _tint = tint,
       _moves = moves,
       _drop = drop,
       _held = held,
       _devicePixelRatio = devicePixelRatio;

  ui.FragmentProgram? _program;
  ui.FragmentShader? _shader;

  ui.FragmentProgram? get program => _program;
  set program(ui.FragmentProgram? value) {
    if (value == _program) return;
    _program = value;
    _shader?.dispose();
    _shader = null;
    markNeedsPaint();
  }

  bool _blur;
  bool get blur => _blur;
  set blur(bool value) {
    if (value == _blur) return;
    _blur = value;
    markNeedsPaint();
  }

  bool _dark;
  bool get dark => _dark;
  set dark(bool value) {
    if (value == _dark) return;
    _dark = value;
    markNeedsPaint();
  }

  double _frost;
  double get frost => _frost;
  set frost(double value) {
    if (value == _frost) return;
    _frost = value;
    markNeedsPaint();
  }

  Color _tint;
  Color get tint => _tint;
  set tint(Color value) {
    if (value == _tint) return;
    _tint = value;
    markNeedsPaint();
  }

  double Function() _held;
  double Function() get held => _held;
  set held(double Function() value) {
    _held = value;
    markNeedsPaint();
  }

  Listenable _moves;
  Listenable get moves => _moves;
  set moves(Listenable value) {
    if (value == _moves) return;
    if (attached) _moves.removeListener(markNeedsPaint);
    _moves = value;
    if (attached) _moves.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  Rect Function() _drop;
  Rect Function() get drop => _drop;
  set drop(Rect Function() value) {
    _drop = value;
    markNeedsPaint();
  }

  double _devicePixelRatio;
  double get devicePixelRatio => _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  final LayerHandle<BackdropFilterLayer> _backdrop = LayerHandle();

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _moves.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _moves.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _backdrop.layer = null;
    _shader?.dispose();
    super.dispose();
  }

  @override
  bool get alwaysNeedsCompositing => true;

  double get _radius {
    // 竖向栏总高远大于宽，胶囊圆角必须取短边一半。
    final short = size.width < size.height ? size.width : size.height;
    return short / 2;
  }

  /// 玻璃四周多读一点 backdrop：模糊与弯边需要周边页面像素。
  static const double _margin = 16;

  @override
  void paint(PaintingContext context, Offset offset) {
    final bounds = offset & size;
    final dropRect = _drop().shift(offset);
    final program = _program;
    final filter = program == null ? _frostedFilter() : _shaderFilter(program, dropRect.shift(-offset));
    if (filter != null) {
      final clip = program == null ? Offset.zero & size : (Offset.zero & size).inflate(_margin);
      context.pushClipRect(needsCompositing, offset, clip, (context, offset) {
        final layer = (_backdrop.layer ??= BackdropFilterLayer())..filter = filter;
        context.pushLayer(layer, (context, offset) {
          final here = dropRect.shift(offset - bounds.topLeft);
          if (program == null) {
            _paintFallback(context.canvas, offset & size, here);
          } else {
            _paintTouch(context.canvas, offset & size, here);
          }
          super.paint(context, offset);
        }, offset);
      });
      return;
    }
    _paintFallback(context.canvas, bounds, dropRect);
    super.paint(context, offset);
  }

  ui.ImageFilter? _frostedFilter() =>
      _blur ? ui.ImageFilter.blur(sigmaX: GlassBarMetrics.blurSigma, sigmaY: GlassBarMetrics.blurSigma, tileMode: TileMode.mirror) : null;

  /// shader 在屏幕物理像素下工作：换算玻璃当前在屏幕上的位置。
  ui.ImageFilter _shaderFilter(ui.FragmentProgram program, Rect dropRect) {
    final shader = _shader ??= program.fragmentShader();
    final ratio = _devicePixelRatio;
    final toScreen = getTransformTo(null);
    final pane = MatrixUtils.transformRect(toScreen, Offset.zero & size);
    final dropOnScreen = MatrixUtils.transformRect(toScreen, dropRect);
    final scale = pane.width / size.width;
    final tint = _tint;
    var i = 2; // 0、1：backdrop 尺寸由引擎写入
    void set(double value) => shader.setFloat(i++, value);
    set(pane.left * ratio);
    set(pane.top * ratio);
    set(pane.width * ratio);
    set(pane.height * ratio);
    set(dropOnScreen.left * ratio);
    set(dropOnScreen.top * ratio);
    set(dropOnScreen.width * ratio);
    set(dropOnScreen.height * ratio);
    final px = ratio * scale;
    set(_radius * px);
    set(dropOnScreen.height / 2 * ratio);
    final held = _held();
    set(dropRect.isEmpty ? 0 : held);
    set(1 + 0.12 * held);
    final frost = _frost.clamp(0.0, 1.0);
    set(26 * px); // 边缘带宽度
    set(16 * px); // 折射强度
    set(1.4 * px); // rim 宽度
    set(0.08); // 色散
    set(tint.r);
    set(tint.g);
    set(tint.b);
    set((_dark ? 0.18 : 0.14) + 0.48 * frost);
    set(-0.6);
    set(-0.8);
    set(_dark ? 0.8 : 1.2); // rim 强度
    set(1.18); // 饱和度
    // 定义边线：轮廓内侧一线，浅色玻璃上压暗、深色上提亮。
    set(1.2 * px);
    set(_dark ? 0 : 0.16);
    set(_dark ? 0.07 : 0);
    final glass = ui.ImageFilter.shader(shader);
    if (!_blur) return glass;
    // 磨砂越浓，后面页面扩散越强。
    final sigma = 6 + 10 * frost;
    return ui.ImageFilter.compose(outer: glass, inner: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.mirror));
  }

  /// shader 之上：药丸随放大镜渐隐 + 触摸高光。
  void _paintTouch(Canvas canvas, Rect bounds, Rect dropRect) {
    _paintPill(canvas, dropRect, lens: true);
    _paintGlow(canvas, bounds, dropRect);
    _paintLensDepth(canvas, dropRect);
  }

  /// 按住的放大镜悬浮在玻璃上：周围软阴影 + 内侧上缘阴影。
  void _paintLensDepth(Canvas canvas, Rect dropRect) {
    final held = _held().clamp(0.0, 1.0);
    if (held <= 0 || dropRect.isEmpty) return;
    final lens = RRect.fromRectAndRadius(dropRect, Radius.circular(dropRect.shortestSide / 2));
    final around = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(dropRect.inflate(48))
      ..addRRect(lens);
    canvas
      ..save()
      ..clipPath(around)
      ..drawRRect(
        lens.shift(const Offset(0, 4)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.10 * held)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, Shadow.convertRadiusToSigma(24)),
      )
      ..restore();
    final radius = 8 * held;
    final inner = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(dropRect.inflate(radius * 3 + 8))
      ..addRRect(lens.shift(Offset(0, radius)));
    canvas
      ..save()
      ..clipRRect(lens)
      ..drawPath(
        inner,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.15 * held)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, Shadow.convertRadiusToSigma(radius)),
      )
      ..restore();
  }

  /// 静止的水滴：一层药丸阴影（浅色玻璃上黑、深色上白），放大镜出现时让位。
  void _paintPill(Canvas canvas, Rect dropRect, {required bool lens}) {
    if (dropRect.isEmpty) return;
    final held = _held().clamp(0.0, 1.0);
    final pill = RRect.fromRectAndRadius(dropRect, Radius.circular(dropRect.shortestSide / 2));
    final shade = Colors.black.withValues(alpha: (_dark ? 0.24 : 0.08) * (lens ? 1 - held : 1));
    canvas.drawRRect(pill, Paint()..color = shade);
    if (held > 0) canvas.drawRRect(pill, Paint()..color = Colors.black.withValues(alpha: (lens ? 0.03 : 0.04) * held));
  }

  /// 按住时玻璃在水滴处亮起：微光铺底 + 圆形柔光。
  void _paintGlow(Canvas canvas, Rect bounds, Rect dropRect) {
    final held = _held().clamp(0.0, 1.0);
    if (held <= 0 || dropRect.isEmpty) return;
    canvas
      ..save()
      ..clipRRect(RRect.fromRectAndRadius(bounds, Radius.circular(_radius)))
      ..drawRect(bounds, Paint()..blendMode = BlendMode.plus..color = Colors.white.withValues(alpha: 0.08 * held));
    final radius = bounds.shortestSide * 1.5;
    canvas
      ..drawRect(
        bounds,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.radial(
            dropRect.center,
            radius,
            [
              Colors.white.withValues(alpha: 0.15 * held),
              Colors.white.withValues(alpha: 0.15 * held),
              const Color(0x00FFFFFF),
            ],
            [0, 0.5, 1],
          ),
      )
      ..restore();
  }

  /// 无 shader 时的磨砂玻璃与药丸水滴。
  void _paintFallback(Canvas canvas, Rect bounds, Rect dropRect) {
    final shape = RRect.fromRectAndRadius(bounds, Radius.circular(_radius));
    final alpha = _blur ? (_dark ? 0.30 : 0.34) + 0.14 * _frost.clamp(0.0, 1.0) : 0.90;
    canvas.drawRRect(shape, Paint()..color = _tint.withValues(alpha: alpha));
    _paintPill(canvas, dropRect, lens: false);
    _paintGlow(canvas, bounds, dropRect);
    canvas.drawRRect(
      shape.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = (_dark ? Colors.white : Colors.black).withValues(alpha: _dark ? 0.16 : 0.10),
    );
  }
}
