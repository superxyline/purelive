import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/consts/app_consts.dart';
import 'package:pure_live/player/utils/player_consts.dart';

class PlayerSettingsController extends GetxController {
  final RxInt videoFitIndex = hiveInt('videoFitIndex', 0);
  final RxString videoPlayerKey = hiveString('videoPlayerKey', 'mpv');

  final RxString preferResolution = hiveString('preferResolution', PlayerConsts.resolutions.first);
  final RxString preferResolutionCellular = hiveString('preferResolutionCellular', PlayerConsts.resolutions.first);

  final RxBool enableCodec = hiveBool('enableCodec', true);
  final RxBool playerCompatMode = hiveBool('playerCompatMode', false);
  final RxBool customPlayerOutput = hiveBool('customPlayerOutput', false);
  final RxString videoOutputDriver = hiveString('videoOutputDriver', 'gpu');
  final RxString audioOutputDriver = hiveString('audioOutputDriver', 'auto');
  final RxString videoHardwareDecoder = hiveString('videoHardwareDecoder', 'auto');

  final RxBool floatPlay = hiveBool('floatPlay', false);
  final RxBool windowsPipAlwaysOnTop = hiveBool('windowsPipAlwaysOnTop', false);
  // 全局"纯音频模式"开关（参照 1.1.1）：开启后进入直播间即关闭画面仅播放声音；
  // 直播间内的耳机按钮仍可单独切换当前房间，切换结果不覆盖此全局开关。
  final RxBool audioOnly = hiveBool('audioOnly', false);
  final RxBool useHardStopOnExit = hiveBool('useHardStopOnExit', false);

  // ======================
  // 画质增强（仅 media_kit/mpv 内核生效）
  // ======================
  /// Anime4K 超分：off / efficiency（效率优先）/ quality（质量优先）
  final RxString superResolution = hiveString('superResolution', 'off');

  /// 直播缓冲大小（MB）：作用于 mpv demuxer-max-bytes，越大抗抖动越强、延迟越高
  final RxInt liveBufferSizeMB = hiveInt('liveBufferSizeMB', 64);
  static const int maxLiveBufferSizeMB = 512;

  /// 音量均衡（mpv af loudnorm）：解决不同直播间音量忽大忽小
  final RxBool enableVolumeNormalization = hiveBool('enableVolumeNormalization', false);

  /// B站编码偏好：HEVC(H.265) 优先——同清晰度省约一半带宽，需设备硬解支持；
  /// 线路列表会按偏好把对应编码的流排到前面，可用线路切换手动选择
  final RxBool preferHEVC = hiveBool('preferHEVC', false);

  /// CDN 测速：取流前对各 CDN 主机做 TCP 连接测速，线路按延迟自动排序
  final RxBool enableCdnSpeedTest = hiveBool('enableCdnSpeedTest', false);

  List<BoxFit> get videoFitArray => AppConsts().videoFitType.map((e) => e['attr'] as BoxFit).toList();

  void changePreferResolution(String resolution) {
    if (PlayerConsts.resolutions.contains(resolution)) {
      preferResolution.v = resolution;
    }
  }

  void changePreferResolutionCellular(String resolution) {
    if (PlayerConsts.resolutions.contains(resolution)) {
      preferResolutionCellular.v = resolution;
    }
  }

  void resetMpvPlayerSettings() {
    enableCodec.v = true;
    playerCompatMode.v = false;
    customPlayerOutput.v = false;
    videoOutputDriver.v = 'gpu';
    audioOutputDriver.v = 'auto';
    videoHardwareDecoder.v = 'auto';
    preferResolution.v = PlayerConsts.resolutions.first;
    preferResolutionCellular.v = PlayerConsts.resolutions.first;
    useHardStopOnExit.v = false;
    superResolution.v = 'off';
    liveBufferSizeMB.v = 64;
    enableVolumeNormalization.v = false;
    preferHEVC.v = false;
    enableCdnSpeedTest.v = false;
  }

  Map<String, dynamic> toJson() {
    return {
      'videoFitIndex': videoFitIndex.v,
      'videoPlayerKey': videoPlayerKey.v,
      'preferResolution': preferResolution.v,
      'preferResolutionCellular': preferResolutionCellular.v,
      'enableCodec': enableCodec.v,
      'playerCompatMode': playerCompatMode.v,
      'customPlayerOutput': customPlayerOutput.v,
      'videoOutputDriver': videoOutputDriver.v,
      'audioOutputDriver': audioOutputDriver.v,
      'videoHardwareDecoder': videoHardwareDecoder.v,
      'floatPlay': floatPlay.v,
      'windowsPipAlwaysOnTop': windowsPipAlwaysOnTop.v,
      'audioOnly': audioOnly.v,
      'useHardStopOnExit': useHardStopOnExit.v,
      'superResolution': superResolution.v,
      'liveBufferSizeMB': liveBufferSizeMB.v,
      'enableVolumeNormalization': enableVolumeNormalization.v,
      'preferHEVC': preferHEVC.v,
      'enableCdnSpeedTest': enableCdnSpeedTest.v,
    };
  }

  void fromJson(Map<String, dynamic> json) {
    videoFitIndex.v = json['videoFitIndex'] ?? 0;
    videoPlayerKey.v = json['videoPlayerKey'] ?? 'mpv';
    preferResolution.v = json['preferResolution'] ?? PlayerConsts.resolutions.first;
    preferResolutionCellular.v = json['preferResolutionCellular'] ?? PlayerConsts.resolutions.first;
    enableCodec.v = json['enableCodec'] ?? true;
    playerCompatMode.v = json['playerCompatMode'] ?? false;
    customPlayerOutput.v = json['customPlayerOutput'] ?? false;
    videoOutputDriver.v = json['videoOutputDriver'] ?? 'gpu';
    audioOutputDriver.v = json['audioOutputDriver'] ?? 'auto';
    videoHardwareDecoder.v = json['videoHardwareDecoder'] ?? 'auto';
    floatPlay.v = json['floatPlay'] ?? false;
    windowsPipAlwaysOnTop.v = json['windowsPipAlwaysOnTop'] ?? false;
    audioOnly.v = json['audioOnly'] ?? false;
    useHardStopOnExit.v = json['useHardStopOnExit'] ?? false;
    superResolution.v = json['superResolution'] ?? 'off';
    liveBufferSizeMB.v =
        (((json['liveBufferSizeMB'] as num?)?.toInt() ?? 64).clamp(8, maxLiveBufferSizeMB)).toInt();
    enableVolumeNormalization.v = json['enableVolumeNormalization'] ?? false;
    preferHEVC.v = json['preferHEVC'] ?? false;
    enableCdnSpeedTest.v = json['enableCdnSpeedTest'] ?? false;
  }

  static Map<String, dynamic> extractConfig(Map<String, dynamic>? rootConfig) {
    final player = rootConfig?['player'] as Map<String, dynamic>? ?? {};
    return {
      'videoFitIndex': player['videoFitIndex'] ?? 0,
      'videoPlayerKey': player['videoPlayerKey'] ?? 'mpv',
      'preferResolution': player['preferResolution'] ?? PlayerConsts.resolutions.first,
      'preferResolutionCellular': player['preferResolutionCellular'] ?? PlayerConsts.resolutions.first,
      'enableCodec': player['enableCodec'] ?? true,
      'playerCompatMode': player['playerCompatMode'] ?? false,
      'customPlayerOutput': player['customPlayerOutput'] ?? false,
      'videoOutputDriver': player['videoOutputDriver'] ?? 'gpu',
      'audioOutputDriver': player['audioOutputDriver'] ?? 'auto',
      'videoHardwareDecoder': player['videoHardwareDecoder'] ?? 'auto',
      'floatPlay': player['floatPlay'] ?? false,
      'windowsPipAlwaysOnTop': player['windowsPipAlwaysOnTop'] ?? false,
      'audioOnly': player['audioOnly'] ?? false,
      'useHardStopOnExit': player['useHardStopOnExit'] ?? false,
      'superResolution': player['superResolution'] ?? 'off',
      'liveBufferSizeMB': (((player['liveBufferSizeMB'] as num?)?.toInt() ?? 64).clamp(8, maxLiveBufferSizeMB)).toInt(),
      'enableVolumeNormalization': player['enableVolumeNormalization'] ?? false,
      'preferHEVC': player['preferHEVC'] ?? false,
      'enableCdnSpeedTest': player['enableCdnSpeedTest'] ?? false,
    };
  }

  static Map<String, dynamic> mergeConfig(Map<String, dynamic> rootConfig, Map<String, dynamic> updateFields) {
    final player = Map<String, dynamic>.from(rootConfig['player'] ?? {});
    updateFields.forEach((k, v) => player[k] = v);
    rootConfig['player'] = player;
    return rootConfig;
  }
}
