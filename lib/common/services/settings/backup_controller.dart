import 'dart:io';
import 'dart:convert';
import 'package:get/get.dart';
import 'package:pure_live/common/services/utils/hive_rx.dart';
import 'package:pure_live/modules/tags/tag_management_controller.dart';
import 'package:pure_live/common/services/settings/web_dav_controller.dart';

import 'package:pure_live/common/services/settings/startup_controller.dart';
import 'package:pure_live/common/services/settings/app_settings_controller.dart';
import 'package:pure_live/common/services/settings/favorite_room_controller.dart';
import 'package:pure_live/common/services/settings/font_settings_controller.dart';
import 'package:pure_live/common/services/settings/exit_settings_controller.dart';
import 'package:pure_live/common/services/settings/page_settings_controller.dart';
import 'package:pure_live/common/services/settings/refresh_config_controller.dart';
import 'package:pure_live/common/services/settings/theme_settings_controller.dart';
import 'package:pure_live/common/services/settings/proxy_settings_controller.dart';
import 'package:pure_live/common/services/settings/player_settings_controller.dart';
import 'package:pure_live/common/services/settings/volume_settings_controller.dart';
import 'package:pure_live/common/services/settings/cookie_settings_controller.dart';
import 'package:pure_live/common/services/settings/danmaku_settings_controller.dart';

class BackupController extends GetxController {
  static BackupController get to => Get.find();

  static const int backupVersion = 2;

  final RxString backupDirectory = hiveString('backupDirectory', '');

  Map<String, dynamic> exportAllSettings() {
    if (!Get.isRegistered<TagManagementController>()) {
      Get.put(TagManagementController());
    }

    return {
      'backupVersion': backupVersion,
      'app': Get.find<AppSettingsController>().toJson(),
      'theme': Get.find<ThemeSettingsController>().toJson(),
      'font': Get.find<FontSettingsController>().toJson(),
      'player': Get.find<PlayerSettingsController>().toJson(),
      'danmaku': Get.find<DanmakuSettingsController>().toJson(),
      'volume': Get.find<VolumeSettingsController>().toJson(),
      'favorite': Get.find<FavoriteRoomController>().toJson(),

      'webdav': Get.find<WebDavController>().toJson(),
      'cookie': Get.find<CookieSettingsController>().toJson(),
      'proxy': Get.find<ProxySettingsController>().toJson(),
      'exit': Get.find<ExitSettingsController>().toJson(),
      'startup': Get.find<StartupController>().toJson(),
      'tags': Get.find<TagManagementController>().exportToJson(),
      'refresh': Get.find<RefreshConfigController>().toJson(),
      'page': Get.find<PageSettingsController>().toJson(),
    };
  }

  void importAllSettings(Map<String, dynamic> data) {
    final version = data['backupVersion'];

    if (version == null) {
      _importLegacy(data);
      return;
    }

    switch (version) {
      case 2:
        _importV2(data);
        break;

      default:
        _importLatestCompatible(data);
        break;
    }
  }

  void _importLatestCompatible(Map<String, dynamic> data) {
    _importV2(data);
  }

  void _importV2(Map<String, dynamic> data) {
    Get.find<AppSettingsController>().fromJson(Map<String, dynamic>.from(data['app'] ?? {}));

    Get.find<ThemeSettingsController>().fromJson(Map<String, dynamic>.from(data['theme'] ?? {}));

    Get.find<FontSettingsController>().fromJson(Map<String, dynamic>.from(data['font'] ?? {}));

    Get.find<PlayerSettingsController>().fromJson(Map<String, dynamic>.from(data['player'] ?? {}));

    Get.find<DanmakuSettingsController>().fromJson(Map<String, dynamic>.from(data['danmaku'] ?? {}));

    Get.find<VolumeSettingsController>().fromJson(Map<String, dynamic>.from(data['volume'] ?? {}));

    Get.find<FavoriteRoomController>().fromJson(Map<String, dynamic>.from(data['favorite'] ?? {}));

    Get.find<CookieSettingsController>().fromJson(Map<String, dynamic>.from(data['cookie'] ?? {}));

    Get.find<ProxySettingsController>().fromJson(Map<String, dynamic>.from(data['proxy'] ?? {}));

    Get.find<ExitSettingsController>().fromJson(Map<String, dynamic>.from(data['exit'] ?? {}));

    Get.find<StartupController>().fromJson(Map<String, dynamic>.from(data['startup'] ?? {}));

    Get.find<RefreshConfigController>().fromJson(Map<String, dynamic>.from(data['refresh'] ?? {}));

    Get.find<PageSettingsController>().fromJson(Map<String, dynamic>.from(data['page'] ?? {}));

    if (!Get.isRegistered<TagManagementController>()) {
      Get.put(TagManagementController());
    }

    final tagsData = data['tags'];
    if (tagsData is Map) {
      Get.find<TagManagementController>().importFromJson(Map<String, dynamic>.from(tagsData));
    }
  }

  void _importLegacy(Map<String, dynamic> data) {
    Get.find<AppSettingsController>().fromJson(data);
    Get.find<ThemeSettingsController>().fromJson(data);
    Get.find<FontSettingsController>().fromJson(data);
    Get.find<PlayerSettingsController>().fromJson(data);
    Get.find<DanmakuSettingsController>().fromJson(data);
    Get.find<VolumeSettingsController>().fromJson(data);
    Get.find<FavoriteRoomController>().fromJson(data);

    Get.find<CookieSettingsController>().fromJson(data);
    Get.find<ProxySettingsController>().fromJson(data);
    Get.find<ExitSettingsController>().fromJson(data);
    Get.find<StartupController>().fromJson(data);
    Get.find<RefreshConfigController>().fromJson(data);
    Get.find<PageSettingsController>().fromJson(data);
    if (!Get.isRegistered<TagManagementController>()) {
      Get.put(TagManagementController());
    }

    final legacyTags = data['custom_tags_data'];
    if (legacyTags is Map) {
      Get.find<TagManagementController>().importFromJson(Map<String, dynamic>.from(legacyTags));
    }
  }

  bool backup(File file) {
    try {
      final data = exportAllSettings();
      file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
      return true;
    } catch (_) {
      return false;
    }
  }

  bool recover(File file) {
    try {
      final json = file.readAsStringSync();
      final data = jsonDecode(json);

      if (data is! Map<String, dynamic>) {
        return false;
      }

      importAllSettings(data);

      return true;
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> exportToTVSettings() {
    final danmaku = Get.find<DanmakuSettingsController>().toJson();
    final cookie = Get.find<CookieSettingsController>().toJson();
    final favorite = Get.find<FavoriteRoomController>().toJson();
    return {...danmaku, ...cookie, ...favorite};
  }

  /// 跨端传输导出：关注 + 登录（含真实 Cookie，仅经局域网明文传输，不落盘）
  Map<String, dynamic> exportTransferData() {
    final favorite = Get.find<FavoriteRoomController>().toJson();
    final cookie = Get.find<CookieSettingsController>();
    return {
      'transferVersion': 1,
      'favorite': favorite,
      'cookie': {
        'bilibiliCookie': cookie.bilibiliCookie.v,
        'huyaCookie': cookie.huyaCookie.v,
        'douyinCookie': cookie.douyinCookie.v,
        'douyuCookie': cookie.douyuCookie.v,
        'bilibiliUid': cookie.bilibiliUid.v,
      },
    };
  }

  /// 跨端传输导入：完全覆盖接收方的关注与登录数据
  bool importTransferData(Map<String, dynamic> data) {
    try {
      final favorite = data['favorite'];
      if (favorite is Map) {
        Get.find<FavoriteRoomController>().fromJson(Map<String, dynamic>.from(favorite));
      }
      final cookie = data['cookie'];
      if (cookie is Map) {
        Get.find<CookieSettingsController>().fromJson(Map<String, dynamic>.from(cookie));
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}
