import 'dart:convert';

import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/auth/auth_controller.dart';
import 'package:pure_live/modules/favorite/favorite_controller.dart';
import 'package:pure_live/routes/app_pages.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupBaseManager {
  final String supabaseUrl = 'https://izqkszjbjoumibcoldzk.supabase.co';
  final String supabaseKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml6cWtzempiam91bWliY29sZHprIiwicm9sZSI6ImFub24iLCJpYXQiOjE2OTE3MjU0MzgsImV4cCI6MjAwNzMwMTQzOH0.9tOWVb3hLzdRpGazU9A84nCns9p2DhvimSJenhNPfWU';
  static late SupBaseManager _instance;

  SupBaseManager._internal();
  late Supabase supabase;
  final String tableName = 'follows';
  final String userColumnName = 'user_id';
  final String configColumnName = 'settings';
  SupabaseClient get client => Supabase.instance.client;
  //单例模式，只创建一次实例
  static SupBaseManager getInstance() {
    _instance = SupBaseManager._internal();
    return _instance;
  }

  SupBaseManager();
  Future initial() async {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
  }

  signOut() {
    final SettingsService service = Get.find<SettingsService>();
    client.auth.signOut().then((value) {
      service.fromJson(service.defaultConfig());
      Get.offAllNamed(AppPages.initial);
    });
  }

  Future<void> uploadConfig() async {
    final userId = Get.find<AuthController>().userId;
    final SettingsService service = Get.find<SettingsService>();
    List<dynamic> data =
        await client.from(tableName).select().eq(userColumnName, userId);
    if (data.isNotEmpty) {
      client
          .from(tableName)
          .update({configColumnName: jsonEncode(service.toJson())})
          .eq(userColumnName, userId)
          .then((value) => Get.rawSnackbar(message: '上传成功'), onError: (err) {
            Get.rawSnackbar(message: '上传失败');
          });
    } else {
      client.from(tableName).insert({
        userColumnName: userId,
        configColumnName: jsonEncode(service.toJson())
      }).then((value) => Get.rawSnackbar(message: '上传成功'), onError: (err) {
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
      List<dynamic> data =
          await client.from(tableName).select().eq(userColumnName, userId);
      if (data.isNotEmpty) {
        String json = data[0][configColumnName];
        service.fromJson(jsonDecode(json));
        favoriteController.onRefresh();
      }
    }
  }
}
