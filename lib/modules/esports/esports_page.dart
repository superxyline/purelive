import 'package:cached_network_image/cached_network_image.dart';
import 'package:remixicon/remixicon.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/widgets/common_appbar_actions.dart';
import 'package:pure_live/modules/esports/esports_controller.dart';
import 'package:pure_live/modules/esports/esports_match.dart';

/// 赛事页：展示从昨天到 7 天后的电竞赛事日程。
///
/// 数据源：完美世界电竞（CS2）+ lolesports 官方（LOL）。
/// Dota2 数据源暂未接入，筛选时显示占位提示。
class EsportsPage extends GetView<EsportsController> {
  const EsportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraint) {
        final bool showAction = Get.width <= 680;
        final int menuCount = SettingsService.to.app.savedMenuIds.v.length;

        return Scaffold(
          appBar: AppBar(
            centerTitle: true,
            leading: (showAction || menuCount <= 1) ? const MenuButton() : null,
            actions: showAction ? [CommonAppBarActions()] : null,
            title: Text(i18n('esports_title')),
          ),
          body: Obx(() {
            if (controller.loading.value) {
              return const AppStatusView(type: AppStatusType.loading);
            }
            if (controller.error.value.isNotEmpty && controller.matches.isEmpty) {
              return AppStatusView(
                type: AppStatusType.error,
                icon: Remix.trophy_line,
                title: i18n('esports_load_failed'),
                onButtonPressed: () => controller.loadData(),
              );
            }
            return _buildScheduleBody(context);
          }),
        );
      },
    );
  }

  /// 日程视图：游戏筛选 + 按日期分组列表
  Widget _buildScheduleBody(BuildContext context) {
    return Column(
      children: [
        _buildGameFilter(context),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => controller.loadData(),
            child: Obx(() {
              // Dota2 暂未接入数据源
              if (controller.isDota2Filter) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(
                      height: 300,
                      child: AppStatusView(
                        type: AppStatusType.empty,
                        icon: Remix.trophy_line,
                        title: i18n('esports_dota2_pending'),
                        subtitle: i18n('esports_dota2_pending_subtitle'),
                      ),
                    ),
                  ],
                );
              }
              final filtered = controller.filteredMatches;
              if (filtered.isEmpty) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(
                      height: 300,
                      child: AppStatusView(
                        type: AppStatusType.empty,
                        icon: Remix.trophy_line,
                        title: i18n('esports_empty'),
                        subtitle: i18n('esports_empty_subtitle'),
                        buttonText: i18n('refresh'),
                        onButtonPressed: () => controller.loadData(),
                      ),
                    ),
                  ],
                );
              }
              final grouped = controller.groupByDate(filtered);
              return ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: grouped.length,
                itemBuilder: (context, index) {
                  final day = grouped.keys.elementAt(index);
                  final dayMatches = grouped[day]!;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDateHeader(context, day),
                      ...dayMatches.map((m) => _MatchCard(match: m)),
                    ],
                  );
                },
              );
            }),
          ),
        ),
      ],
    );
  }

  /// 游戏筛选条
  Widget _buildGameFilter(BuildContext context) {
    return Obx(() {
      return SizedBox(
        height: 48,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          itemCount: EsportsController.gameFilterKeys.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final bool selected = controller.gameFilter.value == index;
            return ChoiceChip(
              label: Text(i18n(EsportsController.gameFilterKeys[index])),
              selected: selected,
              showCheckmark: false,
              onSelected: (_) => controller.gameFilter.value = index,
            );
          },
        ),
      );
    });
  }

  /// 日期分组标题
  Widget _buildDateHeader(BuildContext context, DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = day.difference(today).inDays;

    String prefix;
    if (diff == -1) {
      prefix = i18n('esports_yesterday');
    } else if (diff == 0) {
      prefix = i18n('esports_today');
    } else if (diff == 1) {
      prefix = i18n('esports_tomorrow');
    } else {
      prefix = '';
    }
    final weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final weekday = weekdays[day.weekday - 1];
    final dateText = '${day.month}月${day.day}日 $weekday';
    final title = prefix.isEmpty ? dateText : '$prefix · $dateText';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 14,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: AppTextStyles.t15.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// 单场赛事卡片
class _MatchCard extends StatelessWidget {
  final EsportsMatch match;
  const _MatchCard({required this.match});

  String get _seriesText {
    final short = match.seriesShortName;
    final full = match.seriesName;
    if (short.isNotEmpty) return short;
    if (full.isNotEmpty) return full;
    return match.gameName;
  }

  String get _stageText {
    if (match.gameStage.isNotEmpty) return match.gameStage;
    if (match.matchName.isNotEmpty && !match.hasTeams) return match.matchName;
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.06), width: 0.5),
      ),
      child: Column(
        children: [
          // 联赛 · 阶段
          Row(
            children: [
              Expanded(
                child: Text(
                  _seriesText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.t12.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_stageText.isNotEmpty)
                Flexible(
                  child: Text(
                    _stageText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.t12.copyWith(color: theme.hintColor),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              // A 队
              Expanded(child: _buildTeam(theme, match.teamAName, match.teamALogo, alignRight: true)),
              // 中间：比分 / 时间 / LIVE
              SizedBox(
                width: 96,
                child: _buildCenterInfo(theme),
              ),
              // B 队
              Expanded(child: _buildTeam(theme, match.teamBName, match.teamBLogo, alignRight: false)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCenterInfo(ThemeData theme) {
    if (match.isLive) {
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'LIVE',
              style: AppTextStyles.t11.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          if (match.scoreA > 0 || match.scoreB > 0) ...[
            const SizedBox(height: 4),
            Text('${match.scoreA} : ${match.scoreB}', style: AppTextStyles.t15.copyWith(fontWeight: FontWeight.w700)),
          ],
        ],
      );
    }
    if (match.isEnded) {
      final bool hasScore = match.scoreA > 0 || match.scoreB > 0;
      return Column(
        children: [
          Text(
            i18n('esports_ended'),
            style: AppTextStyles.t11.copyWith(color: theme.hintColor),
          ),
          if (hasScore) ...[
            const SizedBox(height: 4),
            Text('${match.scoreA} : ${match.scoreB}', style: AppTextStyles.t15.copyWith(fontWeight: FontWeight.w700)),
          ],
        ],
      );
    }
    // 未开始：开赛时间
    final dt = match.startDateTime;
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return Text(
      '$hh:$mm',
      style: AppTextStyles.t16.copyWith(fontWeight: FontWeight.w700, color: theme.colorScheme.primary),
    );
  }

  Widget _buildTeam(ThemeData theme, String name, String logo, {required bool alignRight}) {
    final Widget nameWidget = Text(
      name.isEmpty ? 'TBD' : name,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: alignRight ? TextAlign.right : TextAlign.left,
      style: AppTextStyles.t13.copyWith(fontWeight: FontWeight.w600, height: 1.2),
    );

    Widget logoWidget;
    if (logo.isNotEmpty) {
      logoWidget = ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CachedNetworkImage(
          imageUrl: logo,
          width: 30,
          height: 30,
          fit: BoxFit.cover,
          errorWidget: (_, _, _) => _buildLogoPlaceholder(theme),
        ),
      );
    } else {
      logoWidget = _buildLogoPlaceholder(theme);
    }

    return Row(
      mainAxisAlignment: alignRight ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        if (!alignRight) ...[logoWidget, const SizedBox(width: 8)],
        Flexible(child: nameWidget),
        if (alignRight) ...[const SizedBox(width: 8), logoWidget],
      ],
    );
  }

  Widget _buildLogoPlaceholder(ThemeData theme) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(Remix.gamepad_line, size: 16, color: theme.hintColor),
    );
  }
}
