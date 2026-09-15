import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/services/video_mask_service.dart';

void main() {
  group('VideoMaskRect', () {
    test('keeps the rect inside the frame', () {
      const rect = VideoMaskRect(x: 0.9, y: 0.95, width: 0.4, height: 0.3);
      final clamped = rect.clamped();
      expect(clamped.x, closeTo(0.6, 1e-9));
      expect(clamped.y, closeTo(0.7, 1e-9));
      expect(clamped.width, closeTo(0.4, 1e-9));
      expect(clamped.height, closeTo(0.3, 1e-9));
    });

    test('clamps negative offsets to the top-left corner', () {
      const rect = VideoMaskRect(x: -0.5, y: -0.2, width: 0.3, height: 0.2);
      final clamped = rect.clamped();
      expect(clamped.x, 0.0);
      expect(clamped.y, 0.0);
      expect(clamped.width, closeTo(0.3, 1e-9));
      expect(clamped.height, closeTo(0.2, 1e-9));
    });

    test('enforces a minimum size so the box stays grabbable', () {
      const rect = VideoMaskRect(x: 0.5, y: 0.5, width: 0.001, height: -1);
      final clamped = rect.clamped();
      expect(clamped.width, VideoMaskRect.minSize);
      expect(clamped.height, VideoMaskRect.minSize);
      // 放大到最小尺寸后仍不能越界
      expect(clamped.x + clamped.width <= 1.0, isTrue);
      expect(clamped.y + clamped.height <= 1.0, isTrue);
    });

    test('round-trips through json and tolerates broken entries', () {
      const rect = VideoMaskRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4);
      final restored = VideoMaskRect.fromJson(rect.toJson());
      expect(restored, rect);

      // 字段缺失/非数字的存量数据按无效处理，用户重新框选即可
      expect(VideoMaskRect.fromJson(<String, dynamic>{}), isNull);
      expect(VideoMaskRect.fromJson({'x': 'abc', 'y': 0, 'w': 1, 'h': 1}), isNull);
      expect(VideoMaskRect.fromJson(null), isNull);
      // 字符串数字（JSON 经其它路径转写后可能出现）仍可解析
      expect(
        VideoMaskRect.fromJson({'x': '0.25', 'y': '0.5', 'w': '0.3', 'h': '0.2'}),
        const VideoMaskRect(x: 0.25, y: 0.5, width: 0.3, height: 0.2),
      );
    });

    test('roomKey is case-insensitive on the platform and per room', () {
      expect(VideoMaskService.roomKey('Bilibili', '21452505'), 'bilibili|21452505');
      expect(
        VideoMaskService.roomKey('bilibili', '6'),
        isNot(VideoMaskService.roomKey('huya', '6')),
      );
    });
  });

  group('VideoMaskService.toggled', () {
    test('first time uses the default rect', () {
      final state = VideoMaskService.toggled(null);
      expect(state.visible, isTrue);
      expect(state.rect, VideoMaskService.defaultRect);
    });

    test('hiding keeps the rect so re-opening restores the adjusted position', () {
      const adjusted = VideoMaskRect(x: 0.7, y: 0.05, width: 0.2, height: 0.3);
      final shown = VideoMaskState(rect: adjusted);
      final hidden = VideoMaskService.toggled(shown);
      expect(hidden.visible, isFalse);
      expect(hidden.rect, adjusted);
      // 再次打开：位置尺寸必须还是调好的那份，不能回到默认值
      final reopened = VideoMaskService.toggled(hidden);
      expect(reopened.visible, isTrue);
      expect(reopened.rect, adjusted);
      expect(reopened.rect, isNot(VideoMaskService.defaultRect));
    });
  });

  group('VideoMaskState json', () {
    test('round-trips rect and visibility', () {
      const state = VideoMaskState(rect: VideoMaskRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4), visible: false);
      final restored = VideoMaskState.fromJson(state.toJson());
      expect(restored?.rect, state.rect);
      expect(restored?.visible, isFalse);
    });

    test('treats legacy entries without the on flag as visible', () {
      // 旧数据只存了 {x,y,w,h}（那时隐藏的遮罩会被直接删掉）
      final restored = VideoMaskState.fromJson({'x': 0.3, 'y': 0.2, 'w': 0.3, 'h': 0.2});
      expect(restored?.visible, isTrue);
      expect(restored?.rect, const VideoMaskRect(x: 0.3, y: 0.2, width: 0.3, height: 0.2));
      expect(VideoMaskState.fromJson({'x': 'abc'}), isNull);
    });
  });
}
