// 本文件内嵌抖音 a_bogus / x-bogus 签名算法。
// 算法来自社区公开的逆向分析成果，仅用于个人学习与交流，原始出处待核实。
// 详细声明见仓库根目录 THIRD_PARTY_NOTICES.md。
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:dart_quickjs/dart_quickjs.dart';
import 'package:pure_live/core/site/douyin_site.dart';
import 'douyin_abogus_js.dart';
import 'douyin_webms_js.dart';

class DouyinSign {


  static const String defaultUserAgent = DouyinSite.kDefaultUserAgent;

  // 复用 JS 运行时，避免每次签名调用都创建新的 4MB 实例（同步执行，无并发冲突）
  static final JsRuntime _abogusRuntime = JsRuntime(memoryLimit: 4 * 1024 * 1024, maxStackSize: 64 * 1024);
  static final JsRuntime _signatureRuntime = JsRuntime(memoryLimit: 4 * 1024 * 1024, maxStackSize: 128 * 1024);
  static String getAbogusUrl(String url, String userAgent) {
    final msToken = generateMsToken(107);
    var params = ('$url&msToken=$msToken').split('?')[1];
    var query = params.contains("?") ? params.split("?")[1] : params;
    var jsCode = kABogus;
    _abogusRuntime.eval(jsCode);
    // 执行getABogus函数
    var aBogus = _abogusRuntime.eval("getABogus('$query', '$userAgent')");
    var newUrl = '$url&msToken=${Uri.encodeComponent(msToken)}&a_bogus=${Uri.encodeComponent(aBogus)}';
    return newUrl;
  }

  static String getSignature(String roomId, String uniqueId) {

    _signatureRuntime.eval(kWebMsSDK);
    var msStub = getMsStub(roomId, uniqueId);
    var signature = _signatureRuntime.eval("getMSSDKSignature('$msStub','$defaultUserAgent')");
    // 如果signature中包含-或=，重新生成
    while (signature.contains('-') || signature.contains('=')) {
      signature = _signatureRuntime.eval("getMSSDKSignature('$msStub','$defaultUserAgent')");
    }
    return signature;
  }

  static String getMsStub(String roomId, String uniqueId) {
    final params = {
      "live_id": "1",
      "aid": "6383",
      "version_code": 180800,
      "webcast_sdk_version": "1.3.0",
      "room_id": roomId,
      "sub_room_id": "",
      "sub_channel_id": "",
      "did_rule": "3",
      "user_unique_id": uniqueId,
      "device_platform": "web",
      "device_type": "",
      "ac": "",
      "identity": "audience",
    };
    final sigParams = params.entries.map((e) => "${e.key}=${e.value}").join(',');
    // 需要导入crypto库: import 'package:crypto/crypto.dart';
    final bytes = sigParams.codeUnits;
    final digest = md5.convert(bytes);
    return digest.toString();
  }

  static String generateMsToken(int length) {
    const characters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List.generate(length, (_) => characters[random.nextInt(characters.length)]).join('');
  }
}
