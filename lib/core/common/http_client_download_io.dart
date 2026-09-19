import 'dart:io' as io;

import 'package:dio/dio.dart';
import 'package:pure_live/core/common/core_error.dart';
import 'package:pure_live/core/common/http_client.dart';

/// io 平台的文件下载实现（返回真实文件句柄）。
extension HttpClientDownloadIo on HttpClient {
  Future<io.File> download(
    String url,
    String savePath, {
    Map<String, dynamic>? header,
    CancelToken? cancel,
    Function(int value, int progress)? onReceiveProgress,
  }) async {
    const downloadSuccessCode1 = 200;
    const downloadSuccessCode2 = 206;
    final tempPath = "$savePath.part";
    final tempFile = io.File(tempPath);

    try {
      if (!await tempFile.exists()) {
        await tempFile.create(recursive: true);
      }
      final response = await dio.download(
        url,
        tempPath,
        cancelToken: cancel,
        onReceiveProgress: onReceiveProgress,
        options: Options(headers: header),
      );

      if (response.statusCode == downloadSuccessCode1 || response.statusCode == downloadSuccessCode2) {
        return await tempFile.rename(savePath);
      } else {
        throw HttpError("下载失败", statusCode: response.statusCode ?? 0);
      }
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        throw HttpError("下载已取消");
      } else if (e.type == DioExceptionType.badResponse) {
        throw HttpError(e.message ?? "", statusCode: e.response?.statusCode ?? 0);
      } else {
        throw HttpError("下载请求失败");
      }
    }
  }
}
