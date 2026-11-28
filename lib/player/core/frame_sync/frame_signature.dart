import 'dart:math' as math;
import 'dart:typed_data';

/// 画面指纹：把一帧画面归一化成 128×72 灰度，再做 4×3 分块 DCT 位哈希。
///
/// 用途：副音轨自动对齐时比对两路画面。算法思路参考开源项目
/// [Fy1Sync](https://github.com/Fy1ng/Fy1Sync)（GPL-3.0-or-later）的帧指纹方案——
/// 分块 pHash / DCT 低频符号是公开技术，这里按思路自行实现，未复制其源码。
///
/// 为什么分块而不是整帧哈希：整帧 pHash 对局部遮挡（摄像头小窗、贴图、比分条）
/// 极其敏感，只要一块区域不同整体距离就爆掉；分成 4×3 共 12 块后可以按块投票，
/// 少数块被挡住不影响判断。
class FrameSignature {
  FrameSignature._(this.hashes, this.detail);

  /// 仅测试用：直接拼装（模拟局部遮挡 / 手工构造指纹）。
  factory FrameSignature.fromParts(List<int?> hashes, Float64List detail) =>
      FrameSignature._(hashes, detail);

  /// 归一化后的画面尺寸（固定，所有指纹都在这个尺度上比较）。
  static const int width = 128;
  static const int height = 72;

  static const int gridX = 4;
  static const int gridY = 3;

  /// 每块 15 位（4×4 DCT 系数去掉 DC 后剩 15 个）。
  static const int bitsPerTile = 15;

  /// 12 个块的位哈希，按下标对应 (bx, by) 网格。
  final List<int?> hashes;

  /// 半分辨率灰度（已减去全图均值），用于精匹配。
  final Float64List detail;

  /// DCT 余弦表：cos(pi * (2x+1) * u / 16)，u/x ∈ [0,4)。
  static final List<List<double>> _cos = List.generate(
    4,
    (u) => List<double>.generate(8, (x) => math.cos(math.pi * (2 * x + 1) * u / 16)),
  );

  static int _popcount(int bits) {
    var count = 0;
    var v = bits;
    while (v != 0) {
      v &= v - 1;
      count++;
    }
    return count;
  }

  /// 把 BGRA 原始像素降采样成 128×72 灰度。
  ///
  /// [stride] 是每行字节数（可能大于 [srcWidth] * 4，硬件解码常见对齐填充）。
  /// 采样点取每个目标像素对应源区域的中心，单点采样即可：后面的 DCT 只取低频，
  /// 本身就有抗噪作用。
  static Uint8List grayFromBgra(
    Uint8List bytes, {
    required int srcWidth,
    required int srcHeight,
    required int stride,
  }) {
    final gray = Uint8List(width * height);
    if (srcWidth <= 0 || srcHeight <= 0 || stride <= 0) return gray;
    final xStep = srcWidth / width;
    final yStep = srcHeight / height;
    for (var ty = 0; ty < height; ty++) {
      final sy = ((ty + 0.5) * yStep).floor().clamp(0, srcHeight - 1);
      final rowBase = sy * stride;
      final outBase = ty * width;
      for (var tx = 0; tx < width; tx++) {
        final sx = ((tx + 0.5) * xStep).floor().clamp(0, srcWidth - 1);
        final i = rowBase + sx * 4;
        if (i + 2 >= bytes.length) continue;
        final b = bytes[i];
        final g = bytes[i + 1];
        final r = bytes[i + 2];
        // 整数近似的 Rec.601 亮度：0.299R + 0.587G + 0.114B
        gray[outBase + tx] = (r * 77 + g * 150 + b * 29) >> 8;
      }
    }
    return gray;
  }

  /// 从 128×72 灰度图算指纹。
  static FrameSignature fromGray(Uint8List gray) {
    assert(gray.length == width * height, 'gray must be ${width}x$height');

    // 半分辨率细节图（隔点取样），减掉均值以抵抗整体亮度/曝光差异。
    final detail = Float64List((width ~/ 2) * (height ~/ 2));
    var sum = 0.0;
    var count = 0;
    for (var y = 0; y < height; y += 2) {
      for (var x = 0; x < width; x += 2) {
        final v = gray[y * width + x].toDouble();
        detail[(y ~/ 2) * (width ~/ 2) + (x ~/ 2)] = v;
        sum += v;
        count++;
      }
    }
    final mean = count == 0 ? 0.0 : sum / count;
    for (var i = 0; i < detail.length; i++) {
      detail[i] -= mean;
    }

    final hashes = <int?>[];
    for (var by = 0; by < gridY; by++) {
      for (var bx = 0; bx < gridX; bx++) {
        hashes.add(_tileHash(gray, bx, by));
      }
    }
    return FrameSignature._(hashes, detail);
  }

  /// 单块 32×24 → 8×8（4×3 箱平均）→ 4×4 DCT → 中位数阈值 → 15 位。
  static int _tileHash(Uint8List gray, int bx, int by) {
    final tile = Float64List(64);
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        var s = 0.0;
        for (var yy = 0; yy < 3; yy++) {
          final sy = by * 24 + y * 3 + yy;
          final rowBase = sy * width;
          for (var xx = 0; xx < 4; xx++) {
            final sx = bx * 32 + x * 4 + xx;
            s += gray[rowBase + sx];
          }
        }
        tile[y * 8 + x] = s / 12;
      }
    }

    final coeffs = Float64List(bitsPerTile);
    var k = 0;
    for (var v = 0; v < 4; v++) {
      for (var u = 0; u < 4; u++) {
        if (u == 0 && v == 0) continue; // 跳过 DC：整体亮度已经减过均值
        var s = 0.0;
        for (var y = 0; y < 8; y++) {
          final cy = _cos[v][y];
          for (var x = 0; x < 8; x++) {
            s += tile[y * 8 + x] * _cos[u][x] * cy;
          }
        }
        coeffs[k++] = s;
      }
    }

    final sorted = List<double>.from(coeffs)..sort();
    final median = sorted[sorted.length ~/ 2];
    var bits = 0;
    for (var i = 0; i < coeffs.length; i++) {
      if (coeffs[i] > median) bits |= 1 << i;
    }
    return bits;
  }

  /// 粗距离：块位哈希的平均汉明距离（0=完全一致，1=完全相反）。
  static double coarseDistance(FrameSignature a, FrameSignature b) {
    var sum = 0;
    var count = 0;
    final n = math.min(a.hashes.length, b.hashes.length);
    for (var i = 0; i < n; i++) {
      final ha = a.hashes[i];
      final hb = b.hashes[i];
      if (ha == null || hb == null) continue;
      sum += _popcount(ha ^ hb);
      count += bitsPerTile;
    }
    return count == 0 ? double.infinity : sum / count;
  }

  /// 精距离：半分辨率灰度差（已归一化到 0~1）。
  static double detailDistance(FrameSignature a, FrameSignature b) {
    final n = math.min(a.detail.length, b.detail.length);
    if (n == 0) return double.infinity;
    var sum = 0.0;
    for (var i = 0; i < n; i++) {
      sum += (a.detail[i] - b.detail[i]).abs();
    }
    return sum / n / 255;
  }
}
