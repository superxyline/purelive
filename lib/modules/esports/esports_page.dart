import 'package:cached_network_image/cached_network_image.dart';
import 'package:remixicon/remixicon.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/widgets/common_appbar_actions.dart';
import 'package:pure_live/modules/esports/esports_controller.dart';
import 'package:pure_live/routes/app_navigation.dart';
import 'package:pure_live/modules/esports/esports_match.dart';
import 'package:pure_live/modules/esports/favorite_match.dart';
import 'package:pure_live/modules/esports/favorite_match_controller.dart';

/// 赛事页：展示从昨天到 7 天后的电竞赛事日程。
///
/// 数据源：完美世界电竞（CS2）+ lolesports 官方（LOL/VALORANT）
/// + Liquipedia（DOTA2）。
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

  /// 日程视图：游戏筛选 + 日期筛选 + 赛事筛选 + 按日期分组列表
  Widget _buildScheduleBody(BuildContext context) {
    return Column(
      children: [
        _buildGameFilter(context),
        _buildFilterDropdowns(context),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => controller.loadData(),
            child: Obx(() {
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
    // 注意：gameFilter.value 必须在 Obx builder 顶层读取，
    // 若只在 ListView itemBuilder（惰性闭包）里访问，GetX 会误判"Obx 未使用 Rx"而抛异常。
    return Obx(() {
      final int currentFilter = controller.gameFilter.value;
      return SizedBox(
        height: 48,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          itemCount: EsportsController.gameFilterKeys.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final bool selected = currentFilter == index;
            return ChoiceChip(
              label: Text(i18n(EsportsController.gameFilterKeys[index])),
              selected: selected,
              showCheckmark: false,
              onSelected: (_) => controller.setGameFilter(index),
            );
          },
        ),
      );
    });
  }

  /// 筛选下拉：日期 + 赛事 横向并列
  Widget _buildFilterDropdowns(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Row(
        children: [
          Expanded(child: _buildDateDropdown(context)),
          const SizedBox(width: 8),
          Expanded(child: _buildSeriesDropdown(context)),
          const SizedBox(width: 4),
          // 只看已关注赛事
          Obx(() {
            final bool on = controller.showOnlyFavorites.value;
            return IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: i18n('esports_favorite_only'),
              icon: Icon(
                on ? Remix.star_fill : Remix.star_line,
                size: 20,
                color: on ? Colors.amber : Theme.of(context).hintColor,
              ),
              onPressed: () => controller.showOnlyFavorites.value = !on,
            );
          }),
        ],
      ),
    );
  }

  /// 日期下拉：全部日期 + 今天~+7天
  Widget _buildDateDropdown(BuildContext context) {
    return Obx(() {
      final DateTime? currentDate = controller.dateFilter.value;
      final List<DateTime> options = controller.dateFilterOptions;
      return _dropdownShell(
        context,
        child: DropdownButtonHideUnderline(
          child: DropdownButton<DateTime?>(
            isExpanded: true,
            value: currentDate,
            icon: const Icon(Remix.calendar_line, size: 16),
            style: AppTextStyles.t13,
            items: [
              DropdownMenuItem<DateTime?>(
                value: null,
                child: Text(i18n('esports_filter_all_dates'), overflow: TextOverflow.ellipsis),
              ),
              for (final DateTime day in options)
                DropdownMenuItem<DateTime?>(
                  value: day,
                  child: Text(_dateLabel(context, day), overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (DateTime? v) => controller.dateFilter.value = v,
          ),
        ),
      );
    });
  }

  /// 赛事下拉：全部赛事 + 当前游戏下的赛事名
  Widget _buildSeriesDropdown(BuildContext context) {
    return Obx(() {
      final List<String> series = controller.availableSeries;
      final String currentSeries = controller.seriesFilter.value;
      return _dropdownShell(
        context,
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            value: currentSeries.isEmpty ? null : currentSeries,
            icon: const Icon(Remix.trophy_line, size: 16),
            style: AppTextStyles.t13,
            items: [
              DropdownMenuItem<String>(
                value: null,
                child: Text(i18n('esports_filter_all_series'), overflow: TextOverflow.ellipsis),
              ),
              for (final String name in series)
                DropdownMenuItem<String>(
                  value: name,
                  child: Text(name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (String? v) => controller.seriesFilter.value = v ?? '',
          ),
        ),
      );
    });
  }

  /// 下拉容器：统一圆角边框
  Widget _dropdownShell(BuildContext context, {required Widget child}) {
    final theme = Theme.of(context);
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }

  /// 日期筛选按钮文案：昨天/今天/明天 用文字，其余用 M/d
  String _dateLabel(BuildContext context, DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = day.difference(today).inDays;
    if (diff == -1) return i18n('esports_yesterday');
    if (diff == 0) return i18n('esports_today');
    if (diff == 1) return i18n('esports_tomorrow');
    return '${day.month}/${day.day}';
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
          // 第一行：联赛名（左）+ 阶段名（中间列，与时间/比分垂直对齐）
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
              SizedBox(
                width: 96,
                child: _stageText.isEmpty
                    ? null
                    : Center(
                        child: Text(
                          _stageText,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.t12.copyWith(color: theme.hintColor),
                        ),
                      ),
              ),
              // 右侧：赛事关注星标
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Obx(() {
                    final favController = Get.find<FavoriteMatchController>();
                    final bool fav = favController.isFavorite(match.matchId);
                    return IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Icon(
                        fav ? Remix.star_fill : Remix.star_line,
                        size: 18,
                        color: fav ? Colors.amber : theme.hintColor,
                      ),
                      onPressed: () =>
                          favController.toggle(FavoriteMatch.fromEsportsMatch(match)),
                    );
                  }),
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
    // 中间列宽度固定 96，所有内容用 Center 包裹确保水平居中
    if (match.isLive) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'LIVE',
              textAlign: TextAlign.center,
              style: AppTextStyles.t11.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          if (match.scoreA > 0 || match.scoreB > 0) ...[
            const SizedBox(height: 4),
            Center(
              child: Text(
                '${match.scoreA} : ${match.scoreB}',
                textAlign: TextAlign.center,
                style: AppTextStyles.t15.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
          // 官方给出了直播间且比赛进行中：提供跳转
          if (match.livePlatform.isNotEmpty && match.liveRoomId.isNotEmpty) ...[
            const SizedBox(height: 6),
            InkWell(
              onTap: () => AppNavigator.toLiveRoomDetail(
                liveRoom: LiveRoom(
                  roomId: match.liveRoomId,
                  platform: match.livePlatform,
                  nick: '${match.teamAName} vs ${match.teamBName}'.trim(),
                  title: match.seriesName,
                  status: true,
                ),
              ),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.live_tv_rounded, size: 12, color: theme.colorScheme.primary),
                    const SizedBox(width: 3),
                    Text(
                      '${i18n('esports_watch_live')}·${Sites.of(match.livePlatform).name}',
                      style: AppTextStyles.t11.copyWith(color: theme.colorScheme.primary),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      );
    }
    if (match.isEnded) {
      final bool hasScore = match.scoreA > 0 || match.scoreB > 0;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Center(
            child: Text(
              i18n('esports_ended'),
              textAlign: TextAlign.center,
              style: AppTextStyles.t11.copyWith(color: theme.hintColor),
            ),
          ),
          if (hasScore) ...[
            const SizedBox(height: 4),
            Center(
              child: Text(
                '${match.scoreA} : ${match.scoreB}',
                textAlign: TextAlign.center,
                style: AppTextStyles.t15.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      );
    }
    // 未开始：开赛时间
    final dt = match.startDateTime;
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return Center(
      child: Text(
        '$hh:$mm',
        textAlign: TextAlign.center,
        style: AppTextStyles.t16.copyWith(fontWeight: FontWeight.w700, color: theme.colorScheme.primary),
      ),
    );
  }

  Widget _buildTeam(ThemeData theme, String name, String logo, {required bool alignRight}) {
    // TBD（无队名）时队标统一用手柄图标占位，即使接口给了 logo URL 也忽略
    // （TBD 队伍的 logo 通常是无效占位图，手柄图标更美观统一）
    final bool isTbd = name.isEmpty;
    final Widget nameWidget = Text(
      name.isEmpty ? 'TBD' : name,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: alignRight ? TextAlign.right : TextAlign.left,
      style: AppTextStyles.t13.copyWith(fontWeight: FontWeight.w600, height: 1.2),
    );

    Widget logoWidget;
    if (!isTbd && logo.isNotEmpty) {
      logoWidget = ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CachedNetworkImage(
          imageUrl: logo,
          width: 30,
          height: 30,
          fit: BoxFit.cover,
          // 完美世界队标有防盗链（需 Referer），统一携带 UA + Referer
          httpHeaders: const {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36',
            'Referer': 'https://data.wanmei.com/',
          },
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
