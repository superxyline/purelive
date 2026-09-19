import 'package:dio/browser.dart';
import 'package:dio/dio.dart';

/// Web 平台的 dio adapter：浏览器内运行，代理由部署环境（同源 /api 反代）承担。
HttpClientAdapter createAdapter() {
  return BrowserHttpClientAdapter(withCredentials: false);
}
