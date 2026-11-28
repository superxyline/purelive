import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:pure_live/common/index.dart';

import '../core/tv_theme.dart';
import 'tv_widgets.dart';
/// TV 直播间卡片（索引高亮驱动，无 Focus 依赖——调用方按索引传 highlighted）。
/// 供主页/搜索/分类房间等网格复用。
class TvRoomCard extends StatelessWidget {
  const TvRoomCard({required this.room, required this.highlighted});

  final LiveRoom room;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final live = room.liveStatus == LiveStatus.live && room.status == true;
    final nick = (room.nick?.isNotEmpty == true) ? room.nick! : (room.roomId ?? '');
    final title = (room.title?.isNotEmpty == true) ? room.title! : nick;
    final fg = highlighted ? Colors.black : TvTheme.textPrimary;
    final sub = highlighted ? Colors.black54 : TvTheme.textSecondary;
    return AnimatedContainer(
      duration: TvTheme.focusDuration,
      curve: TvTheme.focusCurve,
      decoration: BoxDecoration(
        color: highlighted ? TvTheme.focusedCard : TvTheme.card,
        borderRadius: BorderRadius.circular(context.tvDp(TvTheme.cardRadius)),
        border: Border.all(
          color: highlighted ? TvTheme.focusColor : Colors.transparent,
          width: 2,
        ),
        boxShadow: highlighted ? TvTheme.focusGlow : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(context.tvDp(TvTheme.cardRadius)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (room.cover != null && room.cover!.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: room.cover!,
                      fit: BoxFit.cover,
                      fadeInDuration: const Duration(milliseconds: 150),
                      memCacheWidth: 640,
                      errorWidget: (_, _, _) => Container(
                        color: TvTheme.subtleFill,
                        child: Icon(Icons.live_tv_rounded,
                            size: context.tvDp(40), color: TvTheme.textSecondary),
                      ),
                    )
                  else
                    Container(
                      color: TvTheme.subtleFill,
                      child: Icon(Icons.live_tv_rounded,
                          size: context.tvDp(40), color: TvTheme.textSecondary),
                    ),
                  Positioned(
                    top: context.tvDp(8),
                    left: context.tvDp(8),
                    child: Row(
                      children: [
                        TvStatusChip(label: (room.platform ?? '').toUpperCase()),
                        if (live) ...[
                          SizedBox(width: context.tvDp(4)),
                          TvStatusChip(label: 'LIVE'),
                        ],
                        // 开播即置顶标记：长按 OK 切换，置顶的直播间开播后恒排最前
                        if (SettingsService.to.fav.isPinned(room)) ...[
                          SizedBox(width: context.tvDp(4)),
                          TvStatusChip(label: '置顶', icon: Icons.push_pin_rounded),
                        ],
                      ],
                    ),
                  ),
                  Positioned(
                    right: context.tvDp(8),
                    bottom: context.tvDp(8),
                    child: TvStatusChip(label: _heat()),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                  context.tvDp(10), context.tvDp(6), context.tvDp(10), context.tvDp(8)),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: context.tvDp(13),
                    foregroundImage:
                        (room.avatar?.isNotEmpty == true) ? CachedNetworkImageProvider(room.avatar!) : null,
                    backgroundColor: highlighted ? Colors.black12 : TvTheme.subtleFill,
                  ),
                  SizedBox(width: context.tvDp(8)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: context.tvSp(15),
                            fontWeight: FontWeight.w700,
                            color: fg,
                            height: 1.2,
                          ),
                        ),
                        SizedBox(height: context.tvDp(2)),
                        Text(
                          nick,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: context.tvSp(13), color: sub, height: 1.0),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _heat() {
    final heat = (room.watching?.trim().isNotEmpty ?? false)
        ? room.watching!.trim()
        : (room.popularity ?? '');
    return heat;
  }
}
