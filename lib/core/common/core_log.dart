import 'package:logger/logger.dart';

class CoreLog {
  static bool enableLog = true;
  static Function(Level, String)? onPrintLog;
  static Logger logger = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 8,
      lineLength: 120,
      colors: true,
      printEmojis: true,
    ),
  );

  static void d(String message) {
    onPrintLog?.call(Level.debug, message);
    if (!enableLog) {
      return;
    }
    logger.d("${DateTime.now().toString()} - ${getFunctionName()}\n$message");
  }

  static void i(String message) {
    onPrintLog?.call(Level.info, message);
    if (!enableLog) {
      return;
    }
    logger.i("${DateTime.now().toString()} - ${getFunctionName()} - ${getFunctionName()}\n$message");
  }

  static void e(String message, StackTrace stackTrace) {
    onPrintLog?.call(Level.error, message);
    if (!enableLog) {
      return;
    }
    logger.e("${DateTime.now().toString()} - ${getFunctionName()} - ${getFunctionName()}\n$message", stackTrace: stackTrace);
  }

  static String getFunctionName() {
    var stackTrace = StackTrace.current;
    // log(stackTrace.toString());
    var frames = stackTrace.toString().split("\n");
    var functionName = frames[2].trim().split(RegExp("\\s+"))[1];
    return functionName;
  }

  static void error(e) {
    onPrintLog?.call(Level.error, e.toString());
    logger.e(
      "${DateTime.now().toString()} - ${getFunctionName()}\n${e.toString()}",
      error: e,
      stackTrace: (e is Error) ? e.stackTrace : StackTrace.current,
    );
  }

  static void w(String message) {
    onPrintLog?.call(Level.warning, message);
    if (!enableLog) {
      return;
    }
    logger.w("${DateTime.now().toString()} - ${getFunctionName()}\n$message");
  }

  static void logPrint(dynamic obj) {
    onPrintLog?.call(Level.error, obj.toString());
    if (!enableLog) {
      return;
    }
  }
}
