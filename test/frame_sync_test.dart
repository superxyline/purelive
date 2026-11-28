import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/player/core/frame_sync/frame_signature.dart';
import 'package:pure_live/player/core/frame_sync/offset_estimator.dart';

/// 合成一帧 128×72 灰度：静态渐变背景 + 随 [index] 移动的亮块。
/// 背景是静止的（真实直播里大部分画面元素也不动），亮块提供"画面在动"的信号。
Uint8List makeFrame(int index, {int noise = 0}) {
  final gray = Uint8List(FrameSignature.width * FrameSignature.height);
  final cx = 16 + index * 9;
  for (var y = 0; y < FrameSignature.height; y++) {
    for (var x = 0; x < FrameSignature.width; x++) {
      var v = ((x * 2 + y * 3) % 180) + 20;
      if ((x - cx).abs() < 14 && (y - 34).abs() < 11) v = 235;
      if (noise > 0) {
        // 确定性伪噪声：模拟两路编码差异，避免测试依赖随机数
        v += ((x * 31 + y * 17 + index * 13) % (noise * 2 + 1)) - noise;
      }
      gray[y * FrameSignature.width + x] = v.clamp(0, 255);
    }
  }
  return gray;
}

/// 从灰度图直接构造指纹（跳过 BGRA 降采样）。
FrameSignature sigOf(Uint8List gray) => FrameSignature.fromGray(gray);

/// 生成一路样本：内容帧从 [offsetFrames] 开始取。
List<FrameSample> makeSamples({
  int count = 10,
  double stepSeconds = 0.2,
  double startSeconds = 0,
  int contentOffset = 0,
  int noise = 0,
  bool staticOnly = false,
}) {
  return List.generate(count, (i) {
    final content = staticOnly ? 0 : i + contentOffset;
    return FrameSample(
      pts: startSeconds + i * stepSeconds,
      signature: sigOf(makeFrame(content, noise: noise)),
    );
  });
}

void main() {
  group('FrameSignature', () {
    test('相同画面的指纹距离为 0', () {
      final sig = sigOf(makeFrame(3));
      expect(FrameSignature.coarseDistance(sig, sig), 0);
      expect(FrameSignature.detailDistance(sig, sig), 0);
    });

    test('不同画面的距离明显大于同一画面', () {
      final a = sigOf(makeFrame(0));
      final b = sigOf(makeFrame(9));
      expect(FrameSignature.coarseDistance(a, b), greaterThan(0.05));
    });

    test('BGRA 降采样：尺寸固定、灰度值正确', () {
      // 2×1 像素：纯红 / 纯蓝
      final bytes = Uint8List.fromList([
        0, 0, 255, 255, // B,G,R,A -> 红
        255, 0, 0, 255, // 蓝
      ]);
      final gray = FrameSignature.grayFromBgra(bytes, srcWidth: 2, srcHeight: 1, stride: 8);
      expect(gray.length, FrameSignature.width * FrameSignature.height);
      // 左半部分接近红(76)，右半部分接近蓝(29)
      final left = gray[0];
      final right = gray[FrameSignature.width - 1];
      expect(left, greaterThan(right));
      expect(left, greaterThan(60));
      expect(right, lessThan(40));
    });
  });

  group('estimateOffset', () {
    test('B 路晚 2 秒时给出 -2 秒（A 领先）', () {
      final a = makeSamples(noise: 2);
      final b = makeSamples(startSeconds: 2.0, noise: 2);
      final result = estimateOffset(a, b);
      expect(result.isOk, isTrue, reason: '${result.reason}');
      expect(result.estimate!.offsetSeconds, closeTo(-2.0, 0.12));
      expect(result.estimate!.isTrusted, isTrue);
    });

    test('B 路早 1.4 秒时给出 +1.4 秒（B 领先）', () {
      final a = makeSamples(startSeconds: 1.4, noise: 2);
      final b = makeSamples(noise: 2);
      final result = estimateOffset(a, b);
      expect(result.isOk, isTrue, reason: '${result.reason}');
      expect(result.estimate!.offsetSeconds, closeTo(1.4, 0.12));
    });

    test('局部遮挡（摄像头小窗）仍能对齐', () {
      final a = makeSamples(noise: 2);
      // B 路：同样的内容晚 2 秒 + 左上角一块被摄像头小窗盖住
      final b = makeSamples(startSeconds: 2.0, noise: 3)
          .map((s) => FrameSample(
                pts: s.pts,
                signature: FrameSignatureWithPatch.apply(s.signature, maskRatio: 0.22),
              ))
          .toList();
      final result = estimateOffset(a, b);
      expect(result.isOk, isTrue, reason: '${result.reason}');
      expect(result.estimate!.offsetSeconds, closeTo(-2.0, 0.2));
    });

    test('静止画面被拒绝', () {
      final a = makeSamples(staticOnly: true);
      final b = makeSamples(staticOnly: true, startSeconds: 1.0);
      final result = estimateOffset(a, b);
      expect(result.isOk, isFalse);
      expect(result.reason, OffsetRejectReason.staticPicture);
    });

    test('完全不同的画面被拒绝', () {
      final a = makeSamples();
      // 反向渐变：结构完全不同
      final b = List.generate(10, (i) {
        final gray = Uint8List(FrameSignature.width * FrameSignature.height);
        for (var y = 0; y < FrameSignature.height; y++) {
          for (var x = 0; x < FrameSignature.width; x++) {
            gray[y * FrameSignature.width + x] = (255 - ((x + y + i * 5) % 200)).clamp(0, 255);
          }
        }
        return FrameSample(pts: i * 0.2, signature: sigOf(gray));
      });
      final result = estimateOffset(a, b);
      expect(result.isOk, isFalse);
      expect(result.reason, OffsetRejectReason.noMatch);
    });

    test('帧数不足被拒绝', () {
      final result = estimateOffset(makeSamples(count: 2), makeSamples(count: 2));
      expect(result.isOk, isFalse);
      expect(result.reason, OffsetRejectReason.notEnoughFrames);
    });
  });
}

/// 测试辅助：给指纹加局部遮挡（模拟主播的摄像头小窗 / 贴纸）。
class FrameSignatureWithPatch {
  static FrameSignature apply(FrameSignature base, {double maskRatio = 0.2}) {
    final detail = Float64List.fromList(base.detail);
    final width = (FrameSignature.width ~/ 2);
    final height = (FrameSignature.height ~/ 2);
    final maskW = (width * maskRatio).round();
    final maskH = (height * maskRatio).round();
    for (var y = 0; y < maskH; y++) {
      for (var x = 0; x < maskW; x++) {
        detail[y * width + x] = -60; // 明显比周围暗
      }
    }
    return FrameSignature.fromParts(base.hashes, detail);
  }
}
