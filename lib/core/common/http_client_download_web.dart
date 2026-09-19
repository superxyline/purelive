import 'package:dio/dio.dart';
import 'package:pure_live/core/common/http_client.dart';

/// Web 平台 stub：文件下载仅 io 端功能模块使用（这些模块在 web 上被整体 stub），
/// 若意外被调用则显式报错。
extension HttpClientDownloadWeb on HttpClient {
  Future<void> download(
    String url,
    String savePath, {
    Map<String, dynamic>? header,
    CancelToken? cancel,
    Function(int value, int progress)? onReceiveProgress,
  }) async {
    throw UnsupportedError('HttpClient.download is not available on web');
  }
}
