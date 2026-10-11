import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/live_play/states/load_type.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller.dart';

const contentFirstPanelHeaderActionExtent = 48.0;

/// 全屏悬浮面板的统一尺寸策略（移植自上游 v3.1.19 content_first_panel_layout）。
/// 横屏下视频已占满视口，固定小对话框只剩几行内容空间，因此面板刻意
/// 占据大部分安全视口，仅在大屏上封顶。
@immutable
class ContentFirstPanelLayout {
  const ContentFirstPanelLayout({required this.size, required this.insetPadding, required this.splitContent});

  final Size size;
  final EdgeInsets insetPadding;
  final bool splitContent;
}

ContentFirstPanelLayout resolveContentFirstPanelLayout(Size viewport, {double maxHeight = 620.0}) {
  final compactViewport = viewport.width < 720 || viewport.height < 520;
  final horizontalInset = compactViewport ? 8.0 : 20.0;
  final verticalInset = compactViewport ? 8.0 : 20.0;
  final availableWidth = (viewport.width - horizontalInset * 2).clamp(280.0, double.infinity).toDouble();
  final availableHeight = (viewport.height - verticalInset * 2).clamp(240.0, double.infinity).toDouble();

  final targetWidth = (availableWidth * 0.5).clamp(280.0, double.infinity).toDouble();
  final width = targetWidth.clamp(280.0, availableWidth).toDouble();
  final targetHeight = (viewport.height * 1.0).clamp(240.0, maxHeight).toDouble();
  final height = targetHeight.clamp(240.0, availableHeight).toDouble();
  return ContentFirstPanelLayout(
    size: Size(width, height),
    insetPadding: EdgeInsets.symmetric(horizontal: horizontalInset, vertical: verticalInset),
    splitContent: viewport.width > viewport.height && width >= 620.0,
  );
}

/// 流选择面板内可容纳的紧凑选项列数：保证右侧半屏面板不至于变成一列长列表。
int resolveStreamChoiceColumns(double paneWidth, {int? itemCount}) {
  final availableColumns = switch (paneWidth) {
    >= 340 => 3,
    >= 210 => 2,
    _ => 1,
  };
  if (itemCount == null) return availableColumns;
  if (itemCount <= 1) return 1;
  // 四个选项排 3+1 不均衡，2×2 同样两行且给长标签留更多空间。
  if (itemCount == 4 && availableColumns == 3) return 2;
  return math.min(availableColumns, itemCount);
}

@immutable
class StreamSelectorPanelLayout {
  const StreamSelectorPanelLayout({
    required this.dialogHeight,
    required this.qualityHeight,
    required this.lineHeight,
    required this.gap,
    required this.splitContent,
  });

  final double dialogHeight;
  final double qualityHeight;
  final double lineHeight;
  final double gap;
  final bool splitContent;
}

@immutable
class StreamSelectorTextMetrics {
  const StreamSelectorTextMetrics({
    required this.dialogTitleRowHeight,
    required this.paneHeaderHeight,
    required this.itemHeight,
  });

  static const standard = StreamSelectorTextMetrics(
    dialogTitleRowHeight: contentFirstPanelHeaderActionExtent,
    paneHeaderHeight: 23,
    itemHeight: 42,
  );

  final double dialogTitleRowHeight;
  final double paneHeaderHeight;
  final double itemHeight;

  double get dialogChromeHeight => dialogTitleRowHeight + 1;
  double get paneChromeHeight => 4 + paneHeaderHeight + 4 + 6;
  double get minimumPaneHeight => math.max(78, paneChromeHeight + itemHeight);
}

/// 按可见选项数量求出整个流选择面板的固定行高。
/// 短列表出短对话框；任一列表超出视口时，两栏保持最小可用高度、
/// 仅网格内部滚动。
StreamSelectorPanelLayout resolveStreamSelectorPanelLayout({
  required Size maximumDialogSize,
  required int qualityCount,
  required int lineCount,
  required bool splitContent,
  double gap = 5,
  StreamSelectorTextMetrics textMetrics = StreamSelectorTextMetrics.standard,
}) {
  const bodyPadding = 6.0;
  final dialogChromeHeight = textMetrics.dialogChromeHeight;
  final minimumPaneHeight = textMetrics.minimumPaneHeight;

  final innerWidth = math.max(0.0, maximumDialogSize.width - bodyPadding * 2);
  final paneWidth = splitContent ? math.max(0.0, (innerWidth - gap) / 2) : innerWidth;
  final desiredQuality = _streamChoicePaneHeight(paneWidth, qualityCount, textMetrics);
  final desiredLine = _streamChoicePaneHeight(paneWidth, lineCount, textMetrics);
  final maximumBodyHeight = math.max(0.0, maximumDialogSize.height - dialogChromeHeight - bodyPadding * 2);

  if (splitContent) {
    final paneHeight = math.min(math.max(desiredQuality, desiredLine), maximumBodyHeight);
    final dialogHeight = (dialogChromeHeight + bodyPadding * 2 + paneHeight)
        .clamp(124.0, maximumDialogSize.height)
        .toDouble();
    return StreamSelectorPanelLayout(
      dialogHeight: dialogHeight,
      qualityHeight: paneHeight,
      lineHeight: paneHeight,
      gap: gap,
      splitContent: true,
    );
  }

  final desiredPanesHeight = desiredQuality + gap + desiredLine;
  if (desiredPanesHeight <= maximumBodyHeight) {
    return StreamSelectorPanelLayout(
      dialogHeight: dialogChromeHeight + bodyPadding * 2 + desiredPanesHeight,
      qualityHeight: desiredQuality,
      lineHeight: desiredLine,
      gap: gap,
      splitContent: false,
    );
  }

  final availableForPanes = math.max(0.0, maximumBodyHeight - gap);
  final effectiveMinimum = math.min(minimumPaneHeight, availableForPanes / 2);
  final extraSpace = math.max(0.0, availableForPanes - effectiveMinimum * 2);
  final desiredExtra = math.max(1.0, desiredQuality + desiredLine - effectiveMinimum * 2);
  final qualityExtraShare = math.max(0.0, desiredQuality - effectiveMinimum) / desiredExtra;
  final qualityHeight = effectiveMinimum + extraSpace * qualityExtraShare;
  final lineHeight = availableForPanes - qualityHeight;
  return StreamSelectorPanelLayout(
    dialogHeight: maximumDialogSize.height,
    qualityHeight: qualityHeight,
    lineHeight: lineHeight,
    gap: gap,
    splitContent: false,
  );
}

double _streamChoicePaneHeight(double paneWidth, int itemCount, StreamSelectorTextMetrics textMetrics) {
  final paneChromeHeight = textMetrics.paneChromeHeight;
  final itemHeight = textMetrics.itemHeight;
  const itemSpacing = 5.0;
  if (itemCount <= 0) return 78;
  final gridWidth = math.max(0.0, paneWidth - 12);
  final columns = resolveStreamChoiceColumns(gridWidth, itemCount: itemCount);
  final rows = math.max(1, (itemCount / columns).ceil());
  return paneChromeHeight + rows * itemHeight + math.max(0, rows - 1) * itemSpacing;
}

/// 清晰度/线路共用的选择栏：图标标题 + 选项网格，选中项主题色高亮。
class StreamChoicePane extends StatelessWidget {
  const StreamChoicePane({
    super.key,
    required this.icon,
    required this.title,
    required this.itemCount,
    required this.selectedIndex,
    required this.labelBuilder,
    required this.onSelected,
  });

  final IconData icon;
  final String title;
  final int itemCount;
  final int selectedIndex;
  final String Function(int index) labelBuilder;
  final Future<void> Function(int index)? onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textMetrics = StreamSelectorTextMetrics.standard;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .55)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
        child: Column(
          children: [
            SizedBox(
              height: textMetrics.paneHeaderHeight,
              child: Row(
                children: [
                  Icon(icon, size: 16, color: colors.primary),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 4),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final columns = resolveStreamChoiceColumns(constraints.maxWidth, itemCount: itemCount);
                  return GridView.builder(
                    primary: false,
                    padding: EdgeInsets.zero,
                    physics: const PureLiveScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisExtent: textMetrics.itemHeight,
                      mainAxisSpacing: 5,
                      crossAxisSpacing: 5,
                    ),
                    itemCount: itemCount,
                    itemBuilder: (context, index) {
                      final selected = selectedIndex == index;
                      return Material(
                        key: ValueKey('stream-choice-$index'),
                        color: selected
                            ? colors.primaryContainer.withValues(alpha: .78)
                            : colors.surfaceContainerHighest,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: selected
                                ? colors.primary.withValues(alpha: .62)
                                : colors.outlineVariant.withValues(alpha: .2),
                            width: selected ? 1.2 : 1,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: onSelected == null || selected ? null : () => unawaited(onSelected!(index)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: selected ? 18 : 2),
                                  child: Text(
                                    labelBuilder(index),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context).textTheme.bodyMedium
                                        ?.copyWith(fontWeight: selected ? FontWeight.w800 : FontWeight.w600),
                                  ),
                                ),
                                if (selected)
                                  Positioned(
                                    right: 1,
                                    child: Icon(Icons.check_circle_rounded, size: 16, color: colors.primary),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 全屏下清晰度与 CDN 线路选择的紧凑入口：两个选择栏共用一个右侧贴边
/// 面板，避免两个窄菜单在右下安全区相互挤压（移植自上游 v3.1.19
/// FullscreenStreamSelectorButton）。
class FullscreenStreamSelectorButton extends StatelessWidget {
  const FullscreenStreamSelectorButton({super.key, required this.controller});

  final VideoController controller;

  Future<void> _showSelector(BuildContext context) async {
    final layout = resolveContentFirstPanelLayout(MediaQuery.sizeOf(context));
    controller.isMenuOpen.value = true;
    controller.stopHideController();
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => Obx(() {
          final live = controller.livePlayController;
          final state = live.state.value.player;
          final qualityPane = StreamChoicePane(
            key: const ValueKey('stream-quality-pane'),
            icon: Icons.high_quality_rounded,
            title: i18n('select_quality'),
            itemCount: state.qualites.length,
            selectedIndex: state.currentQuality.clamp(0, math.max(0, state.qualites.length - 1)),
            labelBuilder: (index) => state.qualites[index].quality,
            onSelected: (index) async {
              Navigator.of(dialogContext).pop();
              await live.setResolution(ReloadDataType.changeQuality, index, state.currentLineIndex);
            },
          );
          final linePane = StreamChoicePane(
            key: const ValueKey('stream-line-pane'),
            icon: Icons.alt_route_rounded,
            title: i18n('select_line'),
            itemCount: state.playUrls.length,
            selectedIndex: state.currentLineIndex.clamp(0, math.max(0, state.playUrls.length - 1)),
            labelBuilder: (index) => i18n('toolbox_line', args: {'index': (index + 1).toString()}),
            onSelected: (index) async {
              Navigator.of(dialogContext).pop();
              await live.setResolution(ReloadDataType.changeLine, state.currentQuality, index);
            },
          );

          final panelLayout = resolveStreamSelectorPanelLayout(
            maximumDialogSize: layout.size,
            qualityCount: state.qualites.length,
            lineCount: state.playUrls.length,
            splitContent: layout.splitContent,
          );

          return Dialog(
            key: const ValueKey('fullscreen-stream-selector-panel'),
            alignment: Alignment.centerRight,
            insetPadding: layout.insetPadding,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: layout.size.width,
              height: panelLayout.dialogHeight,
              child: Column(
                children: [
                  SizedBox(
                    height: contentFirstPanelHeaderActionExtent,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 9, right: 1),
                      child: Row(
                        children: [
                          Icon(Icons.tune_rounded, size: 17, color: Theme.of(dialogContext).colorScheme.primary),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              i18n('fullscreen_stream_settings'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(dialogContext).textTheme.titleSmall,
                            ),
                          ),
                          IconButton(
                            key: const ValueKey('fullscreen-stream-selector-close'),
                            tooltip: i18n('close'),
                            visualDensity: VisualDensity.standard,
                            constraints: const BoxConstraints.tightFor(
                              width: contentFirstPanelHeaderActionExtent,
                              height: contentFirstPanelHeaderActionExtent,
                            ),
                            padding: EdgeInsets.zero,
                            onPressed: () => Navigator.pop(dialogContext),
                            icon: const Icon(Icons.close_rounded, size: 19),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: panelLayout.splitContent
                          ? Row(
                              children: [
                                Expanded(
                                  child: SizedBox(height: panelLayout.qualityHeight, child: qualityPane),
                                ),
                                SizedBox(width: panelLayout.gap),
                                Expanded(
                                  child: SizedBox(height: panelLayout.lineHeight, child: linePane),
                                ),
                              ],
                            )
                          : Column(
                              children: [
                                SizedBox(
                                  key: const ValueKey('stream-quality-content-sized-slot'),
                                  height: panelLayout.qualityHeight,
                                  child: qualityPane,
                                ),
                                SizedBox(height: panelLayout.gap),
                                SizedBox(height: panelLayout.lineHeight, child: linePane),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      );
    } finally {
      controller.isMenuOpen.value = false;
      controller.enableController();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.livePlayController.state.value.player.qualites.isEmpty) return const SizedBox.shrink();
      return Tooltip(
        message: i18n('fullscreen_stream_settings'),
        child: GestureDetector(
          onTap: () => _showSelector(context),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.only(right: 6, left: 6),
            child: Icon(
              Icons.tune_rounded,
              size: 20,
              color: Colors.white,
            ),
          ),
        ),
      );
    });
  }
}
