import 'package:pure_live/common/index.dart';

/// TV 模式专属设置（Hive 持久化）。
/// 只存 TV 独有的项；弹幕/播放内核等与手机端共用同一批设置键。
class TvSettings {
  TvSettings._();

  /// 主页网格列数（4/5/6）
  static final RxInt gridColumns = hiveInt('tvGridColumns', 4);
}
