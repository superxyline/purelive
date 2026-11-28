import 'dart:math' as math;

import 'frame_signature.dart';

/// 一路画面在某个墙钟时刻的指纹样本。
///
/// [pts] 是抓帧时刻（相对同一次校准起点的秒数）。两路的 pts 必须来自同一个
/// 墙钟（用 `Stopwatch` 或 `DateTime.now()` 统一取），这是唯一共享的时间轴。
class FrameSample {
  const FrameSample({required this.pts, required this.signature});

  final double pts;
  final FrameSignature signature;
}

/// 自动对齐的拒绝原因（要能直接告诉用户"为什么没对上"）。
enum OffsetRejectReason {
  /// 任一路没有取到足够的帧（没画面 / 还在缓冲）
  notEnoughFrames,

  /// 画面几乎不动，匹配没有意义（广告、静态界面、纯黑）
  staticPicture,

  /// 两路画面找不到相似片段（机位不同 / 不是同一场比赛）
  noMatch,

  /// 找到多个同样可信但互相矛盾的偏移（画面重复性太强）
  ambiguous,

  /// 算出来的差值超过可控范围（直播缓冲一般只留得住几十秒）
  outOfRange,
}

class OffsetEstimate {
  const OffsetEstimate({
    required this.offsetSeconds,
    required this.confidence,
    required this.pairs,
  });

  /// `a.pts - b.pts`：**正数表示 A 的内容更晚（A 落后 B）**，也就是 B 更快，
  /// 需要把 B 延后 [offsetSeconds] 秒才能对齐；负数反之。
  final double offsetSeconds;

  /// 0~1，用于决定"要不要相信这次结果"。
  final double confidence;

  /// 参与投票的帧对数。
  final int pairs;

  bool get isTrusted => confidence >= 0.55;
}

class OffsetResult {
  const OffsetResult.ok(this.estimate) : reason = null;
  const OffsetResult.rejected(this.reason) : estimate = null;

  final OffsetEstimate? estimate;
  final OffsetRejectReason? reason;

  bool get isOk => estimate != null;
}

/// 参数默认值参考 Fy1Sync 实测值，按移动端"帧少、间隔大"的情况略放宽。
class OffsetEstimatorOptions {
  const OffsetEstimatorOptions({
    this.bucketSeconds = 0.06,
    this.maxCoarse = 0.28,
    this.maxDetail = 0.055,
    this.minPairs = 3,
    this.maxOffsetSeconds = 60,
    this.minMotion = 0.0015,
    this.ambiguityMarginSeconds = 0.25,
  });

  /// 偏移假设分桶宽度（帧间隔的一半左右）。
  final double bucketSeconds;

  /// 粗匹配阈值（块哈希平均汉明距离）。
  final double maxCoarse;

  /// 精匹配阈值（灰度差，0~1）。
  final double maxDetail;

  /// 至少需要多少对帧才采信。
  final int minPairs;

  /// 可接受的最大差值。
  final double maxOffsetSeconds;

  /// 画面运动量下限（相邻帧灰度差的中位数），低于视为静止画面。
  final double minMotion;

  /// 次优解与最优解相差多少秒以内算"歧义"。
  final double ambiguityMarginSeconds;
}

/// 从两路帧序列估计时间偏移。
///
/// 思路：把两路的所有帧两两比对，保留"看起来是同一画面"的配对，每对给出一个
/// 偏移假设（`a.pts - b.pts`），再对假设做分桶投票——真正的偏移会形成明显的
/// 峰，噪声配对则散落在各处。最后用峰内配对的偏移中位数作为结果。
///
/// 相比完整的时序动态规划（Fy1Sync 的做法），这里省掉了逐对递推：移动端只在
/// 用户点"自动对齐"时抓十来帧，序列短且间隔固定，投票峰值已经足够稳定。
OffsetResult estimateOffset(
  List<FrameSample> a,
  List<FrameSample> b, {
  OffsetEstimatorOptions options = const OffsetEstimatorOptions(),
}) {
  if (a.length < 4 || b.length < 4) {
    return const OffsetResult.rejected(OffsetRejectReason.notEnoughFrames);
  }

  // 静止画面先排除：两路都在放静态图时，任意两帧都"很像"，投票必然误判。
  if (_medianMotion(a) < options.minMotion || _medianMotion(b) < options.minMotion) {
    return const OffsetResult.rejected(OffsetRejectReason.staticPicture);
  }

  final candidates = <_Candidate>[];
  for (final sampleA in a) {
    for (final sampleB in b) {
      final coarse = FrameSignature.coarseDistance(sampleA.signature, sampleB.signature);
      if (coarse > options.maxCoarse) continue;
      final detail = FrameSignature.detailDistance(sampleA.signature, sampleB.signature);
      if (detail > options.maxDetail) continue;
      candidates.add(_Candidate(
        offset: sampleA.pts - sampleB.pts,
        cost: detail + coarse * 0.03,
      ));
    }
  }
  if (candidates.length < options.minPairs) {
    return const OffsetResult.rejected(OffsetRejectReason.noMatch);
  }

  // 分桶投票：权重让"更像"的配对影响更大。
  final buckets = <int, List<_Candidate>>{};
  for (final c in candidates) {
    final key = (c.offset / options.bucketSeconds).round();
    buckets.putIfAbsent(key, () => []).add(c);
  }

  final ranked = buckets.entries.toList()
    ..sort((x, y) => _bucketWeight(y.value).compareTo(_bucketWeight(x.value)));

  final best = ranked.first;
  final bestWeight = _bucketWeight(best.value);
  if (best.value.length < options.minPairs) {
    return const OffsetResult.rejected(OffsetRejectReason.noMatch);
  }

  final bestOffset = _median(best.value.map((c) => c.offset).toList());

  // 歧义检测：如果另一个远离的桶也有可比的可信度，说明画面重复性太强
  // （比如两路都在放同一段循环素材），此时宁可不动也不能瞎调。
  for (final entry in ranked.skip(1)) {
    if (entry.value.length < options.minPairs) continue;
    final offset = _median(entry.value.map((c) => c.offset).toList());
    if ((offset - bestOffset).abs() <= options.ambiguityMarginSeconds) continue;
    if (_bucketWeight(entry.value) >= bestWeight * 0.75) {
      return const OffsetResult.rejected(OffsetRejectReason.ambiguous);
    }
  }

  if (bestOffset.abs() > options.maxOffsetSeconds) {
    return const OffsetResult.rejected(OffsetRejectReason.outOfRange);
  }

  // 置信度：票数够多 + 桶内偏移足够集中 + 距离足够小。
  final spread = _spread(best.value.map((c) => c.offset).toList());
  final avgCost = best.value.map((c) => c.cost).reduce((x, y) => x + y) / best.value.length;
  final voteScore = math.min(1.0, best.value.length / 6);
  final spreadScore = (1 - spread / (options.bucketSeconds * 2)).clamp(0.0, 1.0);
  final costScore = (1 - avgCost / 0.06).clamp(0.0, 1.0);
  final confidence = (voteScore * 0.5 + spreadScore * 0.3 + costScore * 0.2).clamp(0.0, 1.0);

  return OffsetResult.ok(OffsetEstimate(
    offsetSeconds: bestOffset,
    confidence: confidence,
    pairs: best.value.length,
  ));
}

class _Candidate {
  const _Candidate({required this.offset, required this.cost});

  final double offset;
  final double cost;
}

double _bucketWeight(List<_Candidate> list) =>
    list.fold(0.0, (sum, c) => sum + (1 - c.cost / 0.065).clamp(0.0, 1.0));

/// 相邻帧灰度差的中位数：衡量这段画面"有没有在动"。
double _medianMotion(List<FrameSample> samples) {
  if (samples.length < 2) return 0;
  final diffs = <double>[];
  for (var i = 1; i < samples.length; i++) {
    diffs.add(FrameSignature.detailDistance(samples[i - 1].signature, samples[i].signature));
  }
  return _median(diffs);
}

double _median(List<double> values) {
  if (values.isEmpty) return 0;
  final sorted = List<double>.from(values)..sort();
  final mid = sorted.length >> 1;
  if (sorted.length.isOdd) return sorted[mid];
  return (sorted[mid - 1] + sorted[mid]) / 2;
}

double _spread(List<double> values) {
  if (values.length < 2) return 0;
  var min = values.first;
  var max = values.first;
  for (final v in values) {
    if (v < min) min = v;
    if (v > max) max = v;
  }
  return max - min;
}
