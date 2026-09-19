import 'dart:io' as io;

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:pure_live/common/services/settings_service.dart';

/// io 平台（安卓/桌面）的 dio adapter：支持应用内代理设置。
HttpClientAdapter createAdapter() {
  return IOHttpClientAdapter(
    createHttpClient: () {
      final client = io.HttpClient();
      client.idleTimeout = const Duration(seconds: 30);
      client.findProxy = (uri) {
        final proxyCtrl = SettingsService.to.proxy;
        if (proxyCtrl.enableAppProxy.value &&
            proxyCtrl.appProxyHost.value.trim().isNotEmpty &&
            proxyCtrl.appProxyPort.value > 0) {
          final host = proxyCtrl.appProxyHost.value.trim();
          final port = proxyCtrl.appProxyPort.value;
          return 'PROXY $host:$port';
        }
        return 'DIRECT';
      };
      return client;
    },
  );
}
