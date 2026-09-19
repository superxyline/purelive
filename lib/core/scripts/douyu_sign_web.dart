import 'package:pure_live/core/common/http_client.dart';

/// Web 端斗鱼取流签名：本地无 QuickJS，转发给 NAS 后端执行原 JS 片段。
class DouyuSign {
  static Future<String> getSign(String html, String rid) async {
    final result = await HttpClient.instance.postJson(
      '/api/sign/douyu',
      data: {'html': html, 'rid': rid},
    );
    return (result['sign'] as String?) ?? '';
  }
}
