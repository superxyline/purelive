import 'dart:async';

import 'package:pure_live/common/index.dart';
import 'package:pure_live/player/adapters/media_kit_adapter.dart';
import 'package:pure_live/player/core/audio_companion_service.dart';
import 'package:pure_live/player/core/player_manager.dart';
import 'package:pure_live/player/global_player_service.dart';

import 'frame_sync/frame_signature.dart';
import 'frame_sync/offset_estimator.dart';

/// 自动对齐失败的原因（UI 层负责翻译成文案）。
enum AutoAlignFailure {
  /// 当前播放内核不是 mpv（取不到帧）
  engineUnsupported,

  /// 任一路没有画面（还在缓冲 / 纯音频 / 未起播）
  noPicture,

  /// 抓到的有效帧太少
  notEnoughFrames,

  /// 画面基本静止（广告 / 静态界面 / 纯黑）
  staticPicture,

  /// 两路画面找不到同一场景（机位不同 / 不是同一场比赛）
  noMatch,

  /// 画面重复度太高，多个偏移同样可信
  ambiguous,

  /// 差值超过可控范围
  outOfRange,
}

class AutoAlignResult {
  const AutoAlignResult({
    this.beforeSeconds = 0,
    this.afterSeconds = 0,
    this.confidence = 0,
    this.applied = false,
    this.failure,
  });

  /// 检测到的差值（**正数 = 解说更快**，也就是把解说延后这么多秒即可对齐）
  final double beforeSeconds;

  /// 调整后复核的残余差值（正数 = 解说仍更快）
  final double afterSeconds;

  final double confidence;

  /// 是否真的执行过暂停/恢复
  final bool applied;

  final AutoAlignFailure? failure;

  bool get ok => failure == null;

  /// 复核残余在 0.5 秒内视为对齐成功
  bool get withinTolerance => ok && afterSeconds.abs() <= 0.5;
}

/// 副音轨自动对齐：比对两路画面算出时间差，再把快的那一路暂停等另一路追上。
///
/// 为什么不是"把快的一路往回 seek"：直播流（FLV）不可回溯，能做的只有延后，
/// 和现有手动对齐页"暂停快的一路"是同一个动作，这里只是把"差几秒、何时恢复"
/// 交给算法判断。
///
/// 采集策略：一次性抓 10 帧（约 1.4 秒窗口），两路**并行**抓以保证 pts 来自
/// 同一墙钟；不持续采样——手机上持续解码两路 + 抓帧的功耗不可接受。
class AudioCompanionSync {
  AudioCompanionSync._();
  static final AudioCompanionSync instance = AudioCompanionSync._();

  static const int _sampleCount = 10;
  static const int _verifyCount = 8;
  static const int _sampleIntervalMs = 150;
  static const String _pauseSource = 'audioCompanion.autoAlign';

  /// 执行一次自动对齐。整个过程约 4~8 秒（采样 2 秒 + 等待 + 复核 2 秒）。
  Future<AutoAlignResult> autoAlign() async {
    final manager = GlobalPlayerService.instance.playerManager;
    final main = manager.currentPlayer;
    if (main is! MediaKitAdapter) {
      return const AutoAlignResult(failure: AutoAlignFailure.engineUnsupported);
    }
    final companion = AudioCompanionService.instance;
    if (!companion.isActive.value || !companion.hasRoom) {
      return const AutoAlignResult(failure: AutoAlignFailure.noPicture);
    }

    final first = await _sample(main, companion, _sampleCount);
    if (first == null) {
      return const AutoAlignResult(failure: AutoAlignFailure.noPicture);
    }

    final estimateResult = estimateOffset(first.a, first.b);
    if (!estimateResult.isOk) {
      return AutoAlignResult(failure: _map(estimateResult.reason!));
    }
    final estimate = estimateResult.estimate!;
    if (!estimate.isTrusted) {
      return AutoAlignResult(
        beforeSeconds: estimate.offsetSeconds,
        confidence: estimate.confidence,
        failure: AutoAlignFailure.noMatch,
      );
    }

    // 已经很接近就不用动：0.3 秒内人耳基本听不出，反复暂停反而干扰观看
    if (estimate.offsetSeconds.abs() < 0.3) {
      return AutoAlignResult(
        beforeSeconds: estimate.offsetSeconds,
        afterSeconds: estimate.offsetSeconds,
        confidence: estimate.confidence,
      );
    }

    await _applyDelay(estimate.offsetSeconds, manager, companion);

    // 暂停恢复后 mpv 需要重新出帧（尤其是低清晰度那路），等一小会儿再复核
    await Future.delayed(const Duration(milliseconds: 900));

    var after = 0.0;
    final verify = await _sample(main, companion, _verifyCount);
    if (verify != null) {
      final again = estimateOffset(verify.a, verify.b);
      if (again.isOk) after = again.estimate!.offsetSeconds;
    }

    return AutoAlignResult(
      beforeSeconds: estimate.offsetSeconds,
      afterSeconds: after,
      confidence: estimate.confidence,
      applied: true,
    );
  }

  /// 暂停快的一路，等另一路追上后恢复。
  ///
  /// offset < 0：画面（A）更快 → 暂停主画面；
  /// offset > 0：解说（B）更快 → 暂停副音轨。
  Future<void> _applyDelay(
    double offset,
    PlayerManager manager,
    AudioCompanionService companion,
  ) async {
    final ms = (offset.abs() * 1000).round().clamp(200, 60000);
    if (offset < 0) {
      await manager.pause(source: _pauseSource, syncCompanion: false);
      await Future.delayed(Duration(milliseconds: ms));
      await manager.resume(source: _pauseSource, syncCompanion: false);
    } else if (offset > 0) {
      await companion.pausePlayback();
      await Future.delayed(Duration(milliseconds: ms));
      await companion.resumePlayback();
    }
  }

  Future<_Samples?> _sample(
    MediaKitAdapter main,
    AudioCompanionService companion,
    int count,
  ) async {
    final a = <FrameSample>[];
    final b = <FrameSample>[];
    final clock = Stopwatch()..start();
    for (var i = 0; i < count; i++) {
      // pts 取"发起抓帧"的时刻：两路并行抓，内容属于同一墙钟时刻
      final pts = clock.elapsedMilliseconds / 1000.0;
      final frames = await Future.wait([
        main.captureGrayFrame(),
        companion.captureGrayFrame(),
      ]);
      final grayA = frames[0];
      final grayB = frames[1];
      if (grayA != null && grayB != null) {
        a.add(FrameSample(pts: pts, signature: FrameSignature.fromGray(grayA)));
        b.add(FrameSample(pts: pts, signature: FrameSignature.fromGray(grayB)));
      }
      if (i < count - 1) {
        await Future.delayed(const Duration(milliseconds: _sampleIntervalMs));
      }
    }
    if (a.length < 4 || b.length < 4) return null;
    return _Samples(a, b);
  }

  AutoAlignFailure _map(OffsetRejectReason reason) {
    switch (reason) {
      case OffsetRejectReason.notEnoughFrames:
        return AutoAlignFailure.notEnoughFrames;
      case OffsetRejectReason.staticPicture:
        return AutoAlignFailure.staticPicture;
      case OffsetRejectReason.noMatch:
        return AutoAlignFailure.noMatch;
      case OffsetRejectReason.ambiguous:
        return AutoAlignFailure.ambiguous;
      case OffsetRejectReason.outOfRange:
        return AutoAlignFailure.outOfRange;
    }
  }
}

class _Samples {
  const _Samples(this.a, this.b);

  final List<FrameSample> a;
  final List<FrameSample> b;
}
