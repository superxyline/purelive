import 'dart:convert';
import 'package:remixicon/remixicon.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/consts/app_consts.dart';
import 'package:syncfusion_flutter_sliders/sliders.dart';
import 'package:pure_live/common/widgets/count_button.dart';
import 'package:pure_live/modules/live_play/danmaku_viewing_preset.dart';
import 'package:pure_live/modules/settings/pages/pip_danmaku_settings_page.dart';
import 'package:pure_live/modules/live_play/controllers/live_play_controller.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller.dart';


/// 弹幕设置内容页：竖屏房间 Tab 与全屏设置抽屉共用同一控件面（对齐上游
/// v3.1.19 的单一设置面结构）。[embedded] 为 true 时使用紧凑样式——圆角
/// 卡片容器、SwitchListTile 行、12 号字，由全屏右侧抽屉嵌入；
/// [includePipSettings] 控制画中画分区是否显示（全屏抽屉里省略，保持
/// 直播画面可见）。
class DanmakuSettingsContent extends StatefulWidget {
  const DanmakuSettingsContent({
    super.key,
    required this.controller,
    this.embedded = false,
    this.includePipSettings = true,
  });

  final VideoController controller;
  final bool embedded;
  final bool includePipSettings;

  @override
  State<DanmakuSettingsContent> createState() => _DanmakuSettingsPageState();
}

class _DanmakuSettingsPageState extends State<DanmakuSettingsContent> {
  late final ScrollController _scrollController;

  VideoController get controller => widget.controller;

  bool get isEmbedded => widget.embedded;

  /// 当前直播间（详情接口的返回值优先，切房后也保持最新）。
  /// 用于"弹幕列表礼物卡片"这类按房间保存的设置项，以及按平台决定显示哪些设置。
  LiveRoom? get _currentRoom {
    if (Get.isRegistered<LivePlayController>()) {
      final detail = Get.find<LivePlayController>().state.value.room.detail;
      if (detail != null) return detail;
    }
    return widget.controller.room;
  }

  @override
  void initState() {
    super.initState();
    _scrollController = createPureLiveScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color labelColor = theme.colorScheme.onSurface;
    final Color digitColor = theme.colorScheme.primary;
    Widget reactiveCard(List<Widget> Function() builder) => Obx(() {
          final children = builder();
          if (isEmbedded) {
            return Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(children: children),
            );
          }
          return context.buildModernCard(children);
        });

    final scrollChild = SingleChildScrollView(
        controller: _scrollController,
        physics: const PureLiveScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: isEmbedded ? 12 : 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            context.buildGroupTitle(i18n('danmaku_templates')),
            const SizedBox(height: 8),
            Obx(() {
              final activePreset = _matchingPreset();
              final presetContent = Padding(
                padding: EdgeInsets.all(isEmbedded ? 10 : 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: isEmbedded ? 6 : 8,
                      runSpacing: isEmbedded ? 6 : 8,
                      children: [
                        for (final preset in DanmakuViewingPreset.values)
                          ChoiceChip(
                            key: ValueKey('danmaku-template-${preset.id}'),
                            selected: activePreset?.id == preset.id,
                            showCheckmark: false,
                            backgroundColor:
                                isEmbedded ? theme.colorScheme.surface : theme.colorScheme.surfaceContainerHighest,
                            selectedColor: theme.colorScheme.primary,
                            side: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.35)),
                            labelStyle: TextStyle(
                              color: activePreset?.id == preset.id
                                  ? theme.colorScheme.onPrimary
                                  : theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                              fontSize: isEmbedded ? 12 : null,
                            ),
                            avatar: SizedBox(
                              width: isEmbedded ? 16 : 18,
                              child: activePreset?.id == preset.id
                                  ? Icon(Icons.check_rounded,
                                      size: isEmbedded ? 16 : 18, color: theme.colorScheme.onPrimary)
                                  : preset.id == 'best'
                                      ? Icon(Icons.auto_awesome_rounded,
                                          size: isEmbedded ? 16 : 18, color: theme.colorScheme.primary)
                                      : null,
                            ),
                            label: Text(i18n(preset.labelKey)),
                            onSelected: (_) => _applyPreset(preset),
                          ),
                        OutlinedButton.icon(
                          onPressed: _saveTemplate,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: theme.colorScheme.primary,
                            side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.45)),
                            padding: EdgeInsets.symmetric(horizontal: isEmbedded ? 10 : 12),
                          ),
                          icon: Icon(Icons.save_outlined, size: isEmbedded ? 16 : 18),
                          label:
                              Text(i18n('save_current_template'), style: TextStyle(fontSize: isEmbedded ? 12 : null)),
                        ),
                        OutlinedButton.icon(
                          onPressed: _restoreTemplate,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: theme.colorScheme.primary,
                            side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.45)),
                            padding: EdgeInsets.symmetric(horizontal: isEmbedded ? 10 : 12),
                          ),
                          icon: Icon(Icons.restore_rounded, size: isEmbedded ? 16 : 18),
                          label: Text(i18n('restore_saved_template'),
                              style: TextStyle(fontSize: isEmbedded ? 12 : null)),
                        ),
                      ],
                    ),
                    SizedBox(height: isEmbedded ? 8 : 10),
                    Text(
                      '${i18n('danmaku_best_preset_desc')}\n${i18n('danmaku_realtime_hint')}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            height: 1.45,
                            fontSize: isEmbedded ? 11 : null,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              );
              if (isEmbedded) {
                return Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: presetContent,
                );
              }
              return context.buildModernCard([presetContent]);
            }),
            const SizedBox(height: 20),
            context.buildGroupTitle(i18n("danmaku_area")),
            const SizedBox(height: 8),
            reactiveCard(
              () => [
                _switch(
                  theme,
                  title: i18n('danmaku_no_emoji'),
                  value: controller.noEmojiMode.value,
                  onChanged: (value) => controller.noEmojiMode.value = value,
                  labelColor: labelColor,
                ),
                _slider(
                  theme,
                  title: i18n("danmaku_area"),
                  value: controller.danmakuArea.value,
                  min: 0,
                  max: 1,
                  display: "${(controller.danmakuArea.value * 100).toInt()}%",
                  onChanged: (v) => controller.danmakuArea.value = v,
                  labelColor: labelColor,
                  digitColor: digitColor,
                ),
              ],
            ),

            const SizedBox(height: 20),

            // 醒目留言目前只有 B站 会产生消息，其它平台不显示这个设置项
            Obx(() {
              if (_currentRoom?.platform != Sites.bilibiliSite) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  context.buildGroupTitle(i18n("super_chat")),
                  const SizedBox(height: 8),
                  context.buildModernCard([
                    _switch(
                      theme,
                      title: i18n("show_super_chat"),
                      value: SettingsService.to.danmaku.showSuperChat.v,
                      onChanged: (v) => SettingsService.to.danmaku.showSuperChat.v = v,
                      labelColor: labelColor,
                    ),
                  ]),
                ],
              );
            }),

            const SizedBox(height: 20),

            context.buildGroupTitle(i18n('gift_effects')),
            const SizedBox(height: 8),
            reactiveCard(
              () => [
                _switch(
                  theme,
                  title: i18n('local_gift_fullscreen_effect'),
                  value: SettingsService.to.danmaku.showLocalGiftFullscreenEffect.v,
                  onChanged: (v) => SettingsService.to.danmaku.showLocalGiftFullscreenEffect.v = v,
                  labelColor: labelColor,
                ),
                _switch(
                  theme,
                  title: i18n('fullscreen_gift_card'),
                  value: SettingsService.to.danmaku.showFullscreenGiftCard.v,
                  onChanged: (v) => SettingsService.to.danmaku.showFullscreenGiftCard.v = v,
                  labelColor: labelColor,
                ),
                _anchorRow(theme, labelColor),
                _switch(
                  theme,
                  title: i18n('danmaku_list_gift_card'),
                  subtitle: i18n('danmaku_list_gift_card_hint'),
                  value: SettingsService.to.danmaku.showDanmakuListGiftCard(
                    _currentRoom?.platform,
                    _currentRoom?.roomId,
                  ),
                  onChanged: (v) => SettingsService.to.danmaku.setDanmakuListGiftCard(
                    _currentRoom?.platform,
                    _currentRoom?.roomId,
                    v,
                  ),
                  labelColor: labelColor,
                ),
              ],
            ),

            const SizedBox(height: 20),

            context.buildGroupTitle(i18n("position")),
            const SizedBox(height: 8),
            reactiveCard(
              () => [
                _counter(
                  theme,
                  title: i18n("margin_top"),
                  value: controller.danmakuTopArea.value.toInt(),
                  max: 300,
                  onChanged: (v) => controller.danmakuTopArea.value = v.toDouble(),
                  labelColor: labelColor,
                  digitColor: digitColor,
                ),
                _counter(
                  theme,
                  title: i18n("margin_bottom"),
                  value: controller.danmakuBottomArea.value.toInt(),
                  max: 300,
                  onChanged: (v) => controller.danmakuBottomArea.value = v.toDouble(),
                  labelColor: labelColor,
                  digitColor: digitColor,
                ),
              ],
            ),

            const SizedBox(height: 20),

            context.buildGroupTitle(i18n("style")),
            const SizedBox(height: 8),
            reactiveCard(
              () => [
                _slider(
                  theme,
                  title: i18n("opacity"),
                  value: controller.danmakuOpacity.value,
                  min: 0,
                  max: 1,
                  display: "${(controller.danmakuOpacity.value * 100).toInt()}%",
                  onChanged: (v) => controller.danmakuOpacity.value = v,
                  labelColor: labelColor,
                  digitColor: digitColor,
                ),
                _slider(
                  theme,
                  title: i18n("speed"),
                  value: controller.danmakuSpeed.value.toDouble(),
                  min: 20,
                  max: 400,
                  display: '${controller.danmakuSpeed.value.toInt()} px/s',
                  onChanged: (v) => controller.danmakuSpeed.value = v,
                  labelColor: labelColor,
                  digitColor: digitColor,
                ),
                _slider(
                  theme,
                  title: i18n("font_size"),
                  value: controller.danmakuFontSize.value.toDouble(),
                  min: 10,
                  max: 30,
                  display: '${controller.danmakuFontSize.value.toStringAsFixed(1)} px',
                  onChanged: (v) => controller.danmakuFontSize.value = v,
                  labelColor: labelColor,
                  digitColor: digitColor,
                ),
                _slider(
                  theme,
                  title: i18n("font_weight"),
                  value: controller.danmakuFontWeight.value.toDouble(),
                  min: 100,
                  max: 900,
                  stepSize: 100,
                  display: i18n(AppConsts.fontWeightLabels[controller.danmakuFontWeight.value] ?? 'font_weight_normal'),
                  onChanged: (v) {
                    controller.danmakuFontWeight.value = v.round();
                  },
                  labelColor: labelColor,
                  digitColor: digitColor,
                ),
                _switch(
                  theme,
                  title: i18n("danmaku_stroke"),
                  value: controller.enableDanmakuStroke.value,
                  onChanged: (v) => controller.enableDanmakuStroke.value = v,
                  labelColor: labelColor,
                ),
                _slider(
                  theme,
                  title: i18n("stroke"),
                  value: controller.danmakuFontBorder.value.toDouble(),
                  min: 0,
                  max: 4,
                  display: '${controller.danmakuFontBorder.value.toStringAsFixed(1)} px',
                  onChanged: (v) => controller.danmakuFontBorder.value = v,
                  labelColor: labelColor,
                  digitColor: digitColor,
                ),
                _switch(
                  theme,
                  title: '${i18n("danmaku_fps")} · ${i18n("dynamic_follow_display")}',
                  value: SettingsService.to.danmaku.danmakuAutoFps.v,
                  onChanged: (v) => SettingsService.to.danmaku.danmakuAutoFps.v = v,
                  labelColor: labelColor,
                ),
                if (!SettingsService.to.danmaku.danmakuAutoFps.v)
                  _slider(
                    theme,
                    title: i18n("danmaku_fps"),
                    value: controller.danmakuFps.value.toDouble(),
                    min: 30,
                    max: 240,
                    display: "${controller.danmakuFps.value.toInt()} FPS",
                    onChanged: (v) => controller.danmakuFps.value = v.toInt(),
                    labelColor: labelColor,
                    digitColor: digitColor,
                  )
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(
                      '${SettingsService.to.danmaku.resolvedDanmakuFps()} FPS',
                      style: TextStyle(color: digitColor, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            context.buildGroupTitle(i18n('danmaku_repeat_filter')),
            const SizedBox(height: 8),
            reactiveCard(
              () => [
                _switch(
                  theme,
                  title: i18n('collapse_repeated_danmaku'),
                  value: SettingsService.to.danmaku.collapseRepeatedDanmaku.v,
                  onChanged: (v) => SettingsService.to.danmaku.collapseRepeatedDanmaku.v = v,
                  labelColor: labelColor,
                ),
                if (SettingsService.to.danmaku.collapseRepeatedDanmaku.v)
                  _counter(
                    theme,
                    title: i18n('repeated_danmaku_window'),
                    value: SettingsService.to.danmaku.repeatedDanmakuWindowSeconds.v,
                    min: 1,
                    max: 30,
                    onChanged: (v) => SettingsService.to.danmaku.repeatedDanmakuWindowSeconds.v = v,
                    labelColor: labelColor,
                    digitColor: digitColor,
                  ),
              ],
            ),
            const SizedBox(height: 20),
            context.buildGroupTitle(i18n('danmaku_similarity_filter')),
            const SizedBox(height: 8),
            reactiveCard(
              () => [
                _switch(
                  theme,
                  title: i18n('danmaku_similarity_filter_enable'),
                  value: SettingsService.to.danmaku.enableDanmakuSimilarityFilter.v,
                  onChanged: (v) => SettingsService.to.danmaku.enableDanmakuSimilarityFilter.v = v,
                  labelColor: labelColor,
                ),
                if (SettingsService.to.danmaku.enableDanmakuSimilarityFilter.v)
                  _counter(
                    theme,
                    title: i18n('danmaku_similarity_threshold'),
                    value: SettingsService.to.danmaku.danmakuSimilarityThreshold.v,
                    min: 50,
                    max: 100,
                    onChanged: (v) => SettingsService.to.danmaku.danmakuSimilarityThreshold.v = v,
                    labelColor: labelColor,
                    digitColor: digitColor,
                  ),
              ],
            ),
            const SizedBox(height: 20),
            context.buildGroupTitle(i18n('danmaku_screen_interaction')),
            const SizedBox(height: 8),
            reactiveCard(
              () => [
                _switch(
                  theme,
                  title: i18n('danmaku_tap_action'),
                  value: SettingsService.to.danmaku.enableDanmakuTapInteraction.v,
                  onChanged: (v) => SettingsService.to.danmaku.enableDanmakuTapInteraction.v = v,
                  labelColor: labelColor,
                ),
                _switch(
                  theme,
                  title: i18n('danmaku_long_press_action'),
                  value: SettingsService.to.danmaku.enableDanmakuLongPressInteraction.v,
                  onChanged: (v) => SettingsService.to.danmaku.enableDanmakuLongPressInteraction.v = v,
                  labelColor: labelColor,
                ),
              ],
            ),
            const SizedBox(height: 20),

            if (widget.includePipSettings) const PipDanmakuSettingsSection(),
            SizedBox(height: isEmbedded ? 12 : 24),
          ],
        ),
      );
    if (isEmbedded) return scrollChild;
    return Scaffold(body: scrollChild);
  }

  DanmakuViewingPreset? _matchingPreset() {
    for (final preset in DanmakuViewingPreset.values) {
      if (preset.matches(
        area: controller.danmakuArea.v,
        top: controller.danmakuTopArea.v,
        bottom: controller.danmakuBottomArea.v,
        speed: controller.danmakuSpeed.v,
        fontSize: controller.danmakuFontSize.v,
        fontWeight: preset.fontWeight,
        fontBorder: controller.danmakuFontBorder.v,
        opacity: controller.danmakuOpacity.v,
        stroke: controller.enableDanmakuStroke.v,
        autoFps: SettingsService.to.danmaku.danmakuAutoFps.v,
      )) {
        return preset;
      }
    }
    return null;
  }

  void _applyPreset(DanmakuViewingPreset preset) {
    controller.danmakuArea.v = preset.area;
    controller.danmakuTopArea.v = preset.top;
    controller.danmakuBottomArea.v = preset.bottom;
    controller.danmakuSpeed.v = preset.speed;
    controller.danmakuFontSize.v = preset.fontSize;
    controller.danmakuFontWeight.v = preset.fontWeight;
    controller.danmakuFontBorder.v = preset.fontBorder;
    controller.danmakuOpacity.v = preset.opacity;
    controller.enableDanmakuStroke.v = preset.stroke;
    SettingsService.to.danmaku.danmakuAutoFps.v = true;
    setState(() {});
    ToastUtil.show(i18n('danmaku_template_applied'));
  }

  void _saveTemplate() {
    SettingsService.to.danmaku.savedDanmakuTemplate.v = jsonEncode({
      'area': controller.danmakuArea.v,
      'top': controller.danmakuTopArea.v,
      'bottom': controller.danmakuBottomArea.v,
      'speed': controller.danmakuSpeed.v,
      'fontSize': controller.danmakuFontSize.v,
      'fontWeight': controller.danmakuFontWeight.v,
      'fontBorder': controller.danmakuFontBorder.v,
      'opacity': controller.danmakuOpacity.v,
      'stroke': controller.enableDanmakuStroke.v,
      'fps': controller.danmakuFps.v,
      'autoFps': SettingsService.to.danmaku.danmakuAutoFps.v,
    });
    ToastUtil.show(i18n('danmaku_template_saved'));
  }

  void _restoreTemplate() {
    final raw = SettingsService.to.danmaku.savedDanmakuTemplate.v;
    if (raw.isEmpty) {
      ToastUtil.show(i18n('danmaku_template_empty'));
      return;
    }
    try {
      final value = jsonDecode(raw) as Map<String, dynamic>;
      controller.danmakuArea.v = (value['area'] as num).toDouble();
      controller.danmakuTopArea.v = (value['top'] as num).toDouble();
      controller.danmakuBottomArea.v = (value['bottom'] as num).toDouble();
      controller.danmakuSpeed.v = (value['speed'] as num).toDouble();
      controller.danmakuFontSize.v = (value['fontSize'] as num).toDouble();
      controller.danmakuFontWeight.v = (value['fontWeight'] as num).toInt();
      controller.danmakuFontBorder.v = (value['fontBorder'] as num).toDouble();
      controller.danmakuOpacity.v = (value['opacity'] as num).toDouble();
      controller.enableDanmakuStroke.v = value['stroke'] == true;
      controller.danmakuFps.v = (value['fps'] as num?)?.toInt() ?? 60;
      SettingsService.to.danmaku.danmakuAutoFps.v = value['autoFps'] != false;
      ToastUtil.show(i18n('danmaku_template_applied'));
    } catch (_) {
      ToastUtil.show(i18n('danmaku_template_empty'));
    }
  }

  Widget _slider(
    ThemeData theme, {
    required String title,
    required double value,
    required double min,
    required double max,
    required String display,
    required ValueChanged<double> onChanged,
    required Color labelColor,
    required Color digitColor,
    double? stepSize,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.t15.copyWith(fontWeight: FontWeight.w600, color: labelColor),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  display,
                  style: AppTextStyles.t12.copyWith(fontWeight: FontWeight.bold, color: digitColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Transform.translate(
            offset: const Offset(-8, 0),
            child: SizedBox(
              width: double.infinity,
              child: SfSlider(
                min: min,
                max: max,
                value: value,
                stepSize: stepSize,
                activeColor: theme.colorScheme.primary,
                inactiveColor: theme.colorScheme.primary.withValues(alpha: 0.15),
                onChanged: (dynamic v) => onChanged(v as double),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _counter(
    ThemeData theme, {
    required String title,
    required int value,
    int min = 0,
    required int max,
    required ValueChanged<int> onChanged,
    required Color labelColor,
    required Color digitColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              title,
              style: AppTextStyles.t15.copyWith(fontWeight: FontWeight.w600, color: labelColor),
            ),
          ),
          const SizedBox(width: 8),
          CountButton(
            maxValue: max,
            minValue: min,
            selectedValue: value,
            onChanged: onChanged,
            textStyle: TextStyle(color: digitColor, fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  /// 锚点值(topLeft 等 camelCase) → i18n key(pos_top_left 等 snake_case)
  static const Map<String, String> _posKeyMap = {
    'topLeft': 'top_left',
    'top': 'top',
    'topRight': 'top_right',
    'left': 'left',
    'right': 'right',
    'bottomLeft': 'bottom_left',
    'bottom': 'bottom',
    'bottomRight': 'bottom_right',
  };

  String _posKey(String anchor) => 'pos_${_posKeyMap[anchor] ?? anchor}';

  /// 卡片位置行：显示当前锚点，点开九宫格选择（四角+四边 8 方位）。
  Widget _anchorRow(ThemeData theme, Color labelColor) {
    final anchor = SettingsService.to.danmaku.giftCardAnchor.v;
    return InkWell(
      onTap: _showGiftCardAnchorDialog,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    i18n('gift_card_position'),
                    style: AppTextStyles.t15.copyWith(fontWeight: FontWeight.w600, color: labelColor),
                  ),
                  const SizedBox(height: 2),
                  Text(i18n('gift_card_position_hint'), style: AppTextStyles.t12Muted),
                ],
              ),
            ),
            Text(
              i18n(_posKey(anchor)),
              style: AppTextStyles.t14Muted.copyWith(color: theme.colorScheme.primary),
            ),
            Icon(Remix.arrow_right_s_line, size: 18, color: theme.hintColor),
          ],
        ),
      ),
    );
  }

  /// 九宫格方位选择：3×3，中间是卡片示意，四周 8 格为可选方位。
  Future<void> _showGiftCardAnchorDialog() async {
    const anchors = <List<String>>[
      ['topLeft', 'top', 'topRight'],
      ['left', 'right'],
      ['bottomLeft', 'bottom', 'bottomRight'],
    ];
    await Get.dialog<void>(
      AlertDialog(
        title: Text(i18n('gift_card_position')),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final row in anchors)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (row.length == 1) ...[
                        const SizedBox(width: 84, height: 56),
                        const SizedBox(width: 8),
                      ],
                      for (final a in row) ...[
                        _anchorCell(a),
                        if (a != row.last) const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(i18n('cancel'))),
        ],
      ),
    );
    setState(() {});
  }

  Widget _anchorCell(String anchor) {
    final theme = Theme.of(context);
    final selected = SettingsService.to.danmaku.giftCardAnchor.v == anchor;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        SettingsService.to.danmaku.giftCardAnchor.v = anchor;
        Navigator.pop(context);
      },
      child: Container(
        width: 84,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.14)
              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? theme.colorScheme.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Text(
          i18n(_posKey(anchor)),
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? theme.colorScheme.primary : theme.hintColor,
          ),
        ),
      ),
    );
  }

  Widget _switch(
    ThemeData theme, {
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
    required Color labelColor,
    String? subtitle,
  }) {
    if (isEmbedded) {
      return Material(
        type: MaterialType.transparency,
        child: SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          visualDensity: VisualDensity.standard,
          title: Text(
            title,
            style: AppTextStyles.t15.copyWith(fontWeight: FontWeight.w600, color: labelColor),
          ),
          subtitle: subtitle == null ? null : Text(subtitle, style: AppTextStyles.t12Muted),
          value: value,
          activeThumbColor: theme.colorScheme.primary,
          onChanged: onChanged,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.t15.copyWith(fontWeight: FontWeight.w600, color: labelColor),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppTextStyles.t12Muted),
                ],
              ],
            ),
          ),
          Switch(value: value, activeThumbColor: theme.colorScheme.primary, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// 竖屏房间 Tab 的整页包装：与全屏抽屉共用 [DanmakuSettingsContent]。
class DanmakuSettingsPage extends StatelessWidget {
  const DanmakuSettingsPage({super.key, required this.controller});

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: DanmakuSettingsContent(controller: controller));
  }
}
