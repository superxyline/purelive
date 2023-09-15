

import 'package:get/get.dart';
import 'package:pure_live/plugins/supabase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthController extends GetxController {
  final supabaseClient = SupaBaseManager().client;
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
        SupaBaseManager().readConfig();
      } else {
        isLogin = false;
        userId = '';
      }
    });
  }
}
