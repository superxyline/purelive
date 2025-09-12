import 'package:flutter/material.dart';
import 'package:pure_live/common/utils/text_util.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:pure_live/modules/live_play/live_play_controller.dart';

class PlayOther extends StatefulWidget {
  final LivePlayController controller;
  const PlayOther({required this.controller, super.key});

  @override
  State<PlayOther> createState() => _PlayOtherState();
}

class _PlayOtherState extends State<PlayOther> {
  late final List<LiveRoom> onlineRooms;

  @override
  void initState() {
    super.initState();
    onlineRooms = widget.controller.settings.favoriteRooms.where((room) => room.liveStatus == LiveStatus.live).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16.0),
      clipBehavior: Clip.hardEdge,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
      child: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 10, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('正在直播', style: Theme.of(context).textTheme.titleMedium),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 300,
              child: ListView.builder(
                itemCount: onlineRooms.length,
                itemBuilder: (context, index) {
                  return EnhancedListTile(room: onlineRooms[index], dense: true, onTap: widget.controller.switchRoom);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: const Text('关闭'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 增强版 ListTile（带观看数、平台标识等）
class EnhancedListTile extends StatelessWidget {
  final LiveRoom room;
  final bool dense;
  final Function(LiveRoom) onTap;
  const EnhancedListTile({super.key, required this.room, this.dense = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: dense,
      leading: CircleAvatar(
        radius: dense ? 18 : 20,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        foregroundImage: room.avatar?.isNotEmpty == true ? CachedNetworkImageProvider(room.avatar!) : null,
        child: room.avatar?.isNotEmpty != true
            ? Icon(Icons.person, color: Theme.of(context).colorScheme.onSurface, size: dense ? 24 : 28)
            : null,
      ),
      title: Text(
        room.title!,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: dense ? 13 : 15, fontWeight: FontWeight.w500),
      ),
      subtitle: Row(
        children: [
          Text(
            room.nick!,
            style: TextStyle(fontSize: dense ? 11 : 13, fontWeight: FontWeight.w500),
          ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              room.platform?.toUpperCase() ?? '',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w400, color: Colors.white),
            ),
          ),
          if (room.watching != null)
            Text(
              readableCount(room.watching!),
              style: TextStyle(fontSize: dense ? 12 : 14, color: Colors.orange.shade700),
            ),
        ],
      ),
      visualDensity: dense ? VisualDensity.compact : VisualDensity.standard,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      onTap: () {
        Navigator.of(context).pop();
        onTap(room);
      },
    );
  }
}
