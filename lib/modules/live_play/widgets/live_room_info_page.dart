import 'package:remixicon/remixicon.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/widgets/common_avatar.dart';
import 'package:pure_live/modules/live_play/controllers/live_play_controller.dart';

/// 直播间信息展示（弹幕区 tab 与长按菜单对话框共用）。
/// 只消费详情接口已解析进 LiveRoom 的字段，不做网络请求。
class LiveRoomInfoPage extends GetView<LivePlayController> {
  const LiveRoomInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final detail = controller.state.value.room.detail;
    if (detail == null) {
      return AppStatusView(type: AppStatusType.loading, title: "", subtitle: "");
    }
    return LiveRoomInfoView(detail: detail);
  }
}

class LiveRoomInfoView extends StatelessWidget {
  const LiveRoomInfoView({super.key, required this.detail});

  final LiveRoom detail;

  String? get _liveDurationText {
    final startMs = detail.liveStartTime;
    if (startMs == null || startMs <= 0) return null;
    final elapsed = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(startMs));
    if (elapsed.inMinutes < 1) return null;
    final hours = elapsed.inHours;
    final minutes = elapsed.inMinutes % 60;
    if (hours > 0) {
      return '$hours${i18n('hour')} $minutes${i18n('minute')}';
    }
    return '$minutes${i18n('minute')}';
  }

  /// 观众指标行：按平台口径分开展示（人气/累计观看/真实在线不混用同值重复行）
  List<({String label, String value})> get _audienceRows {
    final rows = <({String label, String value})>[];
    final metricType = detail.audienceMetricType ?? AudienceMetricType.unknown;
    final watching = (detail.watching?.isNotEmpty == true ? detail.watching : detail.popularity) ?? '';

    if (metricType == AudienceMetricType.totalViewers) {
      if ((detail.totalViewers ?? '').isNotEmpty) {
        rows.add((label: i18n('room_info_audience_total'), value: detail.totalViewers!));
      }
    } else if (watching.isNotEmpty) {
      rows.add((label: i18n('room_info_audience_popularity'), value: watching));
    }
    final online = detail.onlineViewers ?? '';
    if (online.isNotEmpty && !rows.any((r) => r.value == online)) {
      rows.add((label: i18n('room_info_audience_online'), value: online));
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final site = detail.platform != null && Sites.isSupported(detail.platform!)
        ? Sites.of(detail.platform!)
        : null;
    final rows = <({String label, String value})>[
      if ((detail.area ?? '').isNotEmpty) (label: i18n('room_info_area'), value: detail.area!),
      if ((detail.roomId ?? '').isNotEmpty) (label: i18n('osd_room'), value: detail.roomId!),
      ..._audienceRows,
      // 粉丝数：仅部分平台详情接口提供（B站/虎牙登录态/斗鱼），缺失则不显示该行
      if ((detail.followers ?? '').isNotEmpty && detail.followers != '0')
        (
          label: i18n('room_info_followers'),
          value: readableCount(detail.followers!),
        ),
      if (_liveDurationText != null) (label: i18n('room_info_live_duration'), value: _liveDurationText!),
    ];
    final introduction = (detail.introduction ?? '').trim();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CommonAvatar(avatarUrl: detail.avatar, radius: 22, fallbackName: detail.nick),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      detail.nick?.isNotEmpty == true ? detail.nick! : '-',
                      style: AppTextStyles.t16.copyWith(fontWeight: FontWeight.w700, color: theme.colorScheme.onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (site != null) ...[
                          Image.asset(site.logo, width: 14, height: 14),
                          const SizedBox(width: 4),
                          Text(
                            site.name,
                            style: AppTextStyles.t11.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                        if (detail.isRecord == true) ...[
                          if (site != null) const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              i18n('room_info_replay'),
                              style: AppTextStyles.t11.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if ((detail.title ?? '').isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              detail.title!,
              style: AppTextStyles.t14.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
          ],
          if (rows.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final row in rows)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: theme.dividerColor.withValues(alpha: 0.06), width: 0.8),
                    ),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${row.label}  ',
                            style: AppTextStyles.t11.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                          TextSpan(
                            text: row.value,
                            style: AppTextStyles.t11.copyWith(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.dividerColor.withValues(alpha: 0.04), width: 0.8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Remix.information_line, size: 14, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text(
                      i18n('room_info_introduction'),
                      style: AppTextStyles.t11.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  introduction.isNotEmpty ? introduction : i18n('room_info_introduction_empty'),
                  style: AppTextStyles.t13.copyWith(
                    color: introduction.isNotEmpty
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
