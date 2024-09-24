
import 'dart:io';

import 'package:dio/io.dart';

class CustomIOHttpClientAdapter {

  static IOHttpClientAdapter get instance {
    return IOHttpClientAdapter(createHttpClient: () {
      var httpClient = HttpClient();
      httpClient.badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
      return httpClient;
    });
  }
}

class GlobalHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    var client = super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
    return client;
  }
}