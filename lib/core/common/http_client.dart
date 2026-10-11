import 'package:dio/dio.dart';
import 'dart:io' as io;
import 'dart:typed_data';
import 'package:pure_live/core/common/core_error.dart';
import 'package:pure_live/core/common/custom_interceptor.dart';

import 'dio_adapter_io.dart' if (dart.library.js_interop) 'dio_adapter_web.dart' as adapter;

class HttpClient {
  static const Duration _connectTimeout = Duration(seconds: 20);
  static const Duration _receiveTimeout = Duration(seconds: 20);
  static const Duration _sendTimeout = Duration(seconds: 20);


  static const String _errorGet = "发送GET请求失败";
  static const String _errorPost = "发送POST请求失败";
  static const String _errorHead = "发送HEAD请求失败";

  HttpClient._();
  static final HttpClient instance = HttpClient._();
  late Dio dio = _createDio();
  Dio _createDio() {
    return Dio(BaseOptions(connectTimeout: _connectTimeout, receiveTimeout: _receiveTimeout, sendTimeout: _sendTimeout))
      ..httpClientAdapter = adapter.createAdapter()
      ..interceptors.add(CustomLogInterceptor());
  }

  void rebuildDio() {
    final oldDio = dio;
    dio = _createDio();
    oldDio.close(force: false);
  }

  Future<String> getText(
    String url, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? header,
    CancelToken? cancel,
  }) async {
    try {
      final result = await dio.get(
        url,
        queryParameters: queryParameters,
        options: Options(responseType: ResponseType.plain, headers: header),
        cancelToken: cancel,
      );
      return result.data;
    } catch (e) {
      throw _handleError(e, _errorGet);
    }
  }

  Future<Uint8List> getBytes(
    String url, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? header,
  }) async {
    final result = await dio.get<List<int>>(
      url,
      queryParameters: queryParameters,
      options: Options(responseType: ResponseType.bytes, headers: header),
    );
    return Uint8List.fromList(result.data ?? const <int>[]);
  }

  /// 下载文件到本地（.part 临时文件 + 成功后改名），供壁纸媒体库使用。
  Future<io.File> download(
    String url,
    String savePath, {
    Map<String, dynamic>? header,
    Function(int value, int progress)? onReceiveProgress,
  }) async {
    final tempPath = "$savePath.part";
    final tempFile = io.File(tempPath);

    try {
      if (!await tempFile.exists()) {
        await tempFile.create(recursive: true);
      }
      final response = await dio.download(
        url,
        tempPath,
        onReceiveProgress: onReceiveProgress,
        options: Options(headers: header),
      );
      if (response.statusCode == 200 || response.statusCode == 206) {
        return await tempFile.rename(savePath);
      }
      throw HttpError('download failed', statusCode: response.statusCode ?? 0);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        if (tempFile.existsSync()) tempFile.deleteSync();
        rethrow;
      }
      throw HttpError(e.message ?? 'download error', statusCode: e.response?.statusCode ?? 0);
    } catch (e) {
      if (tempFile.existsSync()) tempFile.deleteSync();
      rethrow;
    }
  }

  Future<dynamic> getJson(
    String url, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? header,
    CancelToken? cancel,
  }) async {
    try {
      final result = await dio.get(
        url,
        queryParameters: queryParameters,
        options: Options(responseType: ResponseType.json, headers: header),
        cancelToken: cancel,
      );
      return result.data;
    } catch (e) {
      throw _handleError(e, _errorGet);
    }
  }

  Future<Response<dynamic>> get(
    String url, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? header,
    CancelToken? cancel,
  }) async {
    try {
      final result = await dio.get(
        url,
        queryParameters: queryParameters,
        options: Options(responseType: ResponseType.json, headers: header),
        cancelToken: cancel,
      );
      return result;
    } catch (e) {
      throw _handleError(e, _errorGet);
    }
  }

  Future<dynamic> postJson(
    String url, {
    Map<String, dynamic>? queryParameters,
    dynamic data,
    Map<String, dynamic>? header,
    bool formUrlEncoded = false,
    CancelToken? cancel,
  }) async {
    try {
      final result = await dio.post(
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
      throw _handleError(e, _errorPost);
    }
  }

  Future<Response> head(
    String url, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? header,
    CancelToken? cancel,
  }) async {
    try {
      final result = await dio.head(
        url,
        queryParameters: queryParameters,
        options: Options(headers: header, receiveDataWhenStatusError: true),
        cancelToken: cancel,
      );
      return result;
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.badResponse) {
        return e.response!;
      }
      throw HttpError(_errorHead);
    }
  }


  HttpError _handleError(dynamic e, String defaultMsg) {
    if (e is DioException && e.type == DioExceptionType.badResponse) {
      return HttpError(e.message ?? defaultMsg, statusCode: e.response?.statusCode ?? 0);
    } else {
      return HttpError(defaultMsg);
    }
  }
}
