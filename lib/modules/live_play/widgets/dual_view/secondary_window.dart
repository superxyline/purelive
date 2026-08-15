import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/live_play/live_play_controller.dart';
import 'package:pure_live/player/core/secondary_player_service.dart';
import 'package:pure_live/modules/live_play/widgets/dual_view/dual_view_picker_sheet.dart';

/// 双开副窗口（小窗）。
///
/// 显示副直播间画面，始终静音；整窗点击 = 互换主副，右上角可关闭，
/// 底部"换一个"可只替换副房间。
class SecondaryWindow extends StatelessWidget {
  const SecondaryWindow({super.key});

  @override
  Widget build(BuildContext context) {
    final service = SecondaryPlayerService.instance;
    return Obx(() {
      if (!service.isActive.value && !service.isLoading.value) {
        return const SizedBox.shrink();
      }
      return Material(
        color: Colors.black,
        elevation: 6,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (service.isActive.value) service.videoWidget,
            if (service.isLoading.value)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            if (service.isFailed.value && !service.isLoading.value)
              Container(
                color: Colors.black87,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(
                      i18n("dual_view_not_live"),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ),
            // 整窗点击 = 互换主副
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () =>
                    service.swapWithMain(Get.find<LivePlayController>()),
              ),
            ),
            // 左上角：静音标识
            const Positioned(
              left: 4,
              top: 4,
              child: _Badge(icon: Icons.volume_off_rounded),
            ),
            // 右上角：关闭副窗口
            Positioned(
              right: 2,
              top: 2,
              child: _RoundButton(
                icon: Icons.close_rounded,
                tooltip: i18n("dual_view_close"),
                onTap: () => service.close(),
              ),
            ),
            // 底部：主播昵称 + 换一个
            Positioned(
              left: 4,
              right: 4,
              bottom: 2,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      service.room.value?.nick ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        shadows: [Shadow(color: Colors.black, blurRadius: 3)],
                      ),
                    ),
                  ),
                  _RoundButton(
                    icon: Icons.autorenew_rounded,
                    tooltip: i18n("dual_view_replace"),
                    onTap: () => _openPicker(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  void _openPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DualViewPickerSheet(
        onPicked: (room) {
          Navigator.of(ctx).pop();
          SecondaryPlayerService.instance.loadRoom(room);
        },
      ),
    );
  }
}

/// 半透明小圆角图标按钮（副窗口用，比 IconButton 更紧凑）
class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap, this.tooltip});

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: tooltip ?? '',
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.black45,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 13, color: Colors.white),
        ),
      ),
    );
  }
}

/// 角标（静音标识）
class _Badge extends StatelessWidget {
  const _Badge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
      child: Icon(icon, size: 11, color: Colors.white),
    );
  }
}

/// 可拖动的副窗口容器：包裹 [SecondaryWindow]，支持整窗拖动改变位置。
///
/// 默认停靠在播放页主体右下角（不遮挡主画面/分辨率栏），拖动到任意位置后
/// 停留在那里；拖动范围被限制在播放页可用区域内。整窗"点一下"仍是互换主副。
class DraggableSecondaryWindow extends StatefulWidget {
  const DraggableSecondaryWindow({
    super.key,
    required this.maxWidth,
    required this.maxHeight,
  });

  /// 播放页 body 的可用宽/高（用于计算默认位置与拖动边界）
  final double maxWidth;
  final double maxHeight;

  @override
  State<DraggableSecondaryWindow> createState() =>
      _DraggableSecondaryWindowState();
}

class _DraggableSecondaryWindowState extends State<DraggableSecondaryWindow> {
  /// 相对默认位置的拖动偏移
  Offset _drag = Offset.zero;

  double get _width {
    final w = widget.maxWidth;
    final isNarrow = w <= 680;
    return (w * (isNarrow ? 0.4 : 0.24) * 1.5).clamp(180.0, 390.0).toDouble();
  }

  double get _height => _width * 9 / 16;

  /// 默认停靠右下角：右下留边 8 / 12，不遮挡上方主画面与分辨率栏
  double get _defaultLeft =>
      (widget.maxWidth - _width - 8).clamp(0.0, double.infinity);

  double get _defaultTop =>
      (widget.maxHeight - _height - 12).clamp(0.0, double.infinity);

  Offset get _pos {
    final maxLeft = (widget.maxWidth - _width).clamp(0.0, double.infinity);
    final maxTop = (widget.maxHeight - _height).clamp(0.0, double.infinity);
    return Offset(
      (_defaultLeft + _drag.dx).clamp(0.0, maxLeft),
      (_defaultTop + _drag.dy).clamp(0.0, maxTop),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final service = SecondaryPlayerService.instance;
      if (!service.isActive.value && !service.isLoading.value) {
        return const SizedBox.shrink();
      }
      final pos = _pos;
      return Positioned(
        left: pos.dx,
        top: pos.dy,
        width: _width,
        height: _height,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) {},
          onPanUpdate: (details) {
            setState(() => _drag += details.delta);
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              const SecondaryWindow(),
              // 顶部小把手：提示可拖动
              Positioned(
                top: 2,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      width: 24,
                      height: 3,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}
