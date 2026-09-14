import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/live_play/local_interaction_controller.dart';

class LocalInteractionSettingsPage extends StatefulWidget {
  const LocalInteractionSettingsPage({super.key});

  @override
  State<LocalInteractionSettingsPage> createState() => _LocalInteractionSettingsPageState();
}

class _LocalInteractionSettingsPageState extends State<LocalInteractionSettingsPage> {
  late final LocalInteractionController controller;
  late final TextEditingController nameController;

  @override
  void initState() {
    super.initState();
    controller = Get.find<LocalInteractionController>();
    nameController = TextEditingController(text: controller.userName.v);
  }

  @override
  void dispose() {
    controller.updateName(nameController.text);
    nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(i18n('local_interaction_settings'))),
      body: ListView(
        physics: const PureLiveScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          context.buildGroupTitle(i18n('local_interaction_settings')),
          context.buildModernCard([
            context.buildSwitchTile(
              title: i18n('local_interaction_enable'),
              subtitle: i18n('local_interaction_enable_desc'),
              value: controller.enabled,
              icon: Icons.auto_awesome_rounded,
              isLong: true,
            ),
          ]),
          // 全屏浮层透明度：作用于全屏时的醒目留言与礼物卡片，
          // 与本地互动开关无关，因此固定显示在这个位置。
          context.buildGroupTitle(i18n('fullscreen_overlay_opacity')),
          context.buildModernCard([
            Obx(
              () => context.buildSliderTile(
                context,
                icon: Icons.chat_bubble_outline_rounded,
                title: i18n('fullscreen_sc_opacity'),
                value: SettingsService.to.danmaku.fullscreenScOpacity.v,
                min: 0.1,
                max: 1.0,
                displayValue: '${(SettingsService.to.danmaku.fullscreenScOpacity.v * 100).round()}%',
                onChanged: (v) => SettingsService.to.danmaku.fullscreenScOpacity.v = v,
              ),
            ),
            Obx(
              () => context.buildSliderTile(
                context,
                icon: Icons.card_giftcard_rounded,
                title: i18n('fullscreen_gift_card_opacity'),
                value: SettingsService.to.danmaku.fullscreenGiftCardOpacity.v,
                min: 0.1,
                max: 1.0,
                displayValue:
                    '${(SettingsService.to.danmaku.fullscreenGiftCardOpacity.v * 100).round()}%',
                onChanged: (v) => SettingsService.to.danmaku.fullscreenGiftCardOpacity.v = v,
              ),
            ),
          ]),
          const SizedBox(height: 20),
          Obx(() {
            if (!controller.enabled.v) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                context.buildGroupTitle(i18n('local_platform_pack')),
                context.buildModernCard([
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(i18n('local_platform_pack_desc'), style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: LocalInteractionController.platformPacks
                              .map(
                                (pack) => ChoiceChip(
                                  avatar: Text(pack.badge),
                                  label: Text(pack.name),
                                  selected: controller.previewPlatform.v == pack.id,
                                  selectedColor: pack.accentColor.withValues(alpha: .18),
                                  onSelected: (_) => controller.previewPlatform.v = pack.id,
                                ),
                              )
                              .toList(),
                        ),
                        const SizedBox(height: 14),
                        _buildPackPreview(context),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 20),
                context.buildGroupTitle(i18n('local_user_profile')),
                context.buildModernCard([
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                    child: TextField(
                      controller: nameController,
                      maxLength: 20,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(labelText: i18n('local_user_name'), counterText: ''),
                      onSubmitted: controller.updateName,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(i18n('local_title_select'), style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 8),
                        Obx(
                          () => Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: LocalInteractionController.titles
                                .map(
                                  (title) => ChoiceChip(
                                    label: Text(i18n('local_title_$title')),
                                    selected: controller.selectedTitle.v == title,
                                    onSelected: (_) => controller.selectedTitle.v = title,
                                  ),
                                )
                                .toList(growable: false),
                          ),
                        ),
                      ],
                    ),
                  ),
                  context.buildSwitchTile(
                    title: i18n('local_overlay_message'),
                    subtitle: i18n('local_overlay_message_desc'),
                    value: controller.showAsDanmaku,
                    icon: Icons.subtitles_rounded,
                    isLong: true,
                  ),
                  context.buildSwitchTile(
                    title: i18n('local_show_platform_badge'),
                    subtitle: i18n('local_show_platform_badge_desc'),
                    value: controller.showPlatformBadge,
                    icon: Icons.workspace_premium_rounded,
                    isLong: true,
                  ),
                  context.buildSwitchTile(
                    title: i18n('local_show_level_badge'),
                    subtitle: i18n('local_show_level_badge_desc'),
                    value: controller.showLevelBadge,
                    icon: Icons.military_tech_rounded,
                    isLong: true,
                  ),
                  context.buildSwitchTile(
                    title: i18n('local_gift_effects'),
                    subtitle: i18n('local_gift_effects_desc'),
                    value: controller.enableGiftEffects,
                    icon: Icons.celebration_rounded,
                    isLong: true,
                  ),
                  Obx(
                    () => context.buildTile(
                      title: i18n('local_interaction_status'),
                      subtitle: '${controller.coins.v} · Lv.${controller.level}',
                      icon: Icons.toll_rounded,
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(i18n('local_interaction_room_entry_desc'), style: Theme.of(context).textTheme.bodySmall),
                ),
                const SizedBox(height: 20),
                context.buildGroupTitle(i18n('local_experience_economy')),
                context.buildModernCard([
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(i18n('local_experience_economy_desc'), style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          children: const [500, 2000, 10000]
                              .map(
                                (value) =>
                                    OutlinedButton(onPressed: () => controller.recharge(value), child: Text('+$value')),
                              )
                              .toList(),
                        ),
                        TextButton.icon(
                          onPressed: controller.history.isEmpty ? null : controller.clearHistory,
                          icon: const Icon(Icons.delete_sweep_outlined),
                          label: Text(i18n('local_clear_history')),
                        ),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 20),
                context.buildGroupTitle(i18n('watch_stats_title')),
                context.buildModernCard([
                  Builder(
                    builder: (context) {
                      final service = WatchStatsService.instance;
                      final entries = service.sortedEntries();
                      if (entries.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.all(14),
                          child: Text(i18n('watch_stats_none'), style: Theme.of(context).textTheme.bodySmall),
                        );
                      }
                      final total = formatWatchDuration(service.totalSeconds());
                      final week = formatWatchDuration(service.weekSeconds());
                      final giftCount = service.totalGiftCount();
                      final giftValue = service.totalGiftValueFen();
                      final giftIncome = service.totalGiftIncomeFen();
                      final topLines = entries
                          .take(3)
                          .map((e) {
                            final nick = (e.value['nick'] as String?) ?? '';
                            final secs = (e.value['total'] as int?) ?? 0;
                            final gifts = (e.value['giftCount'] as int?) ?? 0;
                            // 只有拿得到礼物时才补上礼物信息，避免全是 0 的噪音
                            if (gifts <= 0) return '· $nick（${formatWatchDuration(secs)}）';
                            final roomValue = WatchStatsService.entryGiftValueFen(e.value);
                            final valueText = roomValue > 0 ? ' ≈ ${formatGiftValue(roomValue)}' : '';
                            return '· $nick（${formatWatchDuration(secs)} · '
                                '${i18n('watch_stats_gift_unit', args: {'count': '$gifts'})}$valueText）';
                          })
                          .join('\n');
                      return Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _watchStatRow(context, i18n('watch_stats_total'), total),
                            const SizedBox(height: 6),
                            _watchStatRow(context, i18n('watch_stats_week'), week),
                            const SizedBox(height: 6),
                            _watchStatRow(
                              context,
                              i18n('watch_stats_gifts'),
                              i18n('watch_stats_gift_unit', args: {'count': '$giftCount'}),
                            ),
                            if (giftValue > 0) ...[
                              const SizedBox(height: 6),
                              _watchStatRow(
                                context,
                                i18n('watch_stats_gift_value'),
                                formatGiftValue(giftValue),
                              ),
                              const SizedBox(height: 6),
                              _watchStatRow(
                                context,
                                i18n('watch_stats_gift_income'),
                                formatGiftValue(giftIncome),
                              ),
                            ],
                            if (giftCount > 0) ...[
                              const SizedBox(height: 6),
                              Text(
                                i18n('watch_stats_gift_estimate_hint'),
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).hintColor,
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),
                            Text(
                              '${i18n('watch_stats_top')}:\n$topLines',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.6),
                            ),
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () {
                                  service.clearAll();
                                  setState(() {});
                                  ToastUtil.show(i18n('watch_stats_cleared'));
                                },
                                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                                label: Text(i18n('watch_stats_clear')),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ]),
              ],
            );
          }),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _watchStatRow(BuildContext context, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildPackPreview(BuildContext context) {
    final pack = LocalInteractionController.packForPlatform(controller.previewPlatform.v);
    final gifts = LocalInteractionController.giftsForPlatform(pack.id);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [pack.accentColor.withValues(alpha: .18), pack.accentColor.withValues(alpha: .05)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: pack.accentColor.withValues(alpha: .25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${pack.badge} ${pack.name}', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '${i18n(pack.levelKey)} Lv.${controller.level} · ${controller.coins.v} ${i18n(pack.currencyKey)}',
              style: TextStyle(color: pack.accentColor, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: gifts
                  .map((gift) => Chip(label: Text('${gift.emoji} ${i18n(gift.nameKey)} · ${gift.price}')))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}
