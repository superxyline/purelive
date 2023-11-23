import 'dart:async';
import 'package:get/get.dart';
import 'package:pure_live/plugins/supabase.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthController extends GetxController {
  final supabaseClient = SupaBaseManager().client;
  bool shouldGoReset = false;
  late bool isLogin = false;
  String userId = '';
  @override
  void onInit() {
    super.onInit();
    supabaseClient.auth.onAuthStateChange.listen((data) {
      final AuthChangeEvent event = data.event;
      final Session? session = data.session;
      if (session?.user != null) {
        isLogin = true;
        userId = data.session!.user.id;
        SupaBaseManager().readConfig();
      } else {
        isLogin = false;
        userId = '';
      }
      if (event == AuthChangeEvent.passwordRecovery && shouldGoReset) {
        Timer(const Duration(seconds: 2), () {
          shouldGoReset = false;
          Get.offAndToNamed(RoutePath.kUpdatePassword);
        });
      }
    });
  }
}
