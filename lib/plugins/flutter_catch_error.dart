import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/utils/pref_util.dart';
import 'package:pure_live/core/common/core_log.dart';
import 'package:pure_live/main.dart';
import 'package:pure_live/plugins/global.dart';
///全局异常的捕捉
class FlutterCatchError {
  static run(Widget app, List<String> args) {
    ///Flutter 框架异常
    FlutterError.onError = (FlutterErrorDetails details) async {
      ///TODO 线上环境
      if (kReleaseMode) {
        Zone.current.handleUncaughtError(details.exception, details.stack!);
      } else {
        ///TODO 开发期间 print
        FlutterError.dumpErrorToConsole(details);
      }
    };

    setCustomErrorPage();

    runZonedGuarded(() async {

      WidgetsFlutterBinding.ensureInitialized();
      PrefUtil.prefs = await SharedPreferences.getInstance();
      MediaKit.ensureInitialized();
      if (Platform.isWindows) {
        register(kWindowsScheme);
        await WindowsSingleInstance.ensureSingleInstance(args, "pure_live_instance_checker");
        await windowManager.ensureInitialized();
        await WindowUtil.init(width: 1280, height: 720);
      }
      // 先初始化supdatabase
      await SupaBaseManager.getInstance().initial();
      // 初始化服务
      initService();
      initRefresh();

      ///受保护的代码块
      runApp(app);
    }, (error, stack) => catchError(error, stack));
  }

  ///对搜集的 异常进行处理  上报等等
  static catchError(Object error, StackTrace stack) {
    if(kDebugMode){
      print("AppCatchError>>>>>>>>>>: $kReleaseMode"); //是否是 Release版本
      print('APP出现异常  message:$error,stackTrace：$stack');
      CoreLog.error(stack);
    }
  }

  ///自定义异常页面
  static void setCustomErrorPage() {
    ErrorWidget.builder = (FlutterErrorDetails flutterErrorDetails) {
      debugPrint(flutterErrorDetails.toString());
      String stError = flutterErrorDetails.exceptionAsString();
      return Material(
        color: Colors.transparent,
        child: SafeArea(
          child: Container(
              color: Colors.white,
              padding:  const EdgeInsets.all(15),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(
                      child: Icon(Icons.error,size: 55,color: Colors.orange,),
                    ),
                    Text("Current module exception${'，System diagnosis as：${stError.split(':').isNotEmpty?stError.split(':')[0]:''}'}，Please contact the administrator！",
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14,fontWeight: FontWeight.w500,letterSpacing: 0.4),
                    ),
                    Text(
                      flutterErrorDetails.exceptionAsString(),
                      style: const TextStyle(color: Colors.blue, fontSize: 14),
                      textAlign: TextAlign.start,
                    )
                  ],
                ),
              )
          ),
        ),
      );
    };
  }
}