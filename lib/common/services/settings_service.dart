import 'dart:io';
import 'dart:convert';
import 'dart:developer';
import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/player/player_consts.dart';
import 'package:stop_watch_timer/stop_watch_timer.dart';
import 'package:flutter_exit_app/flutter_exit_app.dart';
import 'package:pure_live/common/consts/app_consts.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/modules/web_dav/webdav_config.dart';
import 'package:pure_live/common/services/bilibili_account_service.dart';

class SettingsService extends GetxController {
  final themeModeName = (HivePrefUtil.getString('themeMode') ?? "System").obs;
  final themeColorSwitch = (HivePrefUtil.getString('themeColorSwitch') ?? Colors.blue.hex).obs;
  final languageName = (HivePrefUtil.getString('language') ?? "简体中文").obs;
  final enableDynamicTheme = (HivePrefUtil.getBool('enableDynamicTheme') ?? false).obs;
  final autoRefreshTime = (HivePrefUtil.getInt('autoRefreshTime') ?? 3).obs;
  final autoShutDownTime = (HivePrefUtil.getInt('autoShutDownTime') ?? 120).obs;
  final enableDenseFavorites = (HivePrefUtil.getBool('enableDenseFavorites') ?? true).obs;
  final enableBackgroundPlay = (HivePrefUtil.getBool('enableBackgroundPlay') ?? false).obs;
  final enableStartUp = (HivePrefUtil.getBool('enableStartUp') ?? true).obs;
  final enableRotateScreenWithSystem = (HivePrefUtil.getBool('enableRotateScreenWithSystem') ?? false).obs;
  final enableScreenKeepOn = (HivePrefUtil.getBool('enableScreenKeepOn') ?? true).obs;
  final enableAutoCheckUpdate = (HivePrefUtil.getBool('enableAutoCheckUpdate') ?? true).obs;
  final enableFullScreenDefault = (HivePrefUtil.getBool('enableFullScreenDefault') ?? false).obs;
  final videoFitIndex = (HivePrefUtil.getInt('videoFitIndex') ?? 0).obs;
  final hideDanmaku = (HivePrefUtil.getBool('hideDanmaku') ?? false).obs;
  final danmakuTopArea = (HivePrefUtil.getDouble('danmakuTopArea') ?? 0.0).obs;
  final danmakuArea = (HivePrefUtil.getDouble('danmakuArea') ?? 1.0).obs;
  final danmakuBottomArea = (HivePrefUtil.getDouble('danmakuBottomArea') ?? 0.5).obs;
  final danmakuSpeed = (HivePrefUtil.getDouble('danmakuSpeed') ?? 8.0).obs;
  final danmakuFontSize = (HivePrefUtil.getDouble('danmakuFontSize') ?? 16.0).obs;
  final danmakuFontBorder = (HivePrefUtil.getDouble('danmakuFontBorder') ?? 4.0).obs;
  final danmakuOpacity = (HivePrefUtil.getDouble('danmakuOpacity') ?? 1.0).obs;
  final enableCodec = (HivePrefUtil.getBool('enableCodec') ?? true).obs;
  final playerCompatMode = (HivePrefUtil.getBool('playerCompatMode') ?? false).obs;
  final videoPlayerIndex = (HivePrefUtil.getInt('videoPlayerIndex') ?? 0).obs;
  final bilibiliCookie = (HivePrefUtil.getString('bilibiliCookie') ?? '').obs;
  final huyaCookie = (HivePrefUtil.getString('huyaCookie') ?? '').obs;
  final dontAskExit = (HivePrefUtil.getBool('dontAskExit') ?? false).obs;
  final exitChoose = (HivePrefUtil.getString('exitChoose') ?? '').obs;
  final douyinCookie = (HivePrefUtil.getString('douyinCookie') ?? '').obs;
  final volume = (HivePrefUtil.getDouble('volume') ?? 0.5).obs;
  final customPlayerOutput = (HivePrefUtil.getBool('customPlayerOutput') ?? false).obs;
  final videoOutputDriver = (HivePrefUtil.getString('videoOutputDriver') ?? "gpu").obs;
  final audioOutputDriver = (HivePrefUtil.getString('audioOutputDriver') ?? "auto").obs;
  final videoHardwareDecoder = (HivePrefUtil.getString('videoHardwareDecoder') ?? "auto").obs;
  final enableAutoShutDownTime = (HivePrefUtil.getBool('enableAutoShutDownTime') ?? false).obs;
  final preferResolution = (HivePrefUtil.getString('preferResolution') ?? PlayerConsts.resolutions[0]).obs;
  final preferPlatform = (HivePrefUtil.getString('preferPlatform') ?? AppConsts.platforms[0]).obs;
  final shieldList = ((HivePrefUtil.getStringList('shieldList') ?? [])).obs;
  final hotAreasList = ((HivePrefUtil.getStringList('hotAreasList') ?? AppConsts.supportSites)).obs;
  final favoriteRooms =
      ((HivePrefUtil.getStringList('favoriteRooms') ?? []).map((e) => LiveRoom.fromJson(jsonDecode(e))).toList()).obs;
  final historyRooms =
      ((HivePrefUtil.getStringList('historyRooms') ?? []).map((e) => LiveRoom.fromJson(jsonDecode(e))).toList()).obs;
  final favoriteAreas =
      ((HivePrefUtil.getStringList('favoriteAreas') ?? []).map((e) => LiveArea.fromJson(jsonDecode(e))).toList()).obs;
  final backupDirectory = (HivePrefUtil.getString('backupDirectory') ?? '').obs;
  final currentWebDavConfig = (HivePrefUtil.getString('currentWebDavConfig') ?? '').obs;
  final webDavConfigs =
      ((HivePrefUtil.getStringList('webDavConfigs') ?? []).map((e) => WebDAVConfig.fromJson(jsonDecode(e))).toList())
          .obs;
  final m3uDirectory = (HivePrefUtil.getString('m3uDirectory') ?? 'm3uDirectory').obs;

  final Map<ColorSwatch<Object>, String> colorsNameMap = AppConsts.themeColors.map(
    (key, value) => MapEntry(ColorTools.createPrimarySwatch(value), key),
  );

  final StopWatchTimer _stopWatchTimer = StopWatchTimer(mode: StopWatchMode.countDown);

  // ========== Getter / Setter ==========
  ThemeMode get themeMode => AppConsts.themeModes[themeModeName.value]!;
  Locale get language => AppConsts.languages[languageName.value]!;
  List<String> get resolutionsList => PlayerConsts.resolutions;
  List<BoxFit> get videofitArrary => PlayerConsts.videofitList;
  List<String> get playerlist => PlayerConsts.players;
  StopWatchTimer get stopWatchTimer => _stopWatchTimer;

  // ========== 数据迁移核心方法 ==========
  /// 迁移旧 SharedPreferences 数据到 Hive（仅首次执行）
  Future<void> migrateOldPrefsData() async {
    if (HivePrefUtil.getBool('_migrated_from_sp') == true) {
      return;
    }

    try {
      final allKeys = PrefUtil.prefs.getKeys();

      for (final key in allKeys) {
        final value = PrefUtil.prefs.get(key);
        if (value == null) continue;
        if (value is String) {
          await HivePrefUtil.setString(key, value);
        } else if (value is int) {
          await HivePrefUtil.setInt(key, value);
        } else if (value is bool) {
          await HivePrefUtil.setBool(key, value);
        } else if (value is double) {
          await HivePrefUtil.setDouble(key, value);
        } else if (value is List<String>) {
          await HivePrefUtil.setStringList(key, value);
        }
      }

      await HivePrefUtil.setBool('_migrated_from_sp', true);
      log('旧 SharedPreferences 数据迁移到 Hive 完成！', name: 'SettingsService');
    } catch (e) {
      log('数据迁移失败: $e', name: 'SettingsService');
    }
  }

  @override
  void onInit() {
    super.onInit();
    migrateOldPrefsData().then((_) {
      update(['migrate_complete']);
    });

    // ========== 响应式变量监听 ==========
    enableDynamicTheme.listen((bool value) async {
      await HivePrefUtil.setBool('enableDynamicTheme', value);
      update(['myapp']);
    });

    themeColorSwitch.listen((value) async {
      await HivePrefUtil.setString('themeColorSwitch', value);
    });

    enableDenseFavorites.listen((value) async {
      await HivePrefUtil.setBool('enableDenseFavorites', value);
    });

    autoRefreshTime.listen((value) async {
      await HivePrefUtil.setInt('autoRefreshTime', value);
    });

    debounce(autoShutDownTime, (callback) async {
      await HivePrefUtil.setInt('autoShutDownTime', autoShutDownTime.value);
      if (enableAutoShutDownTime.isTrue) {
        _stopWatchTimer.onStopTimer();
        _stopWatchTimer.setPresetMinuteTime(autoShutDownTime.value, add: false);
        _stopWatchTimer.onStartTimer();
      } else {
        _stopWatchTimer.onStopTimer();
      }
    }, time: 1.seconds);

    enableBackgroundPlay.listen((value) async {
      await HivePrefUtil.setBool('enableBackgroundPlay', value);
    });

    enableStartUp.listen((value) async {
      await HivePrefUtil.setBool('enableStartUp', value);
      if (value) {
        launchAtStartup.enable();
      } else {
        launchAtStartup.disable();
      }
    });

    enableRotateScreenWithSystem.listen((value) async {
      await HivePrefUtil.setBool('enableRotateScreenWithSystem', value);
    });

    enableScreenKeepOn.listen((value) async {
      await HivePrefUtil.setBool('enableScreenKeepOn', value);
    });

    debounce(enableAutoShutDownTime, (callback) async {
      await HivePrefUtil.setBool('enableAutoShutDownTime', enableAutoShutDownTime.value);
      if (enableAutoShutDownTime.value == true) {
        _stopWatchTimer.onStopTimer();
        _stopWatchTimer.setPresetMinuteTime(autoShutDownTime.value, add: false);
        _stopWatchTimer.onStartTimer();
      } else {
        _stopWatchTimer.onStopTimer();
      }
    }, time: 1.seconds);

    enableAutoCheckUpdate.listen((value) async {
      await HivePrefUtil.setBool('enableAutoCheckUpdate', value);
    });

    enableFullScreenDefault.listen((value) async {
      await HivePrefUtil.setBool('enableFullScreenDefault', value);
    });

    shieldList.listen((value) async {
      await HivePrefUtil.setStringList('shieldList', value);
    });

    hotAreasList.listen((value) async {
      await HivePrefUtil.setStringList('hotAreasList', value);
    });

    favoriteRooms.listen((rooms) async {
      await HivePrefUtil.setStringList('favoriteRooms', rooms.map<String>((e) => jsonEncode(e.toJson())).toList());
    });

    webDavConfigs.listen((configs) async {
      await HivePrefUtil.setStringList('webDavConfigs', configs.map<String>((e) => jsonEncode(e.toJson())).toList());
    });

    currentWebDavConfig.listen((config) async {
      await HivePrefUtil.setString('currentWebDavConfig', config);
    });

    favoriteAreas.listen((areas) async {
      await HivePrefUtil.setStringList('favoriteAreas', areas.map<String>((e) => jsonEncode(e.toJson())).toList());
    });

    historyRooms.listen((rooms) async {
      await HivePrefUtil.setStringList('historyRooms', rooms.map<String>((e) => jsonEncode(e.toJson())).toList());
    });

    backupDirectory.listen((String value) async {
      await HivePrefUtil.setString('backupDirectory', value);
    });

    // 初始化自动关机定时器
    onInitShutDown();

    // 自动关机监听
    _stopWatchTimer.fetchEnded.listen((value) {
      _stopWatchTimer.onStopTimer();
      FlutterExitApp.exitApp();
    });

    // 弹幕/播放器相关配置监听
    videoFitIndex.listen((value) async {
      await HivePrefUtil.setInt('videoFitIndex', value);
    });

    hideDanmaku.listen((value) async {
      await HivePrefUtil.setBool('hideDanmaku', value);
    });

    danmakuArea.listen((value) async {
      await HivePrefUtil.setDouble('danmakuArea', value);
    });

    danmakuTopArea.listen((value) async {
      await HivePrefUtil.setDouble('danmakuTopArea', value);
    });

    danmakuBottomArea.listen((value) async {
      await HivePrefUtil.setDouble('danmakuBottomArea', value);
    });

    danmakuSpeed.listen((value) async {
      await HivePrefUtil.setDouble('danmakuSpeed', value);
    });

    danmakuFontSize.listen((value) async {
      await HivePrefUtil.setDouble('danmakuFontSize', value);
    });

    danmakuFontBorder.listen((value) async {
      await HivePrefUtil.setDouble('danmakuFontBorder', value);
    });

    danmakuOpacity.listen((value) async {
      await HivePrefUtil.setDouble('danmakuOpacity', value);
    });

    enableCodec.listen((value) async {
      await HivePrefUtil.setBool('enableCodec', value);
    });

    playerCompatMode.listen((value) async {
      await HivePrefUtil.setBool('playerCompatMode', value);
    });

    videoPlayerIndex.listen((value) async {
      await HivePrefUtil.setInt('videoPlayerIndex', value);
    });

    bilibiliCookie.listen((value) async {
      await HivePrefUtil.setString('bilibiliCookie', value);
    });

    huyaCookie.listen((value) async {
      await HivePrefUtil.setString('huyaCookie', value);
    });

    dontAskExit.listen((value) async {
      await HivePrefUtil.setBool('dontAskExit', value);
    });

    exitChoose.listen((value) async {
      await HivePrefUtil.setString('exitChoose', value);
    });

    douyinCookie.listen((value) async {
      await HivePrefUtil.setString('douyinCookie', value);
    });

    volume.listen((value) async {
      await HivePrefUtil.setDouble('volume', value);
    });

    customPlayerOutput.listen((value) async {
      await HivePrefUtil.setBool('customPlayerOutput', value);
    });

    videoOutputDriver.listen((value) async {
      await HivePrefUtil.setString('videoOutputDriver', value);
    });

    audioOutputDriver.listen((value) async {
      await HivePrefUtil.setString('audioOutputDriver', value);
    });

    videoHardwareDecoder.listen((value) async {
      await HivePrefUtil.setString('videoHardwareDecoder', value);
    });
  }

  // ========== 公共方法（替换为 HivePrefUtil 异步写入） ==========
  void changeThemeMode(String mode) async {
    if (AppConsts.themeModes.containsKey(mode)) {
      themeModeName.value = mode;
      await HivePrefUtil.setString('themeMode', mode);
      Get.changeThemeMode(themeMode);
    }
  }

  void changeThemeColorSwitch(String hexColor) {
    var themeColor = HexColor(hexColor);
    var lightTheme = MyTheme(primaryColor: themeColor).lightThemeData;
    var darkTheme = MyTheme(primaryColor: themeColor).darkThemeData;
    Get.changeTheme(lightTheme);
    Get.changeTheme(darkTheme);
  }

  void onInitShutDown() {
    if (enableAutoShutDownTime.isTrue) {
      _stopWatchTimer.setPresetMinuteTime(autoShutDownTime.value, add: false);
      _stopWatchTimer.onStartTimer();
    }
  }

  void changeLanguage(String value) async {
    languageName.value = value;
    await HivePrefUtil.setString('language', value);
    Get.updateLocale(language);
  }

  void changePlayer(int value) async {
    videoPlayerIndex.value = value;
    await HivePrefUtil.setInt('videoPlayerIndex', value);
  }

  void changePreferResolution(String name) async {
    if (PlayerConsts.resolutions.indexWhere((e) => e == name) != -1) {
      preferResolution.value = name;
      await HivePrefUtil.setString('preferResolution', name);
    }
  }

  void changePreferPlatform(String name) async {
    if (AppConsts.platforms.indexWhere((e) => e == name) != -1) {
      preferPlatform.value = name;
      update(['myapp']);
      await HivePrefUtil.setString('preferPlatform', name);
    }
  }

  void changeShutDownConfig(int minutes, bool isAutoShutDown) async {
    autoShutDownTime.value = minutes;
    enableAutoShutDownTime.value = isAutoShutDown;
    await HivePrefUtil.setInt('autoShutDownTime', minutes);
    await HivePrefUtil.setBool('enableAutoShutDownTime', isAutoShutDown);
    onInitShutDown();
  }

  void changeAutoRefreshConfig(int minutes) async {
    autoRefreshTime.value = minutes;
    await HivePrefUtil.setInt('autoRefreshTime', minutes);
  }

  // ========== 业务方法（收藏、历史、屏蔽等）==========
  bool isFavorite(LiveRoom room) {
    return favoriteRooms.any((element) => element.roomId == room.roomId);
  }

  LiveRoom getLiveRoomByRoomId(String roomId, String platform) {
    if (!favoriteRooms.any((element) => element.roomId == roomId) &&
        !historyRooms.any((element) => element.roomId == roomId)) {
      return LiveRoom(roomId: roomId, platform: platform, liveStatus: LiveStatus.unknown);
    }
    return favoriteRooms.firstWhere(
      (element) => element.roomId == roomId && element.platform == platform,
      orElse: () => historyRooms.firstWhere((element) => element.roomId == roomId && element.platform == platform),
    );
  }

  bool addRoom(LiveRoom room) {
    if (favoriteRooms.any((element) => element.roomId == room.roomId)) {
      return false;
    }
    favoriteRooms.add(room);
    return true;
  }

  void addShieldList(String value) {
    shieldList.add(value);
  }

  void removeShieldList(int value) {
    shieldList.removeAt(value);
  }

  bool removeRoom(LiveRoom room) {
    if (!favoriteRooms.any((element) => element.roomId == room.roomId)) {
      return false;
    }
    favoriteRooms.remove(room);
    return true;
  }

  bool updateRoom(LiveRoom room) {
    int idx = favoriteRooms.indexWhere((element) => element.roomId == room.roomId);
    updateRoomInHistory(room);
    if (idx == -1) return false;
    favoriteRooms[idx] = room;
    return true;
  }

  void updateRooms(List<LiveRoom> rooms) {
    favoriteRooms.value = rooms;
  }

  bool updateRoomInHistory(LiveRoom room) {
    int idx = historyRooms.indexWhere((element) => element.roomId == room.roomId);
    if (idx == -1) return false;
    historyRooms[idx] = room;
    return true;
  }

  void addRoomToHistory(LiveRoom room) {
    if (historyRooms.any((element) => element.roomId == room.roomId)) {
      historyRooms.remove(room);
    }
    updateRoom(room);
    if (historyRooms.length > 50) {
      historyRooms.removeRange(0, historyRooms.length - 50);
    }
    historyRooms.insert(0, room);
  }

  bool isFavoriteArea(LiveArea area) {
    return favoriteAreas.any(
      (element) =>
          element.areaId == area.areaId && element.platform == area.platform && element.areaType == area.areaType,
    );
  }

  bool addArea(LiveArea area) {
    if (favoriteAreas.any(
      (element) =>
          element.areaId == area.areaId && element.platform == area.platform && element.areaType == area.areaType,
    )) {
      return false;
    }
    favoriteAreas.add(area);
    return true;
  }

  bool removeArea(LiveArea area) {
    if (!favoriteAreas.any(
      (element) =>
          element.areaId == area.areaId && element.platform == area.platform && element.areaType == area.areaType,
    )) {
      return false;
    }
    favoriteAreas.remove(area);
    return true;
  }

  // ========== WebDAV 相关 ==========
  bool addWebDavConfig(WebDAVConfig config) {
    if (webDavConfigs.any((element) => element.name == config.name)) {
      return false;
    }
    webDavConfigs.add(config);
    return true;
  }

  bool removeWebDavConfig(WebDAVConfig config) {
    if (!webDavConfigs.any((element) => element.name == config.name)) {
      return false;
    }
    webDavConfigs.remove(config);
    return true;
  }

  bool updateWebDavConfig(WebDAVConfig config) {
    int idx = webDavConfigs.indexWhere((element) => element.name == config.name);
    if (idx == -1) return false;
    webDavConfigs[idx] = config;
    return true;
  }

  void updateWebDavConfigs(List<WebDAVConfig> configs) {
    webDavConfigs.value = configs;
  }

  bool isWebDavConfigExist(String name) {
    return webDavConfigs.any((element) => element.name == name);
  }

  WebDAVConfig? getWebDavConfigByName(String name) {
    if (isWebDavConfigExist(name)) {
      return webDavConfigs.firstWhere((element) => element.name == name);
    } else {
      return null;
    }
  }

  // ========== 备份恢复 ==========
  bool backup(File file) {
    try {
      final json = toJson();
      file.writeAsStringSync(jsonEncode(json));
    } catch (e) {
      return false;
    }
    return true;
  }

  bool recover(File file) {
    try {
      final json = file.readAsStringSync();
      fromJson(jsonDecode(json));
    } catch (e) {
      return false;
    }
    return true;
  }

  void setBilibiliCookit(String cookie) {
    final BiliBiliAccountService biliAccountService = Get.find<BiliBiliAccountService>();
    if (biliAccountService.cookie.isEmpty || biliAccountService.uid == 0) {
      biliAccountService.resetCookie(cookie);
      biliAccountService.loadUserInfo();
    }
  }

  // ========== 序列化 ==========
  void fromJson(Map<String, dynamic> json) {
    favoriteRooms.value = json['favoriteRooms'] != null
        ? (json['favoriteRooms'] as List).map<LiveRoom>((e) => LiveRoom.fromJson(jsonDecode(e))).toList()
        : [];
    favoriteAreas.value = json['favoriteAreas'] != null
        ? (json['favoriteAreas'] as List).map<LiveArea>((e) => LiveArea.fromJson(jsonDecode(e))).toList()
        : [];
    webDavConfigs.value = json['webDavConfigs'] != null
        ? (json['webDavConfigs'] as List).map<WebDAVConfig>((e) => WebDAVConfig.fromJson(jsonDecode(e))).toList()
        : [];
    shieldList.value = json['shieldList'] != null ? (json['shieldList'] as List).map((e) => e.toString()).toList() : [];
    hotAreasList.value = json['hotAreasList'] != null
        ? (json['hotAreasList'] as List).map((e) => e.toString()).toList()
        : [];
    autoShutDownTime.value = json['autoShutDownTime'] ?? 120;
    currentWebDavConfig.value = json['currentWebDavConfig'] ?? '';
    autoRefreshTime.value = json['autoRefreshTime'] ?? 3;
    themeModeName.value = json['themeMode'] ?? "System";
    enableAutoShutDownTime.value = json['enableAutoShutDownTime'] ?? false;
    enableDynamicTheme.value = json['enableDynamicTheme'] ?? false;
    enableDenseFavorites.value = json['enableDenseFavorites'] ?? false;
    enableBackgroundPlay.value = json['enableBackgroundPlay'] ?? false;
    enableStartUp.value = json['enableStartUp'] ?? true;
    enableRotateScreenWithSystem.value = json['enableRotateScreenWithSystem'] ?? false;
    enableScreenKeepOn.value = json['enableScreenKeepOn'] ?? true;
    enableAutoCheckUpdate.value = json['enableAutoCheckUpdate'] ?? true;
    enableFullScreenDefault.value = json['enableFullScreenDefault'] ?? false;
    languageName.value = json['languageName'] ?? "简体中文";
    preferResolution.value = json['preferResolution'] ?? PlayerConsts.resolutions[0];
    preferPlatform.value = json['preferPlatform'] ?? AppConsts.platforms[0];
    videoFitIndex.value = json['videoFitIndex'] ?? 0;
    hideDanmaku.value = json['hideDanmaku'] ?? false;
    danmakuTopArea.value = json['danmakuTopArea'] != null
        ? double.parse(json['danmakuTopArea'].toString()) > 0.4
              ? 0.4
              : double.parse(json['danmakuTopArea'].toString())
        : 0.0;
    danmakuArea.value = json['danmakuArea'] != null
        ? double.parse(json['danmakuArea'].toString()) > 1.0
              ? 1.0
              : double.parse(json['danmakuArea'].toString())
        : 1.0;
    danmakuBottomArea.value = double.parse(json['danmakuBottomArea'].toString());
    danmakuSpeed.value = json['danmakuSpeed'] != null ? double.parse(json['danmakuSpeed'].toString()) : 8.0;
    danmakuFontSize.value = json['danmakuFontSize'] != null ? double.parse(json['danmakuFontSize'].toString()) : 16.0;
    danmakuFontBorder.value = json['danmakuFontBorder'] != null
        ? double.parse(json['danmakuFontBorder'].toString())
        : 4.0;
    danmakuOpacity.value = json['danmakuOpacity'] != null ? double.parse(json['danmakuOpacity'].toString()) : 1.0;
    videoPlayerIndex.value = json['videoPlayerIndex'] ?? 0;
    enableCodec.value = json['enableCodec'] ?? true;
    playerCompatMode.value = json['playerCompatMode'] ?? false;
    bilibiliCookie.value = json['bilibiliCookie'] ?? '';
    huyaCookie.value = json['huyaCookie'] ?? '';
    dontAskExit.value = json['dontAskExit'] ?? false;
    exitChoose.value = json['exitChoose'] ?? '';
    douyinCookie.value = json['douyinCookie'] ?? '';
    themeColorSwitch.value = json['themeColorSwitch'] ?? Colors.blue.hex;
    volume.value = json['volume'] ?? 0.5;
    customPlayerOutput.value = json['customPlayerOutput'] ?? false;
    videoOutputDriver.value = (json['videoOutputDriver'] == null || json['videoOutputDriver'] == "")
        ? 'gpu'
        : json['videoOutputDriver'];
    audioOutputDriver.value = (json['audioOutputDriver'] == null || json['audioOutputDriver'] == "")
        ? 'auto'
        : json['audioOutputDriver'];
    videoHardwareDecoder.value = (json['videoHardwareDecoder'] == null || json['videoHardwareDecoder'] == "")
        ? 'auto'
        : json['videoHardwareDecoder'];

    // 同步更新到 Hive（恢复备份时）
    changeThemeMode(themeModeName.value);
    changeThemeColorSwitch(themeColorSwitch.value);
    setBilibiliCookit(bilibiliCookie.value);
    changeLanguage(languageName.value);
    changePreferResolution(preferResolution.value);
    changePreferPlatform(preferPlatform.value);
    changeShutDownConfig(autoShutDownTime.value, enableAutoShutDownTime.value);
    changeAutoRefreshConfig(autoRefreshTime.value);

    if (enableStartUp.value) {
      launchAtStartup.enable();
    } else {
      launchAtStartup.disable();
    }
  }

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['favoriteRooms'] = favoriteRooms.map<String>((e) => jsonEncode(e.toJson())).toList();
    json['webDavConfigs'] = webDavConfigs.map<String>((e) => jsonEncode(e.toJson())).toList();
    json['favoriteAreas'] = favoriteAreas.map<String>((e) => jsonEncode(e.toJson())).toList();
    json['themeMode'] = themeModeName.value;
    json['currentWebDavConfig'] = currentWebDavConfig.value;
    json['autoRefreshTime'] = autoRefreshTime.value;
    json['autoShutDownTime'] = autoShutDownTime.value;
    json['enableAutoShutDownTime'] = enableAutoShutDownTime.value;

    json['enableDynamicTheme'] = enableDynamicTheme.value;
    json['enableDenseFavorites'] = enableDenseFavorites.value;
    json['enableBackgroundPlay'] = enableBackgroundPlay.value;
    json['enableStartUp'] = enableStartUp.value;
    json['enableRotateScreenWithSystem'] = enableRotateScreenWithSystem.value;
    json['enableScreenKeepOn'] = enableScreenKeepOn.value;
    json['enableAutoCheckUpdate'] = enableAutoCheckUpdate.value;
    json['enableFullScreenDefault'] = enableFullScreenDefault.value;
    json['preferResolution'] = preferResolution.value;
    json['preferPlatform'] = preferPlatform.value;
    json['languageName'] = languageName.value;

    json['videoFitIndex'] = videoFitIndex.value;
    json['hideDanmaku'] = hideDanmaku.value;
    json['danmakuTopArea'] = danmakuTopArea.value;
    json['danmakuArea'] = danmakuArea.value;
    json['danmakuBottomArea'] = danmakuBottomArea.value;
    json['danmakuSpeed'] = danmakuSpeed.value;
    json['danmakuFontSize'] = danmakuFontSize.value;
    json['danmakuFontBorder'] = danmakuFontBorder.value;
    json['danmakuOpacity'] = danmakuOpacity.value;
    json['videoPlayerIndex'] = videoPlayerIndex.value;
    json['enableCodec'] = enableCodec.value;
    json['playerCompatMode'] = playerCompatMode.value;
    json['bilibiliCookie'] = bilibiliCookie.value;
    json['huyaCookie'] = huyaCookie.value;
    json['dontAskExit'] = dontAskExit.value;
    json['exitChoose'] = exitChoose.value;
    json['douyinCookie'] = douyinCookie.value;
    json['shieldList'] = shieldList.map<String>((e) => e.toString()).toList();
    json['hotAreasList'] = hotAreasList.map<String>((e) => e.toString()).toList();
    json['themeColorSwitch'] = themeColorSwitch.value;
    json['volume'] = volume.value;
    json['customPlayerOutput'] = customPlayerOutput.value;
    json['videoOutputDriver'] = videoOutputDriver.value;
    json['audioOutputDriver'] = audioOutputDriver.value;
    json['videoHardwareDecoder'] = videoHardwareDecoder.value;
    return json;
  }

  @override
  void onClose() {
    _stopWatchTimer.dispose();
    super.onClose();
  }
}
