import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:io' show InternetAddress;
class ShelfUtil {
  static Future<bool> checkConnectWifi() async {
    final Connectivity connectivity = Connectivity();
    ConnectivityResult result = await connectivity.checkConnectivity();
    //  以太网或者wifi
    if (result == ConnectivityResult.wifi ||
        result == ConnectivityResult.ethernet) {
      return true;
    }
    return false;
  }

  static Future<void> setup() async {
    Response echoRequest(Request request) =>
        Response.ok('Request for "${request.url}"');
    var handler =
        const Pipeline().addMiddleware(logRequests()).addHandler(echoRequest);
   var server = await shelf_io.serve(handler, InternetAddress.anyIPv4, 8080);

      // Enable content compression
      server.autoCompress = true;

      print('Serving at http://${server.address.host}:${server.port}');
  }
}
