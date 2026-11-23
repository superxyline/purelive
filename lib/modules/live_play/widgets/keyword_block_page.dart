import 'package:pure_live/common/index.dart';
import 'package:pure_live/core/site/bilibili_shield.dart';
import 'package:pure_live/core/site/bilibili_site.dart';
import 'package:pure_live/modules/live_play/controllers/live_play_controller.dart';
import 'package:pure_live/tv/core/tv_device_service.dart';
import 'package:remixicon/remixicon.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

class KeywordBlockPage extends StatefulWidget {
  const KeywordBlockPage({super.key});

  @override
  State<KeywordBlockPage> createState() => _KeywordBlockPageState();
}

class _KeywordBlockPageState extends State<KeywordBlockPage> {
  final TextEditingController textEditingController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final RxBool _isFocused = false.obs;
  final RxBool _busy = false.obs;
  late final BiliBiliSite _bilibili = BiliBiliSite();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() => _isFocused.value = _focusNode.hasFocus);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    textEditingController.dispose();
    _isFocused.close();
    _busy.close();
    super.dispose();
  }

  /// 添加屏蔽词：写入房间级列表，仅当前直播间生效
  void add() {
    final keyword = textEditingController.text.trim();
    if (keyword.isEmpty) {
      ToastUtil.show(i18n('please_enter_keyword'));
      return;
    }
    final live = Get.find<LivePlayController>();
    SettingsService.to.danmaku.addRoomDanmakuBlock(live.site, live.room.roomId, keyword);
    textEditingController.clear();
    _focusNode.requestFocus();
  }

  /// 长按房间级条目：升入 B 站官方云端屏蔽列表（互动体验页管理的那个，5 平台全局生效）。
  /// 前置条件：官方屏蔽开关已开启（否则升入也不生效，直接提示）；正则/通配符语法官方不支持。
  Future<void> _promoteToOfficial(String keyword) async {
    if (_busy.v) return;
    if (keyword.startsWith('/') && keyword.endsWith('/') || keyword.contains('*') || keyword.contains('?')) {
      ToastUtil.show(i18n('official_shield_regex_unsupported'));
      return;
    }
    if (TvDeviceService.isTv) return;
    if (!SettingsService.to.danmaku.officialShieldEnabled.v) {
      ToastUtil.show(i18n('official_shield_enable_prompt'));
      return;
    }
    if (!_bilibili.hasShieldCredentials) {
      ToastUtil.show(i18n('official_shield_need_login'));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Theme.of(dialogContext).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(i18n('room_block_promote_title')),
        content: Text(i18n('room_block_promote_confirm', args: {'keyword': keyword})),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(i18n('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(i18n('confirm')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final live = Get.find<LivePlayController>();
    final dm = SettingsService.to.danmaku;
    // 本地列表立即生效（无需登录）；已登录B站时自动同步到账号云端
    if (!dm.officialShieldKeywords.contains(keyword)) dm.officialShieldKeywords.add(keyword);
    dm.removeRoomDanmakuBlock(live.site, live.room.roomId, keyword);
    if (!_bilibili.hasShieldCredentials) {
      ToastUtil.show(i18n('room_block_promote_done_local'));
      return;
    }
    _busy.v = true;
    final (ok, msg) = await _bilibili.addShieldKeyword(keyword);
    _busy.v = false;
    ToastUtil.show(ok ? i18n('room_block_promote_done') : msg);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomScrollView(
      physics: const PureLiveScrollPhysics(),
      scrollCacheExtent: const ScrollCacheExtent.pixels(360),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          sliver: SliverToBoxAdapter(
            child: Text(
              i18n('room_block_hint'),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          sliver: SliverToBoxAdapter(child: Obx(() => _buildInput(theme))),
        ),
        // 本直播间屏蔽：输入即写房间级，仅当前直播间生效；长按条目升入官方云端列表
        Obx(() {
          final live = Get.find<LivePlayController>();
          final keywords = List<String>.from(
            SettingsService.to.danmaku.roomDanmakuBlocksOf(live.site, live.room.roomId),
          );
          return _buildBlockSliver(
            theme,
            title: i18n('room_blocked_keywords', args: {'count': '${keywords.length}'}),
            items: keywords,
            icon: Icons.filter_alt_off_rounded,
            onRemove: (index) => SettingsService.to.danmaku.removeRoomDanmakuBlock(
              live.site,
              live.room.roomId,
              keywords[index],
            ),
            onLongPress: _promoteToOfficial,
          );
        }),
        Obx(() {
          final keywords = List<String>.from(SettingsService.to.fav.shieldList);
          return _buildBlockSliver(
            theme,
            title: i18n('keyword_added_count', args: {'count': '${keywords.length}'}),
            items: keywords,
            icon: Icons.filter_alt_off_rounded,
            onRemove: SettingsService.to.fav.removeShieldList,
          );
        }),
        // B 站官方屏蔽（云端全局）：开关开启时只读展示，增删只能在 互动体验 → B站官方屏蔽 里做
        Obx(() {
          final dm = SettingsService.to.danmaku;
          if (!dm.officialShieldEnabled.v) return const SliverToBoxAdapter(child: SizedBox.shrink());
          final keywords = List<String>.from(dm.officialShieldKeywords);
          return _buildReadonlySliver(
            theme,
            title: i18n('official_shield_keywords_count', args: {'count': '${keywords.length}'}),
            hint: i18n('official_shield_readonly_hint'),
            items: keywords,
            icon: Icons.cloud_off_outlined,
          );
        }),
        Obx(() {
          final users = List<String>.from(SettingsService.to.fav.blockedDanmakuUsers);
          return _buildBlockSliver(
            theme,
            title: i18n('blocked_danmaku_users', args: {'count': '${users.length}'}),
            items: users,
            icon: Icons.person_off_rounded,
            onRemove: SettingsService.to.fav.removeBlockedDanmakuUser,
          );
        }),
        // 本直播间礼物卡片屏蔽：删除即恢复该礼物的卡片展示，立即生效
        Obx(() {
          final liveController = Get.find<LivePlayController>();
          final gifts = RoomGiftBlockService.instance.blockedGiftsOf(liveController.site, liveController.room.roomId);
          return _buildBlockSliver(
            theme,
            title: i18n('blocked_gifts_in_room', args: {'count': '${gifts.length}'}),
            items: gifts,
            icon: Icons.card_giftcard_rounded,
            onRemove: (index) => RoomGiftBlockService.instance.unblockGift(
              liveController.site,
              liveController.room.roomId,
              gifts[index],
            ),
          );
        }),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _buildInput(ThemeData theme) {
    final isFocused = _isFocused.value;
    return TextField(
      keyboardType: TextInputType.text,
      controller: textEditingController,
      focusNode: _focusNode,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => add(),
      decoration: InputDecoration(
        hintText: i18n('please_enter_keyword'),
        filled: true,
        fillColor: isFocused
            ? theme.colorScheme.primary.withValues(alpha: 0.04)
            : theme.colorScheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
        ),
        suffixIcon: IconButton(onPressed: add, icon: const Icon(Remix.add_circle_line), tooltip: i18n('add')),
      ),
    );
  }

  /// 只读展示区（B 站官方屏蔽词条在直播间内不可增删改，管理入口在互动体验页）
  Widget _buildReadonlySliver(
    ThemeData theme, {
    required String title,
    required String hint,
    required List<String> items,
    required IconData icon,
  }) {
    return SliverMainAxisGroup(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 2),
          sliver: SliverToBoxAdapter(
            child: Text(
              title,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          sliver: SliverToBoxAdapter(
            child: Text(
              hint,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ),
        if (items.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                return RepaintBoundary(
                  child: Material(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      dense: true,
                      enabled: false,
                      leading: Icon(icon, size: 19, color: theme.colorScheme.onSurfaceVariant),
                      title: Text(items[index], maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildBlockSliver(
    ThemeData theme, {
    required String title,
    required List<String> items,
    required IconData icon,
    required ValueChanged<int> onRemove,
    Future<void> Function(String)? onLongPress,
  }) {
    if (items.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverMainAxisGroup(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
          sliver: SliverToBoxAdapter(
            child: Text(
              title,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.separated(
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final item = items[index];
              final typeInfo = _getKeywordTypeInfo(item);
              return RepaintBoundary(
                child: Material(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  child: ListTile(
                    dense: true,
                    onLongPress: onLongPress == null ? null : () => onLongPress(item),
                    leading: Icon(icon, size: 19, color: theme.colorScheme.primary),
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(item, maxLines: 2, overflow: TextOverflow.ellipsis),
                        ),
                        if (typeInfo != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: typeInfo.$2.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              typeInfo.$1,
                              style: TextStyle(
                                fontSize: 10,
                                color: typeInfo.$2,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    trailing: IconButton(
                      tooltip: i18n('click_to_remove'),
                      icon: const Icon(Remix.close_line, size: 18),
                      onPressed: () => onRemove(index),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 获取关键词类型信息：(类型名, 标签颜色)
  (String, Color)? _getKeywordTypeInfo(String keyword) {
    if (keyword.length >= 2 && keyword.startsWith('/') && keyword.endsWith('/')) {
      return ('REGEX', Colors.purple);
    }
    if (keyword.contains('*') || keyword.contains('?')) {
      return ('WILDCARD', Colors.teal);
    }
    return null; // 普通关键词不显示标签
  }
}
