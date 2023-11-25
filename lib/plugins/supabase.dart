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
    var encryptData = ArchethicUtils().encrypt(jsonEncode(service.toJson()));
    if (data.isNotEmpty) {
      client
          .from(tableName)
          .update({configColumnName: encryptData, isEncrypt: true})
          .eq(userColumnName, userId)
          .then((value) => {}, onError: (err) {});
    } else {
      client.from(tableName).insert({userColumnName: userId, configColumnName: encryptData, isEncrypt: true}).then(
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
    String encryptData = await ArchethicUtils().encrypt(jsonEncode(service.toJson()));
    if (data.isNotEmpty) {
      client
          .from(tableName)
          .update({configColumnName: encryptData, isEncrypt: true})
          .eq(userColumnName, userId)
          .then((value) => Get.rawSnackbar(message: '上传成功'), onError: (err) {
            Get.rawSnackbar(message: '上传失败');
          });
    } else {
      client.from(tableName).insert({userColumnName: userId, configColumnName: encryptData, isEncrypt: true}).then(
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
        if (isAlreadyEncrypt) {
          Map<String, dynamic> back = jsonDecode(ArchethicUtils().decrypti(jsonString));
          service.fromJson(back);
        } else {
          service.fromJson(jsonDecode(jsonString));
        }
        favoriteController.onRefresh();
      }
    }
  }
}
