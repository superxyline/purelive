import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:pure_live/common/index.dart';
import 'package:flame_barrage/flame_barrage.dart';
import 'package:pure_live/modules/live_play/controllers/player_state.dart';
import 'package:pure_live/modules/live_play/controllers/live_play_controller.dart';
import 'package:pure_live/modules/live_play/widgets/danmaku_composer.dart';
import 'package:pure_live/modules/live_play/widgets/danmaku_message_actions.dart';

bool isDanmakuUserScrollStart(ScrollNotification notification) {
  return (notification is ScrollStartNotification && notification.dragDetails != null) ||
      (notification is ScrollUpdateNotification && notification.dragDetails != null) ||
      (notification is UserScrollNotification && notification.direction != ScrollDirection.idle);
}

/// 点击礼物卡片：确认后屏蔽该礼物在本直播间的卡片展示。
/// 屏蔽立即生效（已显示的全屏卡片立即消失），可在弹幕"屏蔽列表"中恢复。
Future<void> onGiftCardTap(BuildContext context, LiveMessage message) async {
  final data = message.data is Map ? message.data as Map : const {};
  final giftName = data['giftName']?.toString() ?? '';
  if (giftName.isEmpty) return;
  final theme = Theme.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(i18n('block_gift_card_title'), style: AppTextStyles.t16Bold),
      content: Text(
        i18n('block_gift_card_confirm', args: {'name': giftName}),
        style: AppTextStyles.t14.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(i18n('cancel'), style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.primary),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(i18n('block_gift_card_action')),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  final controller = Get.find<LivePlayController>();
  RoomGiftBlockService.instance.blockGift(controller.site, controller.room.roomId, giftName);
  controller.removeFullscreenGiftsByGiftName(giftName);
  ToastUtil.show(i18n('gift_card_blocked', args: {'name': giftName}));
}

class DanmakuListView extends StatefulWidget {
  final LiveRoom room;

  const DanmakuListView({super.key, required this.room});

  @override
  State<DanmakuListView> createState() => DanmakuListViewState();
}

class DanmakuListViewState extends State<DanmakuListView> {
  final ScrollController _scrollController = createPureLiveScrollController();

  static const Duration throttleDuration = Duration(milliseconds: 80);

  /// 回看历史暂停自动滚动后，无任何操作自动恢复滚动的等待时长。
  static const Duration resumeIdleDelay = Duration(seconds: 10);

  bool userScrolling = false;
  bool _autoScrollEnabled = true;
  Timer? _resumeTimer;
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
    _resumeTimer?.cancel();
    _pendingMessageCount.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> forceScrollToBottom() async {
    if (!mounted || !_autoScrollEnabled) return;
    await SchedulerBinding.instance.endOfFrame;
    if (!mounted || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (!position.hasContentDimensions) {
      // 列表条目数突增（如恢复自动滚动时整体换快照）后的首帧，
      // position 尺寸可能尚未就绪；此时直接放弃会让恢复动作停在旧
      // 位置且不再自动贴底，表现为"恢复了却不滚动"。延迟一帧重试。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) forceScrollToBottom();
      });
      return;
    }
    if ((position.pixels - position.minScrollExtent).abs() > 0.5) {
      _scrollController.jumpTo(position.minScrollExtent);
    }
  }

  void _restartResumeTimer() {
    _resumeTimer?.cancel();
    _resumeTimer = Timer(resumeIdleDelay, () {
      _resumeTimer = null;
      if (mounted && !_autoScrollEnabled) _resumeAutoScroll();
    });
  }

  void _pauseAutoScroll() {
    // 已处于暂停状态时也要重置无操作计时：持续浏览历史期间不能被超时打断。
    _restartResumeTimer();
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
    _resumeTimer?.cancel();
    _resumeTimer = null;
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
    // 阈值放宽到 150px：用户慢速滑回底部时很难精确停在 60px 内，
    // 差一点就永远不满足恢复条件，表现为"滑回底部也不继续滚动"。
    final atBottom = distanceToBottom <= 150;
    // 用户拖动/滚轮：立即暂停自动滚动。拖动初期 offset 仍贴近底部，
    // 此时不能因"贴近底部"而恢复，否则自动滚动会和用户抢滚动条，
    // 表现为列表抖动并弹回底部，无法回看历史弹幕。
    if (isDanmakuUserScrollStart(notification)) {
      _pauseAutoScroll();
      return;
    }
    // 仅在滚动结束/静止后，且仍贴近底部，才恢复自动滚动
    if ((notification is ScrollEndNotification ||
            (notification is UserScrollNotification && notification.direction == ScrollDirection.idle)) &&
        atBottom &&
        !_autoScrollEnabled) {
      _resumeAutoScroll();
    }
  }

  /// 是否已登录 B站：登录后弹幕输入自动切换为真实发送。
  bool get _canSendRealDanmaku =>
      controller.site == Sites.bilibiliSite && SettingsService.to.cookieManager.bilibiliCookie.v.trim().isNotEmpty;

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
              return DanmakuComposer(controller: controller);
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
    if (danmaku.type == LiveMessageType.gift && danmaku.data is Map) {
      return GiftCard(message: danmaku, onTap: () => onGiftCardTap(context, danmaku));
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
                      Stack(
                        children: [
                          // 黑色描底层：保证任何背景色下用户名都清晰可见
                          Text(
                            sc.userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              foreground: Paint()
                                ..style = PaintingStyle.stroke
                                ..strokeWidth = 3
                                ..strokeJoin = StrokeJoin.round
                                ..color = Colors.black,
                            ),
                          ),
                          Text(
                            sc.userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: nameColor, fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '￥${sc.price}',
                        style: TextStyle(color: bottomColor, fontWeight: FontWeight.w800, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Text(_timeText(sc.startTime), style: TextStyle(color: bottomColor, fontSize: 12)),
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

/// 礼物卡片组件（支持B站/抖音/虎牙/斗鱼）
class GiftCard extends StatelessWidget {
  final LiveMessage message;

  /// 液体玻璃样式：模糊背后画面并叠加深色染色渐变（用于全屏视频背景上，
  /// 提升卡片与文字可读性）。弹幕列表等普通背景使用默认样式即可。
  final bool glassEffect;

  /// 点击卡片：弹出"屏蔽该礼物卡片展示"确认框（本直播间维度）
  final VoidCallback? onTap;

  // 非 const：_accentFuture 依赖 message 运行时初始化
  GiftCard({super.key, required this.message, this.glassEffect = false, this.onTap});

  /// 卡片强调色解析：网络礼物且带图标时从图标提取主导色调，
  /// 主色到手前先以平台色兜底渲染，拿到后无感切换。
  late final Future<Color> _accentFuture = _resolveAccent();

  Future<Color> _resolveAccent() {
    final url = _giftIconUrl;
    if (_isLocal || url.isEmpty) return Future.value(_fallbackAccent);
    final cached = _GiftPalette.cached(url);
    if (cached != null) return Future.value(cached);
    return _GiftPalette.resolve(url, _fallbackAccent);
  }

  Map get _data => message.data is Map ? message.data as Map : const {};

  bool get _isLocal => _data['local'] == true;

  String get _platform => _data['platform']?.toString() ?? '';

  /// 兜底强调色：本地礼物用消息自带颜色，网络礼物按平台色
  Color get _fallbackAccent => _GiftPalette.fallbackFor(_platform, _isLocal, message);

  String get _giftName {
    final value = _data['giftName'];
    if (value is String && value.isNotEmpty) return value;
    return i18n('local_gift_center');
  }

  /// 数量解析与控制器共用 LiveMessageGiftX.giftCount，保证两侧一致。
  int get _giftCount => message.giftCount;

  String get _giftIconUrl {
    final value = _data['giftIcon'];
    if (value is String && value.isNotEmpty) return value;
    return '';
  }

  String get _emoji {
    // 优先使用本地礼物的emoji字段
    final localEmoji = _data['emoji'];
    if (localEmoji is String && localEmoji.isNotEmpty) return localEmoji;

    // 根据礼物名称返回对应emoji
    final giftName = _giftName;

    // 通用礼物名称匹配（斗鱼 + 虎牙 + 抖音 + B站）
    if (giftName.contains('火箭')) return '🚀';
    if (giftName.contains('飞机')) return '✈️';
    if (giftName.contains('游艇') || giftName.contains('游轮')) return '🛥️';
    if (giftName.contains('城堡')) return '🏰';
    if (giftName.contains('摩天轮')) return '🎡';
    if (giftName.contains('钻戒') || giftName.contains('戒指')) return '💍';
    if (giftName.contains('花园') || giftName.contains('玫瑰')) return '🌹';
    if (giftName.contains('情书') || giftName.contains('告白')) return '💌';
    if (giftName.contains('守护')) return '🛡️';
    if (giftName.contains('天使')) return '👼';
    if (giftName.contains('恶魔')) return '😈';
    if (giftName.contains('骑士') || giftName.contains('战士')) return '⚔️';
    if (giftName.contains('剑') || giftName.contains('刀')) return '🗡️';
    if (giftName.contains('锤') || giftName.contains('斧')) return '🔨';
    if (giftName.contains('枪') || giftName.contains('炮')) return '🔫';
    if (giftName.contains('炸弹') || giftName.contains('手雷')) return '💣';
    if (giftName.contains('超火') || giftName.contains('火焰')) return '🔥';
    if (giftName.contains('荧光棒') || giftName.contains('棒')) return '🔦';
    if (giftName.contains('办卡') || giftName.contains('卡')) return '💳';
    if (giftName.contains('弱鸡') || giftName.contains('鸡')) return '🐔';
    if (giftName.contains('电影票') || giftName.contains('电影')) return '🎬';
    if (giftName.contains('魔法书') || giftName.contains('书')) return '📖';
    if (giftName.contains('老虎') || giftName.contains('虎牙')) return '🐯';
    if (giftName.contains('鱼')) return '🐟';
    if (giftName.contains('花') || giftName.contains('草')) return '🌸';
    if (giftName.contains('星') || giftName.contains('星星')) return '⭐';
    if (giftName.contains('月') || giftName.contains('月亮')) return '🌙';
    if (giftName.contains('太阳') || giftName.contains('日')) return '☀️';
    if (giftName.contains('彩虹')) return '🌈';
    if (giftName.contains('皇冠')) return '👑';
    if (giftName.contains('钻石')) return '💎';
    if (giftName.contains('蛋糕') || giftName.contains('甜')) return '🍰';
    if (giftName.contains('音乐') || giftName.contains('音符')) return '🎵';
    if (giftName.contains('爱') || giftName.contains('心') || giftName.contains('❤')) return '❤️';

    return '🎁';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Color>(
      future: _accentFuture,
      builder: (context, snapshot) {
        final accentColor = snapshot.data ?? _fallbackAccent;
        return _buildWithAccent(context, accentColor);
      },
    );
  }

  Widget _buildWithAccent(BuildContext context, Color accentColor) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 玻璃版（全屏视频背景）：深色染色渐变底 + 提亮文字，保证可读性；
    // 普通版（弹幕列表）：维持原有低饱和底色与文字颜色。
    final Decoration cardDecoration;
    final Color nameColor;
    final Color infoColor;
    final List<Shadow> textShadows;
    final double iconBgAlpha;
    if (glassEffect) {
      cardDecoration = BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            // 无实时模糊后加深底色补偿可读性（原 0.52/0.64 为配合模糊的值）
            Color.alphaBlend(accentColor.withValues(alpha: 0.30), Colors.black.withValues(alpha: 0.68)),
            Color.alphaBlend(accentColor.withValues(alpha: 0.15), Colors.black.withValues(alpha: 0.78)),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 0.8),
      );
      // 平台色整体偏暗（如抖音红），向白色提亮 35% 保证深色底上可读
      nameColor = Color.lerp(accentColor, Colors.white, 0.35)!;
      infoColor = Colors.white.withValues(alpha: 0.95);
      textShadows = [Shadow(color: Colors.black.withValues(alpha: 0.55), blurRadius: 3)];
      iconBgAlpha = 0.25;
    } else {
      final cardBgColor = isDark
          ? accentColor.withValues(alpha: 0.15)
          : accentColor.withValues(alpha: 0.1);
      cardDecoration = BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accentColor.withValues(alpha: 0.3), width: 0.5),
      );
      nameColor = accentColor;
      infoColor = isDark ? Colors.white70 : Colors.black87;
      textShadows = const [];
      iconBgAlpha = 0.2;
    }

    Widget card = Container(
      decoration: cardDecoration,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 平台色竖条：官方礼物横幅的识别元素，玻璃版才显示。
            // 不加发光阴影——常驻 blur 阴影在多卡片堆叠时是持续合成负担。
            if (glassEffect)
              Container(
                width: 4,
                height: 40,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(color: accentColor, borderRadius: BorderRadius.circular(2)),
              ),
            // 礼物图标（优先使用网络图片，否则使用emoji）
            Container(
              width: glassEffect ? 44 : 36,
              height: glassEffect ? 44 : 36,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: iconBgAlpha),
                borderRadius: BorderRadius.circular(glassEffect ? 10 : 8),
              ),
              child: _giftIconUrl.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(glassEffect ? 10 : 8),
                      child: Image.network(
                        _giftIconUrl,
                        width: glassEffect ? 44 : 36,
                        height: glassEffect ? 44 : 36,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => Center(
                          child: Text(_emoji, style: TextStyle(fontSize: glassEffect ? 24 : 20)),
                        ),
                      ),
                    )
                  : Center(
                      child: Text(
                        _emoji,
                        style: TextStyle(fontSize: glassEffect ? 24 : 20),
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            // 用户名和礼物信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 用户名
                  Text(
                    message.userName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: nameColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      shadows: textShadows,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // 礼物信息
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${i18n('local_sent_gift')} ',
                          style: TextStyle(color: infoColor, fontSize: 12, shadows: textShadows),
                        ),
                        TextSpan(
                          text: _giftName,
                          style: TextStyle(
                            color: infoColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            shadows: textShadows,
                          ),
                        ),
                        // 数量用平台色强调；玻璃版（全屏）在数量合并时做跳动动画
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: glassEffect
                              ? AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 250),
                                  transitionBuilder: (child, animation) => ScaleTransition(
                                    scale: Tween<double>(begin: 1.6, end: 1.0).animate(
                                      CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
                                    ),
                                    child: child,
                                  ),
                                  child: Text(
                                    ' ×$_giftCount',
                                    key: ValueKey(_giftCount),
                                    style: TextStyle(
                                      color: accentColor,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      shadows: textShadows,
                                    ),
                                  ),
                                )
                              : Text(
                                  ' ×$_giftCount',
                                  style: TextStyle(
                                    color: accentColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    shadows: textShadows,
                                  ),
                                ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (onTap != null) {
      card = GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: card);
    }

    if (!glassEffect) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: card,
      );
    }
    // 原为 BackdropFilter(blur 16) 实时模糊背后画面——它是 Flutter 中
    // 开销最高的特效之一，多张卡片堆叠时每帧多次离屏渲染+高斯采样，
    // 弹幕越多越卡。现改用加深的不透明染色渐变保证可读性，不再实时模糊。
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: card,
    );
  }
}

/// 礼物卡片强调色解析：从礼物图标图片提取主导色调（饱和度加权的
/// 色相圆周平均），让卡片底色/竖条/数量色跟随礼物本身的颜色而非
/// 固定平台色。结果按图标 URL 缓存，同一礼物只解码一次。
class _GiftPalette {
  _GiftPalette._();

  static final Map<String, Color> _cache = {};

  /// 兜底强调色：本地礼物用消息自带颜色，网络礼物按平台色
  static Color fallbackFor(String platform, bool isLocal, LiveMessage message) {
    if (isLocal) {
      return Color.fromARGB(255, message.color.r, message.color.g, message.color.b);
    }
    switch (platform) {
      case 'bilibili':
        return const Color(0xFFFF6B35); // B站橙
      case 'douyin':
        return const Color(0xFFFF2C55); // 抖音红
      default:
        return const Color(0xFFFFC107); // 默认金（虎牙/斗鱼等）
    }
  }

  static Color? cached(String url) => _cache[url];

  static Future<Color> resolve(String url, Color fallback) async {
    final cached = _cache[url];
    if (cached != null) return cached;

    Color result = fallback;
    try {
      // 礼物图标 CDN 同样有 referer 防盗链（B站等），与封面图共用请求头
      final provider = NetworkImage(normalizeNetworkImageUrl(url), headers: networkImageHeaders(url));
      final stream = provider.resolve(ImageConfiguration.empty);
      final completer = Completer<ui.Image?>();
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          if (!completer.isCompleted) completer.complete(info.image);
          stream.removeListener(listener);
        },
        onError: (_, _) {
          if (!completer.isCompleted) completer.complete(null);
          stream.removeListener(listener);
        },
      );
      stream.addListener(listener);
      final image = await completer.future.timeout(const Duration(seconds: 3), onTimeout: () => null);
      final dominant = image == null ? null : await _dominantHueColor(image);
      if (dominant != null) result = dominant;
    } catch (_) {
      // 提取失败按兜底色缓存，避免同一图标反复解码
    }
    _cache[url] = result;
    return result;
  }

  /// 降采样遍历像素，跳过近黑/近白/低饱和像素（避免白色横幅底、
  /// 深色描边拉偏色调），以饱和度为权重做色相圆周平均，
  /// 再以固定饱和度/亮度输出，保证作为卡片强调色观感稳定。
  static Future<Color?> _dominantHueColor(ui.Image image) async {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bytes == null) return null;
    final data = bytes.buffer.asUint8List();
    final w = image.width;
    final h = image.height;
    final stepX = math.max(1, w ~/ 32);
    final stepY = math.max(1, h ~/ 32);
    double sinSum = 0;
    double cosSum = 0;
    double weightSum = 0;
    for (var py = 0; py < h; py += stepY) {
      for (var px = 0; px < w; px += stepX) {
        final i = (py * w + px) * 4;
        if (i + 3 >= data.length) break;
        final alpha = data[i + 3];
        if (alpha < 128) continue;
        final hsl = HSLColor.fromColor(Color.fromARGB(alpha, data[i], data[i + 1], data[i + 2]));
        if (hsl.lightness < 0.12 || hsl.lightness > 0.90 || hsl.saturation < 0.20) continue;
        final rad = hsl.hue * math.pi / 180;
        final weight = hsl.saturation;
        sinSum += math.sin(rad) * weight;
        cosSum += math.cos(rad) * weight;
        weightSum += weight;
      }
    }
    if (weightSum <= 0) return null;
    var hue = math.atan2(sinSum, cosSum) * 180 / math.pi;
    if (hue < 0) hue += 360;
    return HSLColor.fromAHSL(1.0, hue, 0.62, 0.55).toColor();
  }
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
