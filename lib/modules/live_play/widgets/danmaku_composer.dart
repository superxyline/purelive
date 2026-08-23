import 'package:flutter/services.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/live_play/controllers/live_play_controller.dart';
import 'package:pure_live/modules/live_play/widgets/local_gift_sheet.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller.dart';

/// 弹幕发送输入条（列表输入框 / 全屏控制条共用）。
///
/// 视觉风格统一：isDense、圆角 22、左侧星星按钮（点击弹出当前平台本地礼物面板）、
/// 右侧发送按钮。发送逻辑与直播间一致：
/// - 已登录 B站（当前为 B站直播间）→ 真实发送到 B站服务器；
/// - 否则 → 本地互动回显（需开启本地互动）。
///
/// 全屏控制条内（[videoController] 非空）时：
/// - 输入聚焦期间保持控制条常显（`inputEditing`），不被自动隐藏打断；
/// - 失焦后由控制条 4 秒自动隐藏。
class DanmakuComposer extends StatefulWidget {
  const DanmakuComposer({super.key, required this.controller, this.videoController, this.dark = false});

  final LivePlayController controller;
  final VideoController? videoController;
  final bool dark;

  @override
  State<DanmakuComposer> createState() => _DanmakuComposerState();
}

class _DanmakuComposerState extends State<DanmakuComposer> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _sending = false;

  LivePlayController get controller => widget.controller;

  bool get _inControlBar => widget.videoController != null;

  /// 是否已登录 B站：登录后发送自动切换为真实发送。
  bool get _canSendRealDanmaku =>
      controller.site == Sites.bilibiliSite && SettingsService.to.cookieManager.bilibiliCookie.v.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _input.dispose();
    widget.videoController?.inputEditing.value = false;
    super.dispose();
  }

  void _onFocusChanged() {
    final vc = widget.videoController;
    if (vc == null) return;
    vc.inputEditing.value = _focusNode.hasFocus;
    vc.enableController();
  }

  /// 统一发送入口：B站登录走真实发送，否则本地回显。
  Future<void> _send() async {
    if (_sending) return;
    final text = _input.text.trim();
    if (text.isEmpty) return;
    if (_canSendRealDanmaku) {
      setState(() => _sending = true);
      final ok = await controller.sendLiveDanmaku(text);
      if (!mounted) return;
      if (ok) _input.clear();
      setState(() => _sending = false);
      return;
    }
    final local = controller.localInteractionController;
    if (!local.enabled.v) return;
    controller.emitLocalMessage(
      local.createChat(text, platform: controller.site),
      showAsDanmaku: local.showAsDanmaku.v,
      delay: LivePlayController.localChatDeliveryDelay,
    );
    _input.clear();
    ToastUtil.show(i18n('local_message_queued'));
  }

  /// 点击星星：弹出当前直播间平台的本地礼物面板，可直接发送礼物。
  void _openGiftSheet() {
    final local = controller.localInteractionController;
    if (!local.enabled.v) {
      ToastUtil.show(i18n('local_gift_unavailable'));
      return;
    }
    showLocalGiftSheet(
      context,
      controller: local,
      platform: controller.site,
      onMessage: (message, showAsDanmaku) => controller.emitLocalMessage(message, showAsDanmaku: showAsDanmaku),
    );
  }

  InputDecoration _decoration(ThemeData theme) {
    final hintColor = widget.dark ? Colors.white60 : theme.colorScheme.onSurfaceVariant;
    final fillColor = widget.dark
        ? Colors.white.withValues(alpha: 0.12)
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6);
    return InputDecoration(
      hintText: _canSendRealDanmaku ? i18n('send_danmaku_hint') : i18n('local_message_hint'),
      hintStyle: TextStyle(color: hintColor, fontSize: widget.dark ? 12 : 13),
      counterText: '',
      isDense: true,
      filled: true,
      fillColor: fillColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      prefixIcon: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: IconButton(
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          tooltip: i18n('local_gift_center'),
          onPressed: _openGiftSheet,
          icon: Icon(Icons.auto_awesome_rounded, size: 19, color: hintColor),
        ),
      ),
      suffixIcon: IconButton(
        onPressed: _sending ? null : _send,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        icon: Icon(Icons.send_rounded, size: 18, color: widget.dark ? Colors.white : theme.colorScheme.primary),
        tooltip: _canSendRealDanmaku ? i18n('send') : i18n('local_send_message'),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(widget.dark ? 18 : 20),
        borderSide: BorderSide.none,
      ),
    );
  }

  TextField _field(ThemeData theme) {
    return TextField(
      controller: _input,
      focusNode: _focusNode,
      style: TextStyle(
        color: widget.dark ? Colors.white : theme.colorScheme.onSurface,
        fontSize: widget.dark ? 13 : 14,
      ),
      maxLength: 20,
      textInputAction: TextInputAction.send,
      inputFormatters: [LengthLimitingTextInputFormatter(20)],
      onChanged: (_) {
        if (_inControlBar) widget.videoController!.enableController();
      },
      onSubmitted: (_) => _send(),
      decoration: _decoration(theme),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_inControlBar) {
      return SizedBox(width: 190, height: 38, child: _field(theme));
    }
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: Padding(padding: const EdgeInsets.fromLTRB(10, 8, 8, 8), child: _field(theme)),
      ),
    );
  }
}
