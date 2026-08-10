import 'package:flutter/services.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/live_play/live_play_controller.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller.dart';

/// B站直播间弹幕发送输入条。
///
/// 竖屏时独立放在弹幕列表底部（播放器外，videoController 为空）；
/// 全屏时嵌入播放器底部控制条（videoController 非空），输入期间保持控制条可见。
class LiveDanmakuInputBar extends StatefulWidget {
  final LivePlayController controller;
  final VideoController? videoController;
  final bool dark;

  const LiveDanmakuInputBar({
    super.key,
    required this.controller,
    this.videoController,
    this.dark = false,
  });

  @override
  State<LiveDanmakuInputBar> createState() => _LiveDanmakuInputBarState();
}

class _LiveDanmakuInputBarState extends State<LiveDanmakuInputBar> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _sending = false;
  Worker? _hideWorker;

  bool get _inControlBar => widget.videoController != null;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      final vc = widget.videoController;
      if (vc == null) return;
      if (_focusNode.hasFocus) {
        // 全屏控制条内输入时禁止自动隐藏，避免输入被中断。
        vc.inputEditing.value = true;
        vc.enableController();
      } else {
        vc.inputEditing.value = false;
        vc.enableController();
      }
    });
    if (_inControlBar) {
      _hideWorker = ever(widget.videoController!.showController, (visible) {
        if (!visible && _focusNode.hasFocus) {
          _focusNode.unfocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _hideWorker?.dispose();
    _focusNode.dispose();
    _input.dispose();
    widget.videoController?.inputEditing.value = false;
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    final text = _input.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    final ok = await widget.controller.sendLiveDanmaku(text);
    if (!mounted) return;
    if (ok) _input.clear();
    setState(() => _sending = false);
  }

  InputDecoration _decoration(ThemeData theme, Color fgColor, Color hintColor, {bool showSendIcon = false}) {
    return InputDecoration(
      hintText: i18n('send_danmaku_hint'),
      hintStyle: TextStyle(color: hintColor, fontSize: widget.dark ? 12 : 13),
      counterText: '',
      isDense: true,
      filled: true,
      fillColor: widget.dark
          ? Colors.white.withValues(alpha: 0.12)
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      suffixIcon: showSendIcon
          ? IconButton(
              onPressed: _sending ? null : _send,
              icon: Icon(Icons.send_rounded, size: 16, color: widget.dark ? Colors.white : theme.colorScheme.primary),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            )
          : null,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(widget.dark ? 18 : 20),
        borderSide: BorderSide.none,
      ),
    );
  }

  TextField _field(ThemeData theme) {
    final fgColor = widget.dark ? Colors.white : theme.colorScheme.onSurface;
    final hintColor = widget.dark ? Colors.white60 : theme.colorScheme.onSurfaceVariant;
    return TextField(
      controller: _input,
      focusNode: _focusNode,
      style: TextStyle(color: fgColor, fontSize: widget.dark ? 13 : 14),
      maxLength: 20,
      textInputAction: TextInputAction.send,
      inputFormatters: [LengthLimitingTextInputFormatter(20)],
      onChanged: (_) {
        if (_inControlBar) widget.videoController!.enableController();
      },
      onSubmitted: (_) => _send(),
      decoration: _decoration(theme, fgColor, hintColor, showSendIcon: _inControlBar),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_inControlBar) {
      return SizedBox(width: 168, height: 36, child: _field(theme));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Row(
        children: [
          Expanded(child: _field(theme)),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _sending ? null : _send,
            icon: const Icon(Icons.send_rounded, size: 20),
            color: theme.colorScheme.primary,
            style: IconButton.styleFrom(
              backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
            ),
            tooltip: i18n('send'),
          ),
        ],
      ),
    );
  }
}
