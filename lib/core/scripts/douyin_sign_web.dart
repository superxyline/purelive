import 'dart:math';

import 'package:pure_live/core/common/http_client.dart';

/// Web 端抖音签名：a-bogus / X-Bogus 等交给 NAS 后端执行原 JS 片段；
/// msToken 是纯随机串，本地直接生成，无需网络。
class DouyinSign {
  static Future<String> _post(String path, Map<String, dynamic> body) async {
    final result = await HttpClient.instance.postJson(
      '/api/sign/douyin/$path',
      data: body,
    );
    return (result['result'] as String?) ?? '';
  }

  static Future<String> getAbogusUrl(String url, String userAgent) =>
      _post('abogus', {'url': url, 'userAgent': userAgent});

  static Future<String> getSignature(String roomId, String uniqueId) =>
      _post('signature', {'roomId': roomId, 'uniqueId': uniqueId});

  static Future<String> getMsStub(String roomId, String uniqueId) =>
      _post('msStub', {'roomId': roomId, 'uniqueId': uniqueId});

  static String generateMsToken(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand = Random.secure();
    return String.fromCharCodes(
      Iterable.generate(length, (_) => chars.codeUnitAt(rand.nextInt(chars.length))),
    );
  }
}
