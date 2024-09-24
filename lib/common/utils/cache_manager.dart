// ignore_for_file: implementation_imports
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:file/local.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_cache_manager/src/storage/file_system/file_system_io.dart';
import 'package:pure_live/core/common/http_client.dart' as http_client;

class CustomCacheManager {
  static const key = 'customCacheKey';

  static CacheManager instance = CacheManager(
    Config(
      key,
      stalePeriod: const Duration(days: 3),
      // maxNrOfCacheObjects: 20,
      repo: JsonCacheInfoRepository(databaseName: key),
      fileSystem: IOFileSystem(key),
      // fileService: HttpFileService(),
      fileService: DioHttpFileService(http_client.HttpClient.instance.dio),
    ),
  );

  static Future<double> cacheSize() async {
    var baseDir = await getTemporaryDirectory();
    var path = p.join(baseDir.path, key);

    var fs = const LocalFileSystem();
    var directory = fs.directory((path));
    return (await directory.stat()).size / 8 / 1000;
  }

  static Future<void> clearCache() async {
    var baseDir = await getTemporaryDirectory();
    var path = p.join(baseDir.path, key);

    var fs = const LocalFileSystem();
    var directory = fs.directory((path));
    await directory.delete(recursive: true);
  }
}

class DioHttpFileService extends FileService {
  final Dio _dio;

  DioHttpFileService(this._dio);

  @override
  Future<FileServiceResponse> get(String url, {Map<String, String>? headers}) async {
    Options options =
    Options(headers: headers ?? {}, responseType: ResponseType.stream);

    Response<ResponseBody> httpResponse =
    await _dio.get<ResponseBody>(url, options: options);

    return DioGetResponse(httpResponse);
  }
}

class DioGetResponse implements FileServiceResponse {
  final DateTime _receivedTime = DateTime.now();
  final Response<ResponseBody> _response;

  DioGetResponse(this._response);

  @override
  Stream<List<int>> get content =>
      _response.data!.stream.map((e) => e.toList());

  @override
  int get contentLength => _getContentLength();

  @override
  String get eTag => _response.headers['etag']?.first ?? '-1';

  @override
  String get fileExtension {
    var fileExtension = '';
    final contentTypeHeader =
        _response.headers[Headers.contentTypeHeader]?.first;
    if (contentTypeHeader != null) {
      final contentType = ContentType.parse(contentTypeHeader);
      fileExtension = contentType.mimeType;
    }
    return fileExtension;
  }

  @override
  int get statusCode => _response.statusCode ?? 500;

  @override
  DateTime get validTill {
    // Without a cache-control header we keep the file for a week
    var ageDuration = const Duration(days: 7);
    final controlHeader = _response.headers['cache-control']?.first;
    if (controlHeader != null) {
      final controlSettings = controlHeader.split(',');
      for (final setting in controlSettings) {
        final sanitizedSetting = setting.trim().toLowerCase();
        if (sanitizedSetting == 'no-cache') {
          ageDuration = const Duration();
        }
        if (sanitizedSetting.startsWith('max-age=')) {
          var validSeconds = int.tryParse(sanitizedSetting.split('=')[1]) ?? 0;
          if (validSeconds > 0) {
            ageDuration = Duration(seconds: validSeconds);
          }
        }
      }
    }

    return _receivedTime.add(ageDuration);
  }

  int _getContentLength() {
    try {
      return int.parse(
          _response.headers[Headers.contentLengthHeader]?.first ?? '-1');
    } catch (e) {
      return -1;
    }
  }
}

