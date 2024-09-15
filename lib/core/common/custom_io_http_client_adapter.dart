
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