import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/live_play/controllers/live_play_controller.dart';
import 'package:pure_live/player/core/audio_companion_service.dart';

/// 音画对齐预览：同一屏并排看"主直播间画面"和"解说源画面"，
/// 各自可以独立暂停，把两边暂停在同一时刻后点确认，退出预览即为对齐状态。
///
/// 为什么这样做：直播流没法回溯，靠听感判断几秒差很难；
/// 但两个画面里同一个事件（比分、画面切镜、口型）是能对上的——
/// 暂停快的那一路等另一路追上，两路播放位置就一致了，恢复后自然同步。
class AudioCompanionAlignPage extends StatefulWidget {
  const AudioCompanionAlignPage({super.key, required this.controller});

  final LivePlayController controller;

  @override
  State<AudioCompanionAlignPage> createState() => _AudioCompanionAlignPageState();
}

class _AudioCompanionAlignPageState extends State<AudioCompanionAlignPage> {
  final AudioCompanionService _service = AudioCompanionService.instance;

  bool _mainPaused = false;
  bool _sourcePaused = false;

  @override
  void initState() {
    super.initState();
    // 预览期间副音轨要出画面，打开视频解码
    _service.setPreview(true);
  }

  @override
  void dispose() {
    // 离开预览：恢复两路播放，并关掉副音轨的视频解码继续省电
    if (_mainPaused) {
      GlobalPlayerService.instance.playerManager.resume(source: 'audioCompanion.preview', syncCompanion: false);
    }
    if (_sourcePaused) {
      _service.resumePlayback();
    }
    _service.setPreview(false);
    super.dispose();
  }

  Future<void> _toggleMain() async {
    final manager = GlobalPlayerService.instance.playerManager;
    final next = !_mainPaused;
    setState(() => _mainPaused = next);
    if (next) {
      await manager.pause(source: 'audioCompanion.preview', syncCompanion: false);
    } else {
      await manager.resume(source: 'audioCompanion.preview', syncCompanion: false);
    }
  }

  Future<void> _toggleSource() async {
    final next = !_sourcePaused;
    setState(() => _sourcePaused = next);
    if (next) {
      await _service.pausePlayback();
    } else {
      await _service.resumePlayback();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final manager = GlobalPlayerService.instance.playerManager;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(i18n('audio_companion_align_title'), style: AppTextStyles.t16Bold.copyWith(color: Colors.white)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Text(
              i18n('audio_companion_align_hint'),
              style: AppTextStyles.t12.copyWith(color: Colors.white70, height: 1.4),
            ),
          ),
          Expanded(
            child: _Pane(
              label: i18n('audio_companion_align_main'),
              subtitle: null,
              paused: _mainPaused,
              onToggle: _toggleMain,
              child: manager.currentVideoWidget,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Obx(() {
              final room = _service.room.value;
              final name = room == null
                  ? ''
                  : '${room.nick?.isNotEmpty == true ? room.nick : room.roomId} · ${room.platform?.toUpperCase() ?? ''}';
              return _Pane(
                label: i18n('audio_companion_align_source'),
                subtitle: name.isEmpty ? null : name,
                paused: _sourcePaused,
                onToggle: _toggleSource,
                child: _service.videoWidget,
              );
            }),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
                      onPressed: () async {
                        await widget.controller.disableAudioCompanion();
                        if (context.mounted) Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: Text(i18n('audio_companion_stop')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: Text(i18n('audio_companion_align_confirm')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 单路画面容器：左上角标签、右下角暂停/播放按钮。
class _Pane extends StatelessWidget {
  const _Pane({
    required this.label,
    required this.subtitle,
    required this.paused,
    required this.onToggle,
    required this.child,
  });

  final String label;
  final String? subtitle;
  final bool paused;
  final VoidCallback onToggle;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (child != null)
            FittedBox(fit: BoxFit.contain, child: SizedBox(width: 1920, height: 1080, child: child!))
          else
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          Positioned(
            left: 10,
            top: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
              child: Text(
                subtitle == null ? label : '$label · $subtitle',
                style: AppTextStyles.t11.copyWith(color: Colors.white),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Positioned(
            right: 8,
            bottom: 8,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onToggle,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(
                    paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
          if (paused)
            Positioned(
              left: 10,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(i18n('audio_companion_align_paused'), style: AppTextStyles.t11.copyWith(color: Colors.white)),
              ),
            ),
        ],
      ),
    );
  }
}
