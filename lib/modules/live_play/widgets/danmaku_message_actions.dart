import 'dart:ui' show ImageFilter;

import 'package:flutter/services.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/live_play/controllers/live_play_controller.dart';
import 'package:pure_live/modules/live_play/states/ui_state.dart';

class DanmakuMessageActions {
  DanmakuMessageActions._();

  /// 面板布局选择：
  /// - 手机非全屏：底部弹窗（保持原交互）；
  /// - 全屏（手机/平板）：从画面右侧滑出的窄面板（毛玻璃质感）；
  /// - 平板非全屏：覆盖右侧弹幕列表的窄面板。
  static bool _shouldUseRightPanel() {
    if (Get.width > 680) return true;
    try {
      if (Get.isRegistered<LivePlayController>() &&
          Get.find<LivePlayController>().state.value.ui.screenMode == VideoMode.fullscreen) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  static Future<void> show(BuildContext context, LiveMessage message) async {
    if (_shouldUseRightPanel()) {
      final theme = Theme.of(context);
      // 右侧窄面板：全屏/平板下不遮挡主画面。
      // 毛玻璃质感：背景模糊 + 半透明主题色底 + 细描边（全屏视频上微微透出画面）。
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black54,
        builder: (sheetContext) => Dialog(
          alignment: Alignment.centerRight,
          insetPadding: const EdgeInsets.symmetric(vertical: 48),
          backgroundColor: Colors.transparent,
          child: SafeArea(
            child: Container(
              width: 280,
              clipBehavior: Clip.antiAlias,
              constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.92),
              decoration: ShapeDecoration(
                color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.72),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35)),
                ),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _buildEntries(context, sheetContext, message),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      return;
    }

    // 手机非全屏：底部弹窗（跟随主题 bottomSheetTheme：圆角24 + 拖动手柄）
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.85),
          child: SingleChildScrollView(child: Wrap(children: _buildEntries(context, sheetContext, message))),
        ),
      ),
    );
  }
}

/// 菜单头部：展示被点击的弹幕内容（用户名 / 等级徽章 / 消息正文）。
/// 底部弹窗与右侧面板共用，风格随主题。
Widget _buildMessageHeader(BuildContext context, LiveMessage message) {
  final theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                message.userName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (message.userLevel.isNotEmpty) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Lv.${message.userLevel}',
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(message.message, style: theme.textTheme.bodyMedium?.copyWith(height: 1.3)),
        const SizedBox(height: 10),
        Divider(height: 1, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ],
    ),
  );
}

/// 菜单条目（底部弹窗与右侧面板共用）
List<Widget> _buildEntries(BuildContext context, BuildContext sheetContext, LiveMessage message) {
  final actions = <Widget>[
    ListTile(
      leading: const Icon(Icons.copy_all_rounded),
      title: Text(i18n('copy')),
      onTap: () async {
        Navigator.of(sheetContext).pop();
        await Clipboard.setData(ClipboardData(text: '${message.userName}: ${message.message}'));
        ToastUtil.show(i18n('copied_to_clipboard'));
      },
    ),
    ListTile(
      leading: const Icon(Icons.plus_one_rounded),
      title: Text(i18n('danmaku_plus_one')),
      subtitle: Text(message.message, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () async {
        Navigator.of(sheetContext).pop();
        await sendPlusOne(message);
      },
    ),
    if (!message.isLocal && message.userName.trim().isNotEmpty)
      ListTile(
        leading: const Icon(Icons.person_off_rounded),
        title: Text(i18n('block_danmaku_user')),
        subtitle: Text(message.userName, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: () {
          SettingsService.to.fav.addBlockedDanmakuUser(message.userName);
          if (Get.isRegistered<LivePlayController>()) {
            Get.find<LivePlayController>().removeDanmakuWhere(
              (item) => item.userName.trim().toLowerCase() == message.userName.trim().toLowerCase(),
            );
          }
          Navigator.of(sheetContext).pop();
          ToastUtil.show(i18n('danmaku_user_blocked'));
        },
      ),
    ListTile(
      leading: const Icon(Icons.filter_alt_rounded),
      title: Text(i18n('block_danmaku_keyword')),
      subtitle: Text(message.message, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () {
        Navigator.of(sheetContext).pop();
        showKeywordDialog(context, message.message);
      },
    ),
  ];

  return [
    _buildMessageHeader(context, message),
    // 操作项左右内边距，让主题自带的 ListTile 圆角悬浮效果完整呈现
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: actions),
    ),
    const SizedBox(height: 8),
  ];
}

/// 加一：把该条弹幕内容直接发出去。
///
/// 已登录 B站（且当前为 B站直播间）时真实发送到 B站服务器；
/// 否则走本地互动回显（需要开启本地互动）。两者都不可用时给出提示。
Future<void> sendPlusOne(LiveMessage message) async {
  final text = message.message.trim();
  if (text.isEmpty) return;
  if (!Get.isRegistered<LivePlayController>()) return;
  final controller = Get.find<LivePlayController>();
  final canSendReal =
      controller.site == Sites.bilibiliSite && SettingsService.to.cookieManager.bilibiliCookie.v.trim().isNotEmpty;
  if (canSendReal) {
    await controller.sendLiveDanmaku(text);
    return;
  }
  final local = controller.localInteractionController;
  if (!local.enabled.v) {
    ToastUtil.show(i18n('danmaku_plus_one_unavailable'));
    return;
  }
  controller.emitLocalMessage(
    local.createChat(text, platform: controller.site),
    showAsDanmaku: local.showAsDanmaku.v,
    delay: LivePlayController.localChatDeliveryDelay,
  );
  ToastUtil.show(i18n('local_message_queued'));
}

/// 将弹幕内容按标点和空格分词
List<String> _tokenizeDanmaku(String text) {
  if (text.trim().isEmpty) return [];
  // 按中英文标点、空格分隔，过滤空串
  final tokens = text
      .split(RegExp(r'[，。！？、；：""''「」【】（）\s,\.!?;:\'"()\[\]{}]+'))
      .where((t) => t.trim().isNotEmpty)
      .toList();
  return tokens;
}

/// 添加屏蔽词并清除已匹配弹幕
void _applyBlockedKeywords(List<String> keywords) {
  for (final kw in keywords) {
    final trimmed = kw.trim();
    if (trimmed.isEmpty) continue;
    SettingsService.to.fav.addShieldList(trimmed);
    if (Get.isRegistered<LivePlayController>()) {
      Get.find<LivePlayController>().removeDanmakuWhere(
            (item) => item.message.toLowerCase().contains(trimmed.toLowerCase()),
          );
    }
  }
}

Future<void> showKeywordDialog(BuildContext context, String message) async {
  final result = await showDialog<List<String>>(
    context: context,
    builder: (dialogContext) => _KeywordBlockDialog(message: message),
  );
  if (result == null || result.isEmpty) return;
  _applyBlockedKeywords(result);
  ToastUtil.show(i18n('danmaku_keyword_blocked'));
}

/// 关键词屏蔽对话框：分词点选 + 手动输入
class _KeywordBlockDialog extends StatefulWidget {
  final String message;
  const _KeywordBlockDialog({required this.message});

  @override
  State<_KeywordBlockDialog> createState() => _KeywordBlockDialogState();
}

class _KeywordBlockDialogState extends State<_KeywordBlockDialog> {
  late final List<String> _tokens;
  late final Set<int> _selected;
  final TextEditingController _inputController = TextEditingController();
  final Set<String> _manualKeywords = {};

  @override
  void initState() {
    super.initState();
    _tokens = _tokenizeDanmaku(widget.message);
    _selected = {};
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  void _confirm() {
    final result = <String>[
      // 分词选中的
      ..._selected.map((i) => _tokens[i]),
      // 手动输入的
      ..._manualKeywords,
    ];
    Navigator.of(context).pop(result);
  }

  void _addManualKeyword() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    if (_manualKeywords.add(text)) {
      _inputController.clear();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasTokens = _tokens.isNotEmpty;

    return AlertDialog(
      title: Text(i18n('block_danmaku_keyword')),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 分词选择区
              if (hasTokens) ...[
                Text(
                  i18n('tap_to_select_keyword'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: List.generate(_tokens.length, (i) {
                    final isSelected = _selected.contains(i);
                    return FilterChip(
                      label: Text(_tokens[i]),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selected.add(i);
                          } else {
                            _selected.remove(i);
                          }
                        });
                      },
                    );
                  }),
                ),
                const SizedBox(height: 12),
                Divider(color: theme.colorScheme.outlineVariant),
                const SizedBox(height: 12),
              ],

              // 手动输入区
              Text(
                i18n('or_enter_custom_keyword'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              // 格式说明
              Text(
                i18n('keyword_format_hint'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _inputController,
                maxLength: 40,
                decoration: InputDecoration(
                  hintText: i18n('please_enter_keyword'),
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                    onPressed: _addManualKeyword,
                    tooltip: i18n('add'),
                  ),
                ),
                onSubmitted: (_) => _addManualKeyword(),
              ),

              // 已添加的手动关键词列表
              if (_manualKeywords.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _manualKeywords.map((kw) {
                    return Chip(
                      label: Text(kw, style: const TextStyle(fontSize: 12)),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      onDeleted: () {
                        setState(() => _manualKeywords.remove(kw));
                      },
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(i18n('cancel')),
        ),
        FilledButton(
          onPressed: (_selected.isEmpty && _manualKeywords.isEmpty) ? null : _confirm,
          child: Text(i18n('confirm')),
        ),
      ],
    );
  }
}
