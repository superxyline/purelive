import 'dart:async';

import 'package:flutter/material.dart';

import '../core/tv_focus.dart';
import '../core/tv_theme.dart';

/// 半透明黑底圆角角标（平台/人气/关注）
class TvStatusChip extends StatelessWidget {
  const TvStatusChip({super.key, required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: context.tvDp(8), vertical: context.tvDp(2)),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(context.tvDp(6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: context.tvDp(12), color: Colors.white),
            SizedBox(width: context.tvDp(3)),
          ],
          Text(
            label,
            style: TextStyle(fontSize: context.tvSp(12), color: Colors.white),
          ),
        ],
      ),
    );
  }
}

/// 聚焦跑马灯：聚焦且文本溢出时水平往返滚动，失焦/不溢出静止
class TvMarqueeText extends StatefulWidget {
  const TvMarqueeText(
    this.text, {
    super.key,
    required this.focused,
    this.style,
    this.maxLines = 1,
  });

  final String text;
  final bool focused;
  final TextStyle? style;
  final int maxLines;

  @override
  State<TvMarqueeText> createState() => _TvMarqueeTextState();
}

class _TvMarqueeTextState extends State<TvMarqueeText> {
  final ScrollController _controller = ScrollController();
  Timer? _timer;
  double _offset = 0;
  bool _forward = true;

  @override
  void didUpdateWidget(TvMarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focused != oldWidget.focused) {
      if (widget.focused) {
        _start();
      } else {
        _stop();
      }
    }
  }

  void _start() {
    _stop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final max = _controller.position.maxScrollExtent;
      if (max <= 0) return; // 不溢出，不滚
      _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        if (!mounted || !_controller.hasClients) return;
        final max = _controller.position.maxScrollExtent;
        if (max <= 0) return;
        final step = max / 40;
        setState(() {
          if (_forward) {
            _offset += step;
            if (_offset >= max) {
              _offset = max;
              _forward = false;
            }
          } else {
            _offset -= step;
            if (_offset <= 0) {
              _offset = 0;
              _forward = true;
            }
          }
        });
      });
      _controller.jumpTo(_offset);
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _offset = 0;
    _forward = true;
    if (_controller.hasClients) _controller.jumpTo(0);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Text(
        widget.text,
        maxLines: widget.maxLines,
        style: widget.style,
      ),
    );
  }
}

/// 空态：图标 + 文案 + 按键提示
class TvEmpty extends StatelessWidget {
  const TvEmpty({super.key, this.icon = Icons.tv_off_rounded, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: context.tvDp(56), color: TvTheme.textSecondary),
          SizedBox(height: context.tvDp(12)),
          Text(message, style: TextStyle(fontSize: context.tvSp(16), color: TvTheme.textSecondary)),
        ],
      ),
    );
  }
}

/// 加载态
class TvLoading extends StatelessWidget {
  TvLoading({super.key, this.message = '加载中...'});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: TvTheme.focusColor),
          SizedBox(height: context.tvDp(12)),
          Text(message, style: TextStyle(fontSize: context.tvSp(14), color: TvTheme.textSecondary)),
        ],
      ),
    );
  }
}

/// 平台 Tab 条：横向 Tab + 刷新进度线；重复按当前 Tab 触发刷新
class TvTabBar extends StatelessWidget {
  const TvTabBar({
    super.key,
    required this.tabs,
    required this.currentIndex,
    required this.onSelected,
    this.refreshing = false,
  });

  final List<String> tabs;
  final int currentIndex;
  final ValueChanged<int> onSelected;
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: context.tvDp(56),
      child: Stack(
        alignment: AlignmentDirectional.bottomStart,
        children: [
          ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: context.tvDp(8)),
            itemCount: tabs.length,
            separatorBuilder: (_, _) => SizedBox(width: context.tvDp(8)),
            itemBuilder: (context, index) {
              final selected = index == currentIndex;
              return TvFocusable(
                key: ValueKey('tab_$index'),
                borderRadius: BorderRadius.circular(context.tvDp(999)),
                focusedBackgroundColor: TvTheme.focusColor,
                unfocusedBackgroundColor:
                    selected ? TvTheme.focusColor.withValues(alpha: 0.35) : TvTheme.subtleFill,
                onSelect: () => onSelected(index),
                builder: (context, focused) => Padding(
                  padding: EdgeInsets.symmetric(horizontal: context.tvDp(20), vertical: context.tvDp(8)),
                  child: Text(
                    tabs[index],
                    style: TextStyle(
                      fontSize: context.tvSp(17),
                      fontWeight: selected || focused ? FontWeight.w700 : FontWeight.w500,
                      color: focused
                          ? Colors.white
                          : (selected ? Colors.white : TvTheme.textSecondary),
                    ),
                  ),
                ),
              );
            },
          ),
          if (refreshing)
            const LinearProgressIndicator(
              minHeight: 2,
              color: TvTheme.focusColor,
              backgroundColor: Colors.transparent,
            ),
        ],
      ),
    );
  }
}
