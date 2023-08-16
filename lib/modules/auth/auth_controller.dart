

import 'package:get/get.dart';
import 'package:pure_live/plugins/supbase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthController extends GetxController {
  final supabaseClient = SupBaseManager().client;
  late bool isLogin = false;
  String userId = '';
  @override
  void onInit() {
    super.onInit();
    supabaseClient.auth.onAuthStateChange.listen((data) {
      final AuthChangeEvent event = data.event;
      final Session? session = data.session;
      if (event == AuthChangeEvent.signedIn) {
        isLogin = true;
        userId = session!.user.id;
        SupBaseManager().readConfig();
      } else {
        isLogin = false;
        userId = '';
      }
    });
  }
}
