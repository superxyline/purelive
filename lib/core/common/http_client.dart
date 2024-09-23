import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:dio_cache_interceptor_db_store/dio_cache_interceptor_db_store.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:path_provider/path_provider.dart';
import 'custom_interceptor.dart';
import 'package:pure_live/core/common/core_error.dart';

import 'custom_io_http_client_adapter.dart';


class HttpClient {
  static HttpClient? _httpUtil;

  static HttpClient get instance {
    _httpUtil ??= HttpClient();
    return _httpUtil!;
  }

  static CacheStore? getCacheStore() {
    getTemporaryDirectory().then((dir){
      return DbCacheStore(databasePath: dir.path, logStatements: true);
    });
    sleep(const Duration(seconds: 2));
    return null;
  }

  static CacheOptions cacheOptions = CacheOptions(
    // A default store is required for interceptor.
    store: getCacheStore(),

    // All subsequent fields are optional.

    // Default.
    policy: CachePolicy.request,
    // Returns a cached response on error but for statuses 401 & 403.
    // Also allows to return a cached response on network errors (e.g. offline usage).
    // Defaults to [null].
    hitCacheOnErrorExcept: const [401, 403],
    // Overrides any HTTP directive to delete entry past this duration.
    // Useful only when origin server has no cache config or custom behaviour is desired.
    // Defaults to [null].
    maxStale: const Duration(minutes: 2),
    // Default. Allows 3 cache sets and ease cleanup.
    priority: CachePriority.normal,
    // Default. Body and headers encryption with your own algorithm.
    cipher: null,
    // Default. Key builder to retrieve requests.
    keyBuilder: CacheOptions.defaultCacheKeyBuilder,
    // Default. Allows to cache POST requests.
    // Overriding [keyBuilder] is strongly recommended when [true].
    allowPostMethod: false,
  );

  late Dio dio;
  HttpClient() {

    dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 20),
      ),
    );
    dio.interceptors.add(CustomInterceptor());
    dio.interceptors.add(DioCacheInterceptor(options: cacheOptions));
    dio.httpClientAdapter = CustomIOHttpClientAdapter.instance;
  }

  /// Get请求，返回String
  /// * [url] 请求链接
  /// * [queryParameters] 请求参数
  /// * [cancel] 任务取消Token
  Future<String> getText(
    String url, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? header,
    CancelToken? cancel,
  }) async {
    try {
      queryParameters ??= {};
      header ??= {};
      var result = await dio.get(
        url,
        queryParameters: queryParameters,
        options: Options(
          responseType: ResponseType.plain,
          headers: header,
        ),
        cancelToken: cancel,
      );
      return result.data;
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.badResponse) {
        throw CoreError(e.message ?? "", statusCode: e.response?.statusCode ?? 0);
      } else {
        throw CoreError("发送GET请求失败");
      }
    }
  }

  /// Get请求，返回Map
  /// * [url] 请求链接
  /// * [queryParameters] 请求参数
  /// * [cancel] 任务取消Token
  Future<dynamic> getJson(
    String url, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? header,
    CancelToken? cancel,
  }) async {
    try {
      queryParameters ??= {};
      header ??= {};
      var result = await dio.get(
        url,
        queryParameters: queryParameters,
        options: Options(
          responseType: ResponseType.json,
          headers: header,
        ),
        cancelToken: cancel,
      );
      return result.data;
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.badResponse) {
        throw CoreError(e.message ?? "", statusCode: e.response?.statusCode ?? 0);
      } else {
        throw CoreError("发送GET请求失败");
      }
    }
  }

  /// Post请求，返回Map
  /// * [url] 请求链接
  /// * [queryParameters] 请求参数
  /// * [data] 内容
  /// * [cancel] 任务取消Token
  Future<dynamic> postJson(
    String url, {
    Map<String, dynamic>? queryParameters,
    dynamic data,
    Map<String, dynamic>? header,
    bool formUrlEncoded = false,
    CancelToken? cancel,
  }) async {
    try {
      queryParameters ??= {};
      header ??= {};
      data ??= {};
      var result = await dio.post(
        url,
        queryParameters: queryParameters,
        data: data,
        options: Options(
          responseType: ResponseType.json,
          headers: header,
          contentType: formUrlEncoded ? Headers.formUrlEncodedContentType : null,
        ),
        cancelToken: cancel,
      );
      return result.data;
    } catch (e) {
      SmartDialog.showToast(e.toString());
      if (e is DioException && e.type == DioExceptionType.badResponse) {
        throw CoreError(e.message ?? "", statusCode: e.response?.statusCode ?? 0);
      } else {
        throw CoreError("发送POST请求失败");
      }
    }
  }

  /// Head请求，返回Response
  /// * [url] 请求链接
  /// * [queryParameters] 请求参数
  /// * [cancel] 任务取消Token
  Future<Response> head(
    String url, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? header,
    CancelToken? cancel,
  }) async {
    try {
      queryParameters ??= {};
      header ??= {};
      var result = await dio.head(
        url,
        queryParameters: queryParameters,
        options: Options(
          headers: header,
          receiveDataWhenStatusError: true,
        ),
        cancelToken: cancel,
      );
      return result;
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.badResponse) {
        //throw CoreError(e.message, statusCode: e.response?.statusCode ?? 0);
        return e.response!;
      } else {
        throw CoreError("发送HEAD请求失败");
      }
    }
  }

  /// Get请求，返回Response
  /// * [url] 请求链接
  /// * [queryParameters] 请求参数
  /// * [cancel] 任务取消Token
  Future<Response<dynamic>> get(
    String url, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? header,
    CancelToken? cancel,
  }) async {
    try {
      queryParameters ??= {};
      header ??= {};
      var result = await dio.get(
        url,
        queryParameters: queryParameters,
        options: Options(
          responseType: ResponseType.json,
          headers: header,
        ),
        cancelToken: cancel,
      );
      return result;
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.badResponse) {
        return e.response!;
      } else {
        throw CoreError("发送GET请求失败");
      }
    }
  }
}
