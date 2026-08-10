import 'package:flutter/services.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/live_play/live_play_controller.dart';

/// B站直播间弹幕发送输入条（普通弹幕面板 / 全屏播放器共用）。
class LiveDanmakuInputBar extends StatefulWidget {
  final LivePlayController controller;
  final bool dark;

  const LiveDanmakuInputBar({super.key, required this.controller, this.dark = false});

  @override
  State<LiveDanmakuInputBar> createState() => _LiveDanmakuInputBarState();
}

class _LiveDanmakuInputBarState extends State<LiveDanmakuInputBar> {
  final TextEditingController _input = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _input.dispose();
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color fillColor = widget.dark
        ? Colors.white.withValues(alpha: 0.12)
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6);
    final Color fgColor = widget.dark ? Colors.white : theme.colorScheme.onSurface;
    final Color hintColor = widget.dark ? Colors.white60 : theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: EdgeInsets.only(left: 10, right: 10, top: 6, bottom: widget.dark ? 8 : 6),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              style: TextStyle(color: fgColor, fontSize: 14),
              maxLength: 20,
              textInputAction: TextInputAction.send,
              inputFormatters: [LengthLimitingTextInputFormatter(20)],
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: i18n('send_danmaku_hint'),
                hintStyle: TextStyle(color: hintColor, fontSize: 13),
                counterText: '',
                isDense: true,
                filled: true,
                fillColor: fillColor,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _sending ? null : _send,
            icon: const Icon(Icons.send_rounded, size: 20),
            color: widget.dark ? Colors.white : theme.colorScheme.primary,
            style: IconButton.styleFrom(
              backgroundColor: widget.dark
                  ? Colors.white.withValues(alpha: 0.15)
                  : theme.colorScheme.primary.withValues(alpha: 0.1),
            ),
            tooltip: i18n('send'),
          ),
        ],
      ),
    );
  }
}
