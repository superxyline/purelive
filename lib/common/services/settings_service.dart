import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:stop_watch_timer/stop_watch_timer.dart';
import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';
import 'package:flutter_exit_app/flutter_exit_app.dart';

class SettingsService extends GetxController {
  SettingsService() {
    enableDynamicTheme.listen((bool value) {
      PrefUtil.setBool('enableDynamicTheme', value);
      update(['myapp']);
    });

    enableDenseFavorites.listen((value) {
      PrefUtil.setBool('enableDenseFavorites', value);
    });
    autoRefreshTime.listen((value) {
      PrefUtil.setInt('autoRefreshTime', value);
    });
    debounce(autoShutDownTime, (callback) {
      PrefUtil.setInt('autoShutDownTime', autoShutDownTime.value);
      if (enableAutoShutDownTime.isTrue) {
        _stopWatchTimer.onStopTimer();
        _stopWatchTimer.setPresetMinuteTime(autoShutDownTime.value, add: false);
        _stopWatchTimer.onStartTimer();
      } else {
        _stopWatchTimer.onStopTimer();
      }
    }, time: 1.seconds);
    enableBackgroundPlay.listen((value) {
      PrefUtil.setBool('enableBackgroundPlay', value);
    });
    enableScreenKeepOn.listen((value) {
      PrefUtil.setBool('enableScreenKeepOn', value);
    });
    debounce(enableAutoShutDownTime, (callback) {
      PrefUtil.setBool('enableAutoShutDownTime', enableAutoShutDownTime.value);
      if (enableAutoShutDownTime.value == true) {
        _stopWatchTimer.onStopTimer();
        _stopWatchTimer.setPresetMinuteTime(autoShutDownTime.value, add: false);
        _stopWatchTimer.onStartTimer();
      } else {
        _stopWatchTimer.onStopTimer();
      }
    }, time: 1.seconds);
    enableAutoCheckUpdate.listen((value) {
      PrefUtil.setBool('enableAutoCheckUpdate', value);
    });
    enableFullScreenDefault.listen((value) {
      PrefUtil.setBool('enableFullScreenDefault', value);
    });

    favoriteRooms.listen((rooms) {
      PrefUtil.setStringList('favoriteRooms',
          favoriteRooms.map<String>((e) => jsonEncode(e.toJson())).toList());
    });
    favoriteAreas.listen((rooms) {
      PrefUtil.setStringList('favoriteAreas',
          favoriteAreas.map<String>((e) => jsonEncode(e.toJson())).toList());
    });

    historyRooms.listen((rooms) {
      PrefUtil.setStringList('historyRooms',
          historyRooms.map<String>((e) => jsonEncode(e.toJson())).toList());
    });

    backupDirectory.listen((String value) {
      backupDirectory.value = value;
      PrefUtil.setString('backupDirectory', value);
    });
    onInitShutDown();
    _stopWatchTimer.fetchEnded.listen((value) {
      _stopWatchTimer.onStopTimer();
      FlutterExitApp.exitApp();
    });
  }

  // Theme settings
  static Map<String, ThemeMode> themeModes = {
    "System": ThemeMode.system,
    "Dark": ThemeMode.dark,
    "Light": ThemeMode.light,
  };
  final themeModeName = (PrefUtil.getString('themeMode') ?? "System").obs;

  get themeMode => SettingsService.themeModes[themeModeName.value]!;

  void changeThemeMode(String mode) {
    themeModeName.value = mode;
    PrefUtil.setString('themeMode', mode);
    Get.changeThemeMode(themeMode);
  }

  void onInitShutDown() {
    if (enableAutoShutDownTime.isTrue) {
      _stopWatchTimer.setPresetMinuteTime(autoShutDownTime.value, add: false);
      _stopWatchTimer.onStartTimer();
    }
  }

  static Map<String, Color> themeColors = {
    "Crimson": const Color.fromARGB(255, 220, 20, 60),
    "Orange": Colors.orange,
    "Chrome": const Color.fromARGB(255, 230, 184, 0),
    "Grass": Colors.lightGreen,
    "Teal": Colors.teal,
    "SeaFoam": const Color.fromARGB(255, 112, 193, 207),
    "Ice": const Color.fromARGB(255, 115, 155, 208),
    "Blue": Colors.blue,
    "Indigo": Colors.indigo,
    "Violet": Colors.deepPurple,
    "Orchid": const Color.fromARGB(255, 218, 112, 214),
  };
  final themeColorName = (PrefUtil.getString('themeColor') ?? "Blue").obs;

  final StopWatchTimer _stopWatchTimer =
      StopWatchTimer(mode: StopWatchMode.countDown); // Create instance.

  get themeColor => SettingsService.themeColors[themeColorName.value]!;

  StopWatchTimer get stopWatchTimer => _stopWatchTimer;

  void changeThemeColor(String color) {
    themeColorName.value = color;
    PrefUtil.setString('themeColor', color);
  }

  static Map<String, Locale> languages = {
    "English": const Locale.fromSubtags(languageCode: 'en'),
    "简体中文": const Locale.fromSubtags(languageCode: 'zh', countryCode: 'CN'),
  };
  final languageName = (PrefUtil.getString('language') ?? "简体中文").obs;

  get language => SettingsService.languages[languageName.value]!;

  void changeLanguage(String value) {
    languageName.value = value;
    PrefUtil.setString('language', value);
    Get.updateLocale(language);
  }

  final enableDynamicTheme =
      (PrefUtil.getBool('enableDynamicTheme') ?? false).obs;

  // Custom settings
  final autoRefreshTime = (PrefUtil.getInt('autoRefreshTime') ?? 60).obs;

  final autoShutDownTime = (PrefUtil.getInt('autoShutDownTime') ?? 120).obs;

  final enableDenseFavorites =
      (PrefUtil.getBool('enableDenseFavorites') ?? false).obs;

  final enableBackgroundPlay =
      (PrefUtil.getBool('enableBackgroundPlay') ?? false).obs;

  final enableScreenKeepOn =
      (PrefUtil.getBool('enableScreenKeepOn') ?? false).obs;

  final enableAutoCheckUpdate =
      (PrefUtil.getBool('enableAutoCheckUpdate') ?? true).obs;

  final enableFullScreenDefault =
      (PrefUtil.getBool('enableFullScreenDefault') ?? false).obs;

  final enableAutoShutDownTime =
      (PrefUtil.getBool('enableAutoShutDownTime') ?? false).obs;

  static const List<String> resolutions = ['原画', '蓝光8M', '蓝光4M', '超清', '流畅'];

  final preferResolution =
      (PrefUtil.getString('preferResolution') ?? resolutions[0]).obs;

  void changePreferResolution(String name) {
    if (resolutions.indexWhere((e) => e == name) != -1) {
      preferResolution.value = name;
      PrefUtil.setString('preferResolution', name);
    }
  }

  void changeShutDownConfig(int minutes, bool isAutoShutDown) {
    autoShutDownTime.value = minutes;
    enableAutoShutDownTime.value = isAutoShutDown;
    PrefUtil.setInt('autoShutDownTime', minutes);
    PrefUtil.setBool('enableAutoShutDownTime', isAutoShutDown);
    onInitShutDown();
  }

  void changeAutoRefreshConfig(int seconds) {
    autoRefreshTime.value = seconds;
    PrefUtil.setInt('autoRefreshTime', seconds);
  }

  static const List<String> platforms = ['bilibili', 'douyu', 'huya'];

  final preferPlatform =
      (PrefUtil.getString('preferPlatform') ?? platforms[0]).obs;

  void changePreferPlatform(String name) {
    if (platforms.indexWhere((e) => e == name) != -1) {
      preferPlatform.value = name;
      update(['myapp']);
      PrefUtil.setString('preferPlatform', name);
    }
  }

  // Favorite rooms storage
  final favoriteRooms = ((PrefUtil.getStringList('favoriteRooms') ?? [])
          .map((e) => LiveRoom.fromJson(jsonDecode(e)))
          .toList())
      .obs;

  final historyRooms = ((PrefUtil.getStringList('historyRooms') ?? [])
          .map((e) => LiveRoom.fromJson(jsonDecode(e)))
          .toList())
      .obs;

  bool isFavorite(LiveRoom room) {
    return favoriteRooms.contains(room);
  }

  bool addRoom(LiveRoom room) {
    if (favoriteRooms.contains(room)) return false;
    favoriteRooms.add(room);
    return true;
  }

  bool removeRoom(LiveRoom room) {
    if (!favoriteRooms.contains(room)) return false;
    favoriteRooms.remove(room);
    return true;
  }

  bool updateRoom(LiveRoom room) {
    int idx = favoriteRooms.indexOf(room);
    if (idx == -1) return false;
    favoriteRooms[idx] = room;
    return true;
  }

  bool updateRoomInHistory(LiveRoom room) {
    int idx = historyRooms.indexOf(room);
    if (idx == -1) return false;
    historyRooms[idx] = room;
    return true;
  }

  void addRoomToHistory(LiveRoom room) {
    if (historyRooms.contains(room)) {
      historyRooms.remove(room);
    }
    //默认只记录20条，够用了
    if (historyRooms.length > 19) {
      historyRooms.removeRange(0, historyRooms.length - 19);
    }
    historyRooms.add(room);
  }

  // Favorite areas storage
  final favoriteAreas = ((PrefUtil.getStringList('favoriteAreas') ?? [])
          .map((e) => LiveArea.fromJson(jsonDecode(e)))
          .toList())
      .obs;

  bool isFavoriteArea(LiveArea area) {
    return favoriteAreas.contains(area);
  }

  bool addArea(LiveArea area) {
    if (favoriteAreas.contains(area)) return false;
    favoriteAreas.add(area);
    return true;
  }

  bool removeArea(LiveArea area) {
    if (!favoriteAreas.contains(area)) return false;
    favoriteAreas.remove(area);
    return true;
  }

  // Backup & recover storage
  final backupDirectory = (PrefUtil.getString('backupDirectory') ?? '').obs;

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

  void fromJson(Map<String, dynamic> json) {
    favoriteRooms.value = (json['favoriteRooms'] as List)
        .map<LiveRoom>((e) => LiveRoom.fromJson(jsonDecode(e)))
        .toList();
    favoriteAreas.value = (json['favoriteAreas'] as List)
        .map<LiveArea>((e) => LiveArea.fromJson(jsonDecode(e)))
        .toList();

    changeThemeMode(json['themeMode'] ?? "System");
    changeThemeColor(json['themeColor'] ?? "Crimson");
    autoShutDownTime.value = json['autoShutDownTime'] ?? 120;
    autoRefreshTime.value = json['autoRefreshTime'] ?? 60;

    enableAutoShutDownTime.value = json['enableAutoShutDownTime'] ?? false;
    enableDynamicTheme.value = json['enableDynamicTheme'] ?? false;
    enableDenseFavorites.value = json['enableDenseFavorites'] ?? false;
    enableBackgroundPlay.value = json['enableBackgroundPlay'] ?? false;
    enableScreenKeepOn.value = json['enableScreenKeepOn'] ?? false;
    enableAutoCheckUpdate.value = json['enableAutoCheckUpdate'] ?? true;
    enableFullScreenDefault.value = json['enableFullScreenDefault'] ?? false;
    languageName.value = json['languageName'] ?? "简体中文";
    preferResolution.value = json['preferResolution'] ?? resolutions[0];
    preferPlatform.value = json['preferPlatform'] ?? platforms[0];
    changeLanguage(languageName.value);
    changePreferResolution(preferResolution.value);
    changePreferPlatform(preferPlatform.value);
    changeShutDownConfig(autoShutDownTime.value, enableAutoShutDownTime.value);
    changeAutoRefreshConfig(autoRefreshTime.value);
  }

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['favoriteRooms'] =
        favoriteRooms.map<String>((e) => jsonEncode(e.toJson())).toList();
    json['favoriteAreas'] =
        favoriteAreas.map<String>((e) => jsonEncode(e.toJson())).toList();
    json['themeMode'] = themeModeName.value;
    json['themeColor'] = themeColorName.value;

    json['autoRefreshTime'] = autoRefreshTime.value;
    json['autoShutDownTime'] = autoShutDownTime.value;
    json['enableAutoShutDownTime'] = enableAutoShutDownTime.value;

    json['enableDynamicTheme'] = enableDynamicTheme.value;
    json['enableDenseFavorites'] = enableDenseFavorites.value;
    json['enableBackgroundPlay'] = enableBackgroundPlay.value;
    json['enableScreenKeepOn'] = enableScreenKeepOn.value;
    json['enableAutoCheckUpdate'] = enableAutoCheckUpdate.value;
    json['enableFullScreenDefault'] = enableFullScreenDefault.value;
    json['preferResolution'] = preferResolution.value;
    json['preferPlatform'] = preferPlatform.value;
    json['languageName'] = languageName.value;
    return json;
  }

  defaultConfig() {
    Map<String, dynamic> json = {
      "favoriteRooms": [],
      "favoriteAreas": [],
      "themeMode": "Dark",
      "themeColor": "Chrome",
      "enableDynamicTheme": false,
      "autoShutDownTime": 120,
      "autoRefreshTime": 60,
      "languageName": languageName.value,
      "enableAutoShutDownTime": false,
      "enableDenseFavorites": false,
      "enableBackgroundPlay": false,
      "enableScreenKeepOn": true,
      "enableAutoCheckUpdate": false,
      "enableFullScreenDefault": false,
      "preferResolution": "原画",
      "preferPlatform": "bilibili"
    };
    return json;
  }
}
