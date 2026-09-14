import 'dart:async';
import 'dart:convert';

import 'package:pure_live/get/get.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';

/// 视频遮挡块矩形。四个值都是相对视频区域的**比例**（0~1），
/// 因此全屏、窗口模式、不同分辨率下会落在同一相对位置。
class VideoMaskRect {
  const VideoMaskRect({required this.x, required this.y, required this.width, required this.height});

  final double x;
  final double y;
  final double width;
  final double height;

  VideoMaskRect copyWith({double? x, double? y, double? width, double? height}) => VideoMaskRect(
    x: x ?? this.x,
    y: y ?? this.y,
    width: width ?? this.width,
    height: height ?? this.height,
  );

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'w': width, 'h': height};

  static VideoMaskRect? fromJson(dynamic value) {
    if (value is! Map) return null;
    final x = _asDouble(value['x']);
    final y = _asDouble(value['y']);
    final w = _asDouble(value['w']);
    final h = _asDouble(value['h']);
    if (x == null || y == null || w == null || h == null) return null;
    return VideoMaskRect(x: x, y: y, width: w, height: h).clamped();
  }

  static double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  /// 最小边长（比例）：太小的框既看不出效果也难以按住手柄。
  static const double minSize = 0.06;

  /// 收进 [0,1] 且不小于最小边长，保证框始终落在画面内。
  VideoMaskRect clamped() {
    final w = width.clamp(minSize, 1.0).toDouble();
    final h = height.clamp(minSize, 1.0).toDouble();
    return VideoMaskRect(
      x: x.clamp(0.0, 1.0 - w).toDouble(),
      y: y.clamp(0.0, 1.0 - h).toDouble(),
      width: w,
      height: h,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VideoMaskRect &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);
}

/// 按直播间记忆的视频遮挡块（模糊框）。
///
/// 用户可在全屏/窗口画面上放一个模糊框遮挡固定位置的广告；位置与大小按
/// `platform|roomId` 分别保存，换直播间互不影响，再次点按钮即移除。
class VideoMaskService extends GetxService {
  static const String _storageKey = 'videoMasksV1';

  /// 新建遮挡块的默认位置与大小（画面中上部，避开底部控制栏）。
  static const VideoMaskRect defaultRect = VideoMaskRect(x: 0.32, y: 0.16, width: 0.36, height: 0.18);

  static VideoMaskService? _instance;
  static VideoMaskService get instance => _instance!;

  /// key（platform|roomId）→ 矩形
  final RxMap<String, VideoMaskRect> rxMasks = <String, VideoMaskRect>{}.obs;

  Timer? _saveTimer;

  @override
  void onInit() {
    super.onInit();
    _instance = this;
    _load();
  }

  @override
  void onClose() {
    _saveTimer?.cancel();
    _saveTimer = null;
    _save();
    super.onClose();
  }

  static String roomKey(String? platform, String? roomId) =>
      '${platform?.trim().toLowerCase() ?? ''}|${roomId?.trim() ?? ''}';

  VideoMaskRect? maskOf(String? platform, String? roomId) {
    if ((platform ?? '').trim().isEmpty || (roomId ?? '').trim().isEmpty) return null;
    return rxMasks[roomKey(platform, roomId)];
  }

  /// 该直播间是否已有遮挡块。
  bool hasMask(String? platform, String? roomId) => maskOf(platform, roomId) != null;

  /// 新建或更新遮挡块（拖拽/缩放时高频调用，写盘做了节流）。
  void setMask(String? platform, String? roomId, VideoMaskRect rect) {
    if ((platform ?? '').trim().isEmpty || (roomId ?? '').trim().isEmpty) return;
    rxMasks[roomKey(platform, roomId)] = rect.clamped();
    _scheduleSave();
  }

  /// 移除该直播间的遮挡块。
  void removeMask(String? platform, String? roomId) {
    if ((platform ?? '').trim().isEmpty || (roomId ?? '').trim().isEmpty) return;
    rxMasks.remove(roomKey(platform, roomId));
    _scheduleSave();
  }

  /// 开关该直播间的遮挡块，返回切换后是否存在。
  bool toggleMask(String? platform, String? roomId) {
    if (hasMask(platform, roomId)) {
      removeMask(platform, roomId);
      return false;
    }
    setMask(platform, roomId, defaultRect);
    return true;
  }

  void _load() {
    try {
      final raw = HivePrefUtil.getString(_storageKey);
      if (raw == null || raw.isEmpty) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final loaded = <String, VideoMaskRect>{};
      map.forEach((key, value) {
        final rect = VideoMaskRect.fromJson(value);
        if (rect != null) loaded[key] = rect;
      });
      rxMasks.assignAll(loaded);
    } catch (_) {
      // 存量数据损坏时忽略，用户重新框选即可
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _save);
  }

  void _save() {
    try {
      HivePrefUtil.setString(
        _storageKey,
        jsonEncode(rxMasks.map((key, rect) => MapEntry(key, rect.toJson()))),
      );
    } catch (_) {}
  }

  Map<String, dynamic> toJson() =>
      rxMasks.map((key, rect) => MapEntry(key, rect.toJson()));

  void fromJson(dynamic value) {
    if (value is! Map) return;
    final restored = <String, VideoMaskRect>{};
    value.forEach((key, raw) {
      final rect = VideoMaskRect.fromJson(raw);
      if (rect != null) restored[key.toString()] = rect;
    });
    rxMasks.assignAll(restored);
    _save();
  }
}
