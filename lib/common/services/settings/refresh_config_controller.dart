import 'package:rxdart/rxdart.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/services/medels/refresh_config_model.dart';

class RefreshConfigController extends GetxController {
  /// 收藏列表批量刷新的并发数。
  ///
  /// 旧默认值是 2，关注房间变多后冷启动要跑很多个串行批次，首页会长时间
  /// 停留在上一次的状态；提到 6 后同样的房间数只需约三分之一的时间。
  /// 太高会更容易触发平台风控，因此仍保留设置项供用户自行权衡。
  static const int defaultMaxConcurrentRefresh = 6;

  final RxBool autoRefreshFavorite = hiveBool('autoRefreshFavorite', false);
  final RxInt autoRefreshInterval = hiveInt('autoRefreshInterval', 30);
  final RxInt maxConcurrentRefresh = hiveInt('maxConcurrentRefresh', defaultMaxConcurrentRefresh);
  final RxBool autoRefreshThumbnails = hiveBool('autoRefreshThumbnails', false);
  final RxInt thumbnailRefreshInterval = hiveInt('thumbnailRefreshInterval', 30);

  /// 并发数默认值升级账本：只在用户没动过并发设置（还是旧的默认 2）时
  /// 帮他升到新默认，改动过的不碰。
  final RxInt concurrencyDefaultMigration = hiveInt('refreshConcurrencyMigration', 0);

  final _configStream = BehaviorSubject<RefreshConfig>();
  Stream<RefreshConfig> get configChanges => _configStream.stream;

  @override
  void onInit() {
    super.onInit();
    _migrateConcurrencyDefault();
    _emitConfig();
    everAll([
      autoRefreshFavorite,
      autoRefreshInterval,
      maxConcurrentRefresh,
      autoRefreshThumbnails,
      thumbnailRefreshInterval,
    ], (_) => _emitConfig());
  }

  void _migrateConcurrencyDefault() {
    if (concurrencyDefaultMigration.value >= 1) return;
    if (maxConcurrentRefresh.value == 2) {
      maxConcurrentRefresh.value = defaultMaxConcurrentRefresh;
    }
    concurrencyDefaultMigration.value = 1;
  }

  void _emitConfig() {
    _configStream.add(
      RefreshConfig(
        autoRefreshFavorite: autoRefreshFavorite.value,
        autoRefreshInterval: autoRefreshInterval.value,
        maxConcurrentRefresh: maxConcurrentRefresh.value,
        autoRefreshThumbnails: autoRefreshThumbnails.value,
        thumbnailRefreshInterval: thumbnailRefreshInterval.value,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'autoRefreshFavorite': autoRefreshFavorite.v,
      'autoRefreshInterval': autoRefreshInterval.v,
      'maxConcurrentRefresh': maxConcurrentRefresh.v,
      'autoRefreshThumbnails': autoRefreshThumbnails.v,
      'thumbnailRefreshInterval': thumbnailRefreshInterval.v,
    };
  }

  void fromJson(Map<String, dynamic> json) {
    autoRefreshFavorite.v = json['autoRefreshFavorite'] ?? false;
    autoRefreshInterval.v = json['autoRefreshInterval'] ?? 30;
    maxConcurrentRefresh.v = json['maxConcurrentRefresh'] ?? 2;
    autoRefreshThumbnails.v = json['autoRefreshThumbnails'] ?? false;
    thumbnailRefreshInterval.v = json['thumbnailRefreshInterval'] ?? 30;
  }

  @override
  void onClose() {
    _configStream.close();
    super.onClose();
  }

  static Map<String, dynamic> extractConfig(Map<String, dynamic>? rootConfig) {
    final refresh = rootConfig?['refresh'] as Map<String, dynamic>? ?? {};
    return {
      'autoRefreshFavorite': refresh['autoRefreshFavorite'] ?? false,
      'autoRefreshInterval': refresh['autoRefreshInterval'] ?? 30,
      'maxConcurrentRefresh': refresh['maxConcurrentRefresh'] ?? 2,
      'autoRefreshThumbnails': refresh['autoRefreshThumbnails'] ?? false,
      'thumbnailRefreshInterval': refresh['thumbnailRefreshInterval'] ?? 30,
    };
  }

  static Map<String, dynamic> mergeConfig(Map<String, dynamic> rootConfig, Map<String, dynamic> updateFields) {
    final refresh = Map<String, dynamic>.from(rootConfig['refresh'] ?? {});
    updateFields.forEach((k, v) => refresh[k] = v);
    rootConfig['refresh'] = refresh;
    return rootConfig;
  }
}
