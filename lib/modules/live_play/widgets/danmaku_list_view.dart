import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:pure_live/common/index.dart';
import 'package:flame_barrage/flame_barrage.dart';
import 'package:pure_live/modules/live_play/controllers/player_state.dart';
import 'package:pure_live/modules/live_play/controllers/live_play_controller.dart';
import 'package:pure_live/modules/live_play/widgets/danmaku_message_actions.dart';

bool isDanmakuUserScrollStart(ScrollNotification notification) {
  return (notification is ScrollStartNotification && notification.dragDetails != null) ||
      (notification is ScrollUpdateNotification && notification.dragDetails != null) ||
      (notification is UserScrollNotification && notification.direction != ScrollDirection.idle);
}

class DanmakuListView extends StatefulWidget {
  final LiveRoom room;

  const DanmakuListView({super.key, required this.room});

  @override
  State<DanmakuListView> createState() => DanmakuListViewState();
}

class DanmakuListViewState extends State<DanmakuListView> {
  final ScrollController _scrollController = createPureLiveScrollController();
  final TextEditingController _composerController = TextEditingController();

  static const Duration throttleDuration = Duration(milliseconds: 80);

  bool userScrolling = false;
  bool _autoScrollEnabled = true;
  final ValueNotifier<int> _pendingMessageCount = ValueNotifier<int>(0);
  int _lastControllerLength = 0;
  LiveMessage? _lastControllerTail;
  List<LiveMessage> _visibleMessages = const [];
  List<LiveMessage>? _scheduledSnapshot;

  Timer? throttleTimer;
  Worker? fullscreenWorker;
  Worker? windowFullscreenWorker;
  Worker? superChatWorker;
  StreamSubscription? messagesSub;

  LivePlayController get controller => Get.find<LivePlayController>();

  @override
  void initState() {
    super.initState();
    _visibleMessages = List<LiveMessage>.from(controller.danmakuMessages);
    _lastControllerLength = _visibleMessages.length;
    _lastControllerTail = _visibleMessages.isEmpty ? null : _visibleMessages.last;

    messagesSub = controller.danmakuMessages.listen((_) => _onMessagesChanged());

    fullscreenWorker = ever(GlobalPlayerState.to.isFullscreen, (value) {
      if (value == false && _autoScrollEnabled) {
        WidgetsBinding.instance.addPostFrameCallback((_) => forceScrollToBottom());
      }
    });

    windowFullscreenWorker = ever(GlobalPlayerState.to.isWindowFullscreen, (value) {
      if (value == false && _autoScrollEnabled) {
        WidgetsBinding.instance.addPostFrameCallback((_) => forceScrollToBottom());
      }
    });

    // 醒目留言显示开关变化时刷新列表（不依赖响应式组件包裹，避免破坏列表更新）
    superChatWorker = ever(SettingsService.to.danmaku.showSuperChat, (_) {
      if (mounted) setState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => forceScrollToBottom());
  }

  void _onMessagesChanged() {
    if (!mounted) return;
    final snapshot = List<LiveMessage>.from(controller.danmakuMessages);
    final nextTail = snapshot.isEmpty ? null : snapshot.last;
    final tailChanged = !identical(nextTail, _lastControllerTail);
    final lengthDelta = snapshot.length - _lastControllerLength;
    final addedCount = lengthDelta > 0 ? lengthDelta : (tailChanged ? 1 : 0);
    _lastControllerLength = snapshot.length;
    _lastControllerTail = nextTail;

    if (!_autoScrollEnabled) {
      if (addedCount > 0) {
        _pendingMessageCount.value = (_pendingMessageCount.value + addedCount).clamp(0, 9999);
      }
      return;
    }

    if (nextTail?.isLocal == true && addedCount > 0) {
      throttleTimer?.cancel();
      throttleTimer = null;
      _scheduledSnapshot = null;
      setState(() => _visibleMessages = snapshot);
      WidgetsBinding.instance.addPostFrameCallback((_) => forceScrollToBottom());
      return;
    }

    _scheduledSnapshot = snapshot;
    throttleTimer ??= Timer(throttleDuration, () {
      throttleTimer = null;
      if (!mounted || !_autoScrollEnabled) return;
      final next = _scheduledSnapshot;
      _scheduledSnapshot = null;
      if (next != null) setState(() => _visibleMessages = next);
      WidgetsBinding.instance.addPostFrameCallback((_) => forceScrollToBottom());
    });
  }

  @override
  void dispose() {
    messagesSub?.cancel();
    fullscreenWorker?.dispose();
    windowFullscreenWorker?.dispose();
    superChatWorker?.dispose();
    throttleTimer?.cancel();
    _composerController.dispose();
    _pendingMessageCount.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> forceScrollToBottom() async {
    if (!mounted || !_autoScrollEnabled) return;
    await SchedulerBinding.instance.endOfFrame;
    if (!mounted || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (!position.hasContentDimensions) return;
    if ((position.pixels - position.minScrollExtent).abs() > 0.5) {
      _scrollController.jumpTo(position.minScrollExtent);
    }
  }

  void _pauseAutoScroll() {
    if (!_autoScrollEnabled) return;
    throttleTimer?.cancel();
    throttleTimer = null;
    _scheduledSnapshot = null;
    setState(() {
      _autoScrollEnabled = false;
      userScrolling = true;
    });
    _pendingMessageCount.value = 0;
  }

  Future<void> _resumeAutoScroll() async {
    setState(() {
      _visibleMessages = List<LiveMessage>.from(controller.danmakuMessages);
      _autoScrollEnabled = true;
      userScrolling = false;
    });
    _lastControllerLength = controller.danmakuMessages.length;
    _pendingMessageCount.value = 0;
    await forceScrollToBottom();
  }

  void onScrollNotification(ScrollNotification notification) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final distanceToBottom = position.pixels - position.minScrollExtent;

    // A UserScrollNotification is emitted before the first drag has produced a
    // useful pixel distance. Waiting for a 24 px offset let the 80 ms live
    // update jump the list back to the bottom, so Android users had to swipe
    // repeatedly. Claim a real drag (or mouse wheel) immediately.
    if (isDanmakuUserScrollStart(notification)) {
      _pauseAutoScroll();
    } else if ((notification is ScrollEndNotification ||
            (notification is UserScrollNotification && notification.direction == ScrollDirection.idle)) &&
        distanceToBottom <= 12 &&
        !_autoScrollEnabled) {
      _resumeAutoScroll();
    }
  }

  /// 是否已登录 B站：登录后弹幕输入自动切换为真实发送。
  bool get _canSendRealDanmaku =>
      controller.site == Sites.bilibiliSite &&
      SettingsService.to.cookieManager.bilibiliCookie.v.trim().isNotEmpty;

  /// 真实发送到 B站服务器，成功后由服务器弹幕回包自然显示。
  Future<void> _sendRealDanmaku() async {
    final text = _composerController.text.trim();
    if (text.isEmpty) return;
    final ok = await controller.sendLiveDanmaku(text);
    if (ok && mounted) _composerController.clear();
  }

  void _sendLocalMessage() {
    final text = _composerController.text.trim();
    final local = controller.localInteractionController;
    if (!local.enabled.v || text.isEmpty) return;
    controller.emitLocalMessage(
      local.createChat(text, platform: controller.site),
      showAsDanmaku: local.showAsDanmaku.v,
      delay: LivePlayController.localChatDeliveryDelay,
    );
    _composerController.clear();
    ToastUtil.show(i18n('local_message_queued'));
  }

  /// 统一入口：已登录 B站走真实发送，否则本地回显。
  void _onSendPressed() {
    if (_canSendRealDanmaku) {
      _sendRealDanmaku();
    } else {
      _sendLocalMessage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
      decoration: BoxDecoration(
        color: Get.theme.colorScheme.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Get.theme.colorScheme.outline.withValues(alpha: 0.02), width: 0.5),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      onScrollNotification(notification);
                      return false;
                    },
                    child: ListView.builder(
                      key: const ValueKey('danmaku-message-list'),
                      addAutomaticKeepAlives: false,
                      addRepaintBoundaries: true,
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                      scrollCacheExtent: const ScrollCacheExtent.pixels(360),
                      itemCount: _visibleMessages.length,
                      itemBuilder: (_, index) {
                        final msg = _visibleMessages[_visibleMessages.length - 1 - index];
                        final showSC = SettingsService.to.danmaku.showSuperChat.v;
                        if (msg.type == LiveMessageType.superChat && !showSC) {
                          return const SizedBox.shrink();
                        }
                        return DanmakuItem(key: ObjectKey(msg), danmaku: msg);
                      },
                    ),
                  ),
                  if (userScrolling)
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: FilledButton.icon(
                        key: const ValueKey('danmaku-resume-live'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          backgroundColor: Get.theme.colorScheme.primary.withValues(alpha: 0.92),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                        label: ValueListenableBuilder<int>(
                          valueListenable: _pendingMessageCount,
                          builder: (context, count, _) => Text(
                            count > 0
                                ? i18n('danmaku_new_messages', args: {'count': '$count'})
                                : i18n('scroll_to_bottom'),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        onPressed: _resumeAutoScroll,
                      ),
                    ),
                ],
              ),
            ),
            Obx(() {
              final local = controller.localInteractionController;
              // 本地互动开启，或已登录 B站可真实发送弹幕时，显示输入框。
              if (!local.enabled.v && !_canSendRealDanmaku) return const SizedBox.shrink();
              return Material(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _composerController,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _onSendPressed(),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: _canSendRealDanmaku ? i18n('send_danmaku_hint') : i18n('local_message_hint'),
                              prefixIcon: Icon(
                                _canSendRealDanmaku ? Icons.chat_bubble_outline_rounded : Icons.auto_awesome_rounded,
                                size: 19,
                              ),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(22)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton.filled(
                          tooltip: _canSendRealDanmaku ? i18n('send') : i18n('local_send_message'),
                          onPressed: _onSendPressed,
                          icon: const Icon(Icons.send_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class DanmakuItem extends StatelessWidget {
  final LiveMessage danmaku;

  const DanmakuItem({super.key, required this.danmaku});

  Future<void> _copyMessage() async {
    await Clipboard.setData(ClipboardData(text: "${danmaku.userName}: ${danmaku.message}"));
    ToastUtil.show(i18n('copied_to_clipboard'));
  }

  Future<void> _showActions(BuildContext context) => DanmakuMessageActions.show(context, danmaku);

  @override
  Widget build(BuildContext context) {
    if (danmaku.type == LiveMessageType.superChat && danmaku.data is LiveSuperChatMessage) {
      return SuperChatCard(sc: danmaku.data as LiveSuperChatMessage);
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final baseColor = Color.fromARGB(255, danmaku.color.r, danmaku.color.g, danmaku.color.b);

    final vibrantColor =
        baseColor.toARGB32() == Colors.white.toARGB32() || baseColor.toARGB32() == Colors.black.toARGB32()
        ? (isDark ? Colors.white : Colors.black)
        : HSLColor.fromColor(baseColor).withLightness(isDark ? 0.75 : 0.52).withSaturation(1).toColor();

    final cardBgColor = isDark ? theme.cardColor.withValues(alpha: 0.65) : Colors.white.withValues(alpha: 0.72);

    final textColor = isDark ? Colors.white70 : Colors.black87;

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: cardBgColor, // 动态背景色
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: vibrantColor.withValues(alpha: 0.08), width: 0.5),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 6, right: 10),
                  decoration: BoxDecoration(color: vibrantColor, shape: BoxShape.circle),
                ),

                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onSecondaryTap: () => _showActions(context),
                    onLongPress: () => _showActions(context),
                    onDoubleTap: _copyMessage,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: "${danmaku.userName}: ",
                            style: AppTextStyles.t14.copyWith(fontWeight: FontWeight.w700, color: textColor),
                          ),
                          TextSpan(
                            children: parseEmojis(danmaku.message, AppTextStyles.t14.fontSize!, textColor),
                            style: AppTextStyles.t14.copyWith(
                              height: 1.45,
                              fontWeight: FontWeight.w500,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SuperChatCard extends StatelessWidget {
  final LiveSuperChatMessage sc;

  const SuperChatCard({super.key, required this.sc});

  Color _color(String? hex, Color fallback) {
    if (hex == null || hex.isEmpty) return fallback;
    var value = hex.trim();
    if (!value.startsWith('#')) value = '#$value';
    try {
      return HexColor(value);
    } catch (_) {
      return fallback;
    }
  }

  String _timeText(DateTime time) {
    String two(int v) => v.toString().padLeft(2, '0');
    final hm = '${two(time.hour)}:${two(time.minute)}';
    final now = DateTime.now();
    final sameDay = time.year == now.year && time.month == now.month && time.day == now.day;
    return sameDay ? hm : '${two(time.month)}-${two(time.day)} $hm';
  }

  @override
  Widget build(BuildContext context) {
    final bottomColor = _color(sc.backgroundBottomColor, const Color(0xFF2A60B2));
    final bgColor = _color(sc.backgroundColor, const Color(0xFFEDF5FF));
    final fontColor = _color(sc.messageFontColor, Colors.white);
    final nameColor = _color(sc.nameColor, Colors.white);

    Widget placeholder() => Container(
      width: 40,
      height: 40,
      color: Colors.black26,
      child: const Icon(Icons.person, color: Colors.white70),
    );

    final avatar = ClipOval(
      child: sc.face.isEmpty
          ? placeholder()
          : CachedNetworkImage(
              imageUrl: sc.face,
              width: 40,
              height: 40,
              fit: BoxFit.cover,
              placeholder: (_, _) => placeholder(),
              errorWidget: (_, _, _) => placeholder(),
            ),
    );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: bottomColor, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            color: bgColor,
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                avatar,
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        sc.userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: nameColor, fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '￥${sc.price}',
                        style: TextStyle(color: bottomColor, fontWeight: FontWeight.w800, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Text(
                  _timeText(sc.startTime),
                  style: TextStyle(color: bottomColor, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            color: bottomColor,
            padding: const EdgeInsets.all(10),
            child: Text.rich(
              TextSpan(children: parseEmojis(sc.message, 14, fontColor)),
              style: TextStyle(color: fontColor, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

final Map<String, List<EmojiToken>> emojiCache = {};

class EmojiToken {
  final bool isEmoji;
  final String value;

  const EmojiToken({required this.isEmoji, required this.value});
}

List<EmojiToken> _parseEmojiTokens(String text) {
  final cached = emojiCache[text];
  if (cached != null) {
    return cached;
  }

  final regex = EmojiAtlas.instance.regex;

  if (regex == null) {
    return [EmojiToken(isEmoji: false, value: text)];
  }

  final tokens = <EmojiToken>[];

  int last = 0;

  for (final match in regex.allMatches(text)) {
    if (match.start > last) {
      tokens.add(EmojiToken(isEmoji: false, value: text.substring(last, match.start)));
    }

    tokens.add(EmojiToken(isEmoji: true, value: match.group(0)!));

    last = match.end;
  }

  if (last < text.length) {
    tokens.add(EmojiToken(isEmoji: false, value: text.substring(last)));
  }

  emojiCache[text] = tokens;

  return tokens;
}

List<InlineSpan> parseEmojis(String text, double size, Color color) {
  final tokens = _parseEmojiTokens(text);

  final spans = <InlineSpan>[];

  final style = TextStyle(fontSize: size, color: color);

  final emojiSize = size * 1.25;

  for (final token in tokens) {
    if (!token.isEmoji) {
      spans.add(TextSpan(text: token.value, style: style));
      continue;
    }

    final info = EmojiAtlas.instance.find(token.value);
    final image = info != null ? EmojiAtlas.instance.image(info.id) : null;

    if (image == null) {
      spans.add(TextSpan(text: token.value, style: style));
      continue;
    }

    spans.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: RawImage(image: image, width: emojiSize, height: emojiSize),
      ),
    );
  }

  return spans;
}

class EmojiPainter extends CustomPainter {
  final ui.Image image;

  EmojiPainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = true;

    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant EmojiPainter oldDelegate) {
    return oldDelegate.image != image;
  }
}
