import 'package:flutter/services.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller.dart';

/// B站直播间弹幕发送输入条，放在播放器底部控制条内（与弹幕开关/设置同排）。
class LiveDanmakuInputBar extends StatefulWidget {
  final VideoController controller;

  const LiveDanmakuInputBar({super.key, required this.controller});

  @override
  State<LiveDanmakuInputBar> createState() => _LiveDanmakuInputBarState();
}

class _LiveDanmakuInputBarState extends State<LiveDanmakuInputBar> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _sending = false;
  Worker? _hideWorker;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        widget.controller.enableController();
      }
    });
    // 控制条隐藏时收起输入焦点，避免焦点残留影响返回键。
    _hideWorker = ever(widget.controller.showController, (visible) {
      if (!visible && _focusNode.hasFocus) {
        _focusNode.unfocus();
      }
    });
  }

  @override
  void dispose() {
    _hideWorker?.dispose();
    _focusNode.dispose();
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    final text = _input.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    final ok = await widget.controller.livePlayController.sendLiveDanmaku(text);
    if (!mounted) return;
    if (ok) _input.clear();
    setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 168,
      height: 36,
      child: TextField(
        controller: _input,
        focusNode: _focusNode,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        maxLength: 20,
        textInputAction: TextInputAction.send,
        inputFormatters: [LengthLimitingTextInputFormatter(20)],
        onChanged: (_) => widget.controller.enableController(),
        onSubmitted: (_) => _send(),
        decoration: InputDecoration(
          hintText: i18n('send_danmaku_hint'),
          hintStyle: const TextStyle(color: Colors.white60, fontSize: 12),
          counterText: '',
          isDense: true,
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.12),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          suffixIcon: IconButton(
            onPressed: _sending ? null : _send,
            icon: const Icon(Icons.send_rounded, size: 16, color: Colors.white),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}
