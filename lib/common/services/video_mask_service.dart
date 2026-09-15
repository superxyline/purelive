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

/// 一个直播间的遮罩状态：位置尺寸 + 是否显示。
///
/// 位置尺寸与显示开关分开保存，所以关闭遮罩不会丢掉调好的位置——
/// 再次打开时回到原来的位置，不必重新调整。
class VideoMaskState {
  const VideoMaskState({required this.rect, this.visible = true});

  final VideoMaskRect rect;
  final bool visible;

  VideoMaskState copyWith({VideoMaskRect? rect, bool? visible}) =>
      VideoMaskState(rect: rect ?? this.rect, visible: visible ?? this.visible);

  Map<String, dynamic> toJson() => {...rect.toJson(), 'on': visible};

  static VideoMaskState? fromJson(dynamic value) {
    final rect = VideoMaskRect.fromJson(value);
    if (rect == null) return null;
    // 旧数据没有 on 字段（那时只存可见的遮罩），缺失按显示处理
    final on = value is Map ? value['on'] : null;
    return VideoMaskState(rect: rect, visible: on == null ? true : on == true);
  }
}

/// 按直播间记忆的视频遮挡块（模糊框）。
///
/// 用户可在全屏/窗口画面上放一个模糊框遮挡固定位置的广告；位置与大小按
/// `platform|roomId` 分别保存，换直播间互不影响，再次点按钮即隐藏（位置
/// 保留，下次打开原样恢复）。
class VideoMaskService extends GetxService {
  static const String _storageKey = 'videoMasksV1';

  /// 新建遮挡块的默认位置与大小（画面中上部，避开底部控制栏）。
  static const VideoMaskRect defaultRect = VideoMaskRect(x: 0.32, y: 0.16, width: 0.36, height: 0.18);

  static VideoMaskService? _instance;
  static VideoMaskService get instance => _instance!;

  /// key（platform|roomId）→ 遮罩状态
  final RxMap<String, VideoMaskState> rxMasks = <String, VideoMaskState>{}.obs;

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

  static bool _isValidKey(String? platform, String? roomId) =>
      (platform ?? '').trim().isNotEmpty && (roomId ?? '').trim().isNotEmpty;

  /// 当前**实际显示**的遮罩矩形；隐藏或未设过时返回 null（渲染用）。
  VideoMaskRect? maskOf(String? platform, String? roomId) {
    if (!_isValidKey(platform, roomId)) return null;
    final state = rxMasks[roomKey(platform, roomId)];
    if (state == null || !state.visible) return null;
    return state.rect;
  }

  /// 该直播间当前是否显示着遮罩（按钮高亮用）。
  bool hasMask(String? platform, String? roomId) => maskOf(platform, roomId) != null;

  /// 该直播间是否有记录（含已隐藏的），用于判断"再次打开"要恢复位置还是用默认位置。
  bool hasStoredMask(String? platform, String? roomId) =>
      _isValidKey(platform, roomId) && rxMasks.containsKey(roomKey(platform, roomId));

  /// 新建或更新遮罩（拖拽/缩放时高频调用，写盘做了节流）。
  void setMask(String? platform, String? roomId, VideoMaskRect rect) {
    if (!_isValidKey(platform, roomId)) return;
    rxMasks[roomKey(platform, roomId)] = VideoMaskState(rect: rect.clamped());
    _scheduleSave();
  }

  /// 隐藏该直播间的遮罩：**保留位置尺寸**，下次打开原样恢复。
  void hideMask(String? platform, String? roomId) {
    if (!_isValidKey(platform, roomId)) return;
    final key = roomKey(platform, roomId);
    final state = rxMasks[key];
    if (state == null) return;
    rxMasks[key] = state.copyWith(visible: false);
    _scheduleSave();
  }

  /// 开关切换的纯逻辑：已有记录（哪怕当前隐藏）就沿用它的位置尺寸，
  /// 只有该直播间从未设过遮罩时才落到默认位置。
  static VideoMaskState toggled(VideoMaskState? current) => current == null
      ? const VideoMaskState(rect: defaultRect)
      : current.copyWith(visible: !current.visible);

  /// 开关该直播间的遮罩，返回切换后是否显示。
  bool toggleMask(String? platform, String? roomId) {
    if (!_isValidKey(platform, roomId)) return false;
    final key = roomKey(platform, roomId);
    final next = toggled(rxMasks[key]);
    rxMasks[key] = next;
    _scheduleSave();
    return next.visible;
  }

  void _load() {
    try {
      final raw = HivePrefUtil.getString(_storageKey);
      if (raw == null || raw.isEmpty) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      rxMasks.assignAll(_parseStates(map));
    } catch (_) {
      // 存量数据损坏时忽略，用户重新框选即可
    }
  }

  static Map<String, VideoMaskState> _parseStates(dynamic value) {
    if (value is! Map) return const {};
    final restored = <String, VideoMaskState>{};
    value.forEach((key, raw) {
      final state = VideoMaskState.fromJson(raw);
      if (state != null) restored[key.toString()] = state;
    });
    return restored;
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _save);
  }

  void _save() {
    try {
      HivePrefUtil.setString(
        _storageKey,
        jsonEncode(rxMasks.map((key, state) => MapEntry(key, state.toJson()))),
      );
    } catch (_) {}
  }

  Map<String, dynamic> toJson() =>
      rxMasks.map((key, state) => MapEntry(key, state.toJson()));

  void fromJson(dynamic value) {
    rxMasks.assignAll(_parseStates(value));
    _save();
  }
}
