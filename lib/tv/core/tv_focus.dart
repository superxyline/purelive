import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';

import 'tv_theme.dart';

/// TV 焦点系统（自写，对齐 pure_live_TV 交互规格）：
///
/// - [TvFocusable]：通用可聚焦件——聚焦放大 1.05/按下 0.97、光晕+高亮环、
///   120ms easeOutCubic（失焦零时长）；OK/Enter 触发 [TvFocusable.onSelect]；
/// - [TvFocusRegion]：区域分组（FocusTraversalGroup）+ 区域焦点记忆
///   （memoryKey → 最后聚焦节点），页面切 Tab/返回时恢复；
/// - 方向键移动交给 Flutter 默认 directional traversal（全局就近寻焦），
///   页面不再手写"边缘让焦"逻辑。
///
/// 确认键：Android TV 遥控 OK = KEYCODE_DPAD_CENTER → Flutter `select`，
/// 另兼容 enter / 游戏手柄 A。

/// 区域焦点记忆：memoryKey → 最后持有焦点的 FocusNode
final Map<String, FocusNode> _tvFocusMemory = {};

FocusNode? tvFocusMemoryOf(String key) => _tvFocusMemory[key];

class TvFocusable extends StatefulWidget {
  const TvFocusable({
    super.key,
    required this.builder,
    this.onSelect,
    this.onLongPress,
    this.focusNode,
    this.autofocus = false,
    this.enabled = true,
    this.scale = TvTheme.focusScale,
    this.borderRadius = const BorderRadius.all(Radius.circular(TvTheme.cardRadius)),
    this.glow = true,
    this.focusedBackgroundColor,
    this.unfocusedBackgroundColor,
    this.pressed,
  });

  /// focused=true 时渲染聚焦外观（ TvRoomCard 聚焦白底等）
  final Widget Function(BuildContext context, bool focused) builder;

  /// OK/Enter 确认
  final VoidCallback? onSelect;

  /// OK 长按（500ms 阈值）
  final VoidCallback? onLongPress;

  final FocusNode? focusNode;
  final bool autofocus;
  final bool enabled;
  final double scale;
  final BorderRadius borderRadius;
  final bool glow;
  final Color? focusedBackgroundColor;
  final Color? unfocusedBackgroundColor;

  /// 按下（焦点内 OK 按住）时的回调，用于 0.97 缩放
  final ValueChanged<bool>? pressed;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  late final FocusNode _node;
  bool _ownsNode = false;
  bool _focused = false;
  bool _pressing = false;
  Timer? _longPressTimer;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode != null) {
      _node = widget.focusNode!;
    } else {
      _node = FocusNode(debugLabel: 'TvFocusable#${identityHashCode(this)}');
      _ownsNode = true;
    }
    _node.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    final focused = _node.hasFocus;
    if (_focused != focused) {
      debugPrint('[TvFocus] node=$_node focused=$focused');
      setState(() {
        _focused = focused;
        if (!focused) _pressing = false;
      });
      // 记录到所属区域
      final region = TvFocusRegion.regionKeyOf(_node);
      if (region != null) _tvFocusMemory[region] = _node;
    }
  }

  @override
  void dispose() {
    _node.removeListener(_onFocusChanged);
    if (_ownsNode) _node.dispose();
    _longPressTimer?.cancel();
    super.dispose();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (!widget.enabled || !_focused) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final isConfirm = key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA;
    if (!isConfirm) return KeyEventResult.ignored;

    if (widget.onSelect == null && widget.onLongPress == null) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      _pressing = true;
      widget.pressed?.call(true);
      setState(() {});
      _longPressTimer?.cancel();
      if (widget.onLongPress != null) {
        // 有长按语义：等 500ms 长按，松开才触发单击
        _longPressTimer = Timer(const Duration(milliseconds: 500), () {
          _longPressTimer = null;
          widget.onLongPress!();
        });
      } else {
        // 无长按语义：KeyDown 即触发（电视遥控 KeyUp 不可靠）
        widget.onSelect?.call();
      }
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      _longPressTimer?.cancel();
      _longPressTimer = null;
      _pressing = false;
      widget.pressed?.call(false);
      setState(() {});
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final scale = _pressing
        ? TvTheme.pressedScale
        : (_focused ? widget.scale : 1.0);
    final duration = _focused ? TvTheme.focusDuration : TvTheme.unfocusDuration;
    final bg = _focused
        ? (widget.focusedBackgroundColor ?? Colors.transparent)
        : (widget.unfocusedBackgroundColor ?? Colors.transparent);

    return Focus(
      focusNode: _node,
      autofocus: widget.autofocus,
      canRequestFocus: widget.enabled,
      onKeyEvent: _onKeyEvent,
      child: AnimatedScale(
        scale: scale,
        duration: duration,
        curve: TvTheme.focusCurve,
        child: AnimatedContainer(
          duration: duration,
          curve: TvTheme.focusCurve,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: widget.borderRadius,
            border: _focused
                ? Border.all(color: TvTheme.focusColor, width: 2)
                : Border.all(color: Colors.transparent, width: 2),
            boxShadow: _focused && widget.glow ? TvTheme.focusGlow : null,
          ),
          child: widget.builder(context, _focused),
        ),
      ),
    );
  }
}

/// 区域分组：FocusTraversalGroup + 区域焦点记忆。
///
/// 用法：包住侧栏/Tab条/网格/面板；`TvFocusRegion.memoryOf(key)` 在页面
/// 切换回来时恢复焦点；`regionKeyOf(node)` 供 [TvFocusable] 回写记忆。
class TvFocusRegion extends StatefulWidget {
  const TvFocusRegion({
    super.key,
    required this.memoryKey,
    required this.child,
    this.autofocusRestore = false,
  });

  final String memoryKey;
  final Widget child;

  /// 区域内节点获得焦点时是否自动把记忆挂到该区域（默认由 TvFocusable 回写）
  final bool autofocusRestore;

  /// 区域级记忆表：node → regionKey
  static final Map<FocusNode, String> _nodeRegion = <FocusNode, String>{};

  static String? regionKeyOf(FocusNode node) => _nodeRegion[node];

  static FocusNode? memoryOf(String key) => _tvFocusMemory[key];

  /// 请求把焦点恢复到 [key] 区域的最后焦点节点（无记忆则返回 false）
  static bool restore(String key) {
    final node = _tvFocusMemory[key];
    if (node == null || !node.canRequestFocus) return false;
    node.requestFocus();
    return true;
  }

  @override
  State<TvFocusRegion> createState() => _TvFocusRegionState();
}

class _TvFocusRegionState extends State<TvFocusRegion> {
  @override
  void initState() {
    super.initState();
    // 把区域内新注册的 focus node 关联到本区域（遍历由 TvFocusable 调用 regionKeyOf）
    scheduleMicrotask(_associateDescendants);
  }

  void _associateDescendants() {
    if (!mounted) return;
    final root = Focus.maybeOf(context);
    if (root == null) return;
    for (final node in root.descendants) {
      TvFocusRegion._nodeRegion[node] = widget.memoryKey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: _RegionRegistrar(
        onNodesChanged: _associateDescendants,
        child: widget.child,
      ),
    );
  }
}

/// 区域内子树变化（列表增删卡片）时重新关联焦点归属
class _RegionRegistrar extends StatefulWidget {
  const _RegionRegistrar({required this.onNodesChanged, required this.child});

  final VoidCallback onNodesChanged;
  final Widget child;

  @override
  State<_RegionRegistrar> createState() => _RegionRegistrarState();
}

class _RegionRegistrarState extends State<_RegionRegistrar> {
  int _lastHash = 0;

  @override
  Widget build(BuildContext context) {
    final hash = identityHashCode(widget.child);
    if (hash != _lastHash) {
      _lastHash = hash;
      scheduleMicrotask(widget.onNodesChanged);
    }
    return widget.child;
  }
}
