
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pure_live/modules/auth/components/supa_email_auth.dart';
import 'package:pure_live/plugins/supbase.dart';
import 'package:pure_live/routes/app_pages.dart';
import 'dart:developer';

import 'package:supabase_flutter/supabase_flutter.dart';
class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('登录'),
      ),
       body: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              SupaEmailAuth(
                redirectTo: kIsWeb ? null : 'purelive://signin',
                onSignInComplete: (AuthResponse response) {
                  SupBaseManager().readConfig();
                  Get.rawSnackbar(message: '登陆成功');
                  Get.offAllNamed(AppPages.initial);
                },
                onSignUpComplete: (AuthResponse response) {
                  Get.rawSnackbar(message: '请确认您的邮箱');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
