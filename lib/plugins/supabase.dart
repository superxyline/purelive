import 'dart:convert';
import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/plugins/archethic.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pure_live/modules/auth/auth_controller.dart';
import 'package:pure_live/modules/favorite/favorite_controller.dart';

class SupaBaseManager {
  final String supabaseUrl = 'https://izqkszjbjoumibcoldzk.supabase.co';
  final String supabaseKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml6cWtzempiam91bWliY29sZHprIiwicm9sZSI6ImFub24iLCJpYXQiOjE2OTE3MjU0MzgsImV4cCI6MjAwNzMwMTQzOH0.9tOWVb3hLzdRpGazU9A84nCns9p2DhvimSJenhNPfWU';
  static late SupaBaseManager _instance;

  SupaBaseManager._internal();
  late Supabase supabase;
  final String tableName = 'follows';
  final String userColumnName = 'user_id';
  final String configColumnName = 'settings';
  final String isEncrypt = 'is_encrypt';
  final String isLzs = 'is_lzs';
  SupabaseClient get client => Supabase.instance.client;
  //单例模式，只创建一次实例
  static SupaBaseManager getInstance() {
    _instance = SupaBaseManager._internal();
    return _instance;
  }

  SupaBaseManager();
  Future initial() async {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
  }

  signOut() {
    client.auth.signOut().then((value) {
      Get.offAllNamed(RoutePath.kInitial);
    });
  }

  Future<void> uploadConfigWithBackGend() async {
    final isLogin = Get.find<AuthController>().isLogin;
    if (!isLogin) {
      return;
    }
    final userId = Get.find<AuthController>().userId;
    final SettingsService service = Get.find<SettingsService>();
    List<dynamic> data = await client.from(tableName).select().eq(userColumnName, userId);
    final isHasEncrypt = data.isNotEmpty ? data[0][isEncrypt] : false;
    final isHasLzs = data.isNotEmpty ? data[0][isLzs] : false;
    var encryptData = ArchethicUtils().encrypt(jsonEncode(service.toJson()), isHasEncrypt, isHasLzs);
    if (data.isNotEmpty) {
      client
          .from(tableName)
          .update({configColumnName: encryptData, isEncrypt: true, isLzs: true})
          .eq(userColumnName, userId)
          .then((value) => {}, onError: (err) {});
    } else {
      client
          .from(tableName)
          .insert({userColumnName: userId, configColumnName: encryptData, isEncrypt: true, isLzs: true}).then(
              (value) => {},
              onError: (err) {});
    }
  }

  Future<void> uploadConfig() async {
    final isLogin = Get.find<AuthController>().isLogin;
    if (!isLogin) {
      return;
    }
    final userId = Get.find<AuthController>().userId;
    final SettingsService service = Get.find<SettingsService>();
    List<dynamic> data = await client.from(tableName).select().eq(userColumnName, userId);
    final isHasEncrypt = await isDataEncrypt();
    final isHasLzs = await isDataLzs();
    final encryptData = await ArchethicUtils().encrypt(jsonEncode(service.toJson()), isHasEncrypt, isHasLzs);
    if (data.isNotEmpty) {
      client
          .from(tableName)
          .update({configColumnName: encryptData, isEncrypt: true, isLzs: true})
          .eq(userColumnName, userId)
          .then((value) => Get.rawSnackbar(message: '上传成功'), onError: (err) {
            Get.rawSnackbar(message: '上传失败');
          });
    } else {
      client
          .from(tableName)
          .insert({userColumnName: userId, configColumnName: encryptData, isEncrypt: true, isLzs: true}).then(
              (value) => Get.rawSnackbar(message: '上传成功'), onError: (err) {
        Get.rawSnackbar(message: '上传失败');
      });
    }
  }

  Future<void> readConfig() async {
    final userId = Get.find<AuthController>().userId;
    final isLogin = Get.find<AuthController>().isLogin;
    final FavoriteController favoriteController = Get.find<FavoriteController>();
    if (isLogin == true) {
      final SettingsService service = Get.find<SettingsService>();
      List<dynamic> data = await client.from(tableName).select().eq(userColumnName, userId);
      if (data.isNotEmpty) {
        String jsonString = data[0][configColumnName];
        bool isAlreadyEncrypt = data[0][isEncrypt];
        bool isHasLzs = data[0][isLzs];
        if (isAlreadyEncrypt) {
          final jsonData = await ArchethicUtils().decrypti(jsonString, isAlreadyEncrypt, isHasLzs);
          Map<String, dynamic> back = jsonDecode(jsonData!);
          service.fromJson(back);
        } else {
          service.fromJson(jsonDecode(jsonString));
        }
        favoriteController.onRefresh();
      }
    }
  }

  Future<bool> isDataEncrypt() async {
    final userId = Get.find<AuthController>().userId;
    final isLogin = Get.find<AuthController>().isLogin;
    if (isLogin == true) {
      List<dynamic> data = await client.from(tableName).select().eq(userColumnName, userId);
      if (data.isNotEmpty) {
        return data[0][isEncrypt];
      }
    }
    return false;
  }

  Future<bool> isDataLzs() async {
    final userId = Get.find<AuthController>().userId;
    final isLogin = Get.find<AuthController>().isLogin;
    if (isLogin == true) {
      List<dynamic> data = await client.from(tableName).select().eq(userColumnName, userId);
      if (data.isNotEmpty) {
        return data[0][isLzs];
      }
    }
    return false;
  }
}
