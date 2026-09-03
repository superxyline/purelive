import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final cookie = "acf_uid=27047486;acf_stk=11b344af7ef2cca3;dy_did=1976bad760eb7b35a33d922900061701";
  final roomId = "10917030";
  final msg = "主播你好";

  final client = HttpClient()
    ..badCertificateCallback = ((_, __, ___) => true)
    ..connectionTimeout = Duration(seconds: 10);

  // 方法1: POST sendcontent
  try {
    final req = await client.postUrl(Uri.parse("https://www.douyu.com/member/room/sendcontent"));
    req.headers.set("Cookie", cookie);
    req.headers.set("Referer", "https://www.douyu.com/$roomId");
    req.headers.set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36");
    req.headers.contentType = ContentType("application", "x-www-form-urlencoded", charset: "utf-8");
    req.write("roomid=$roomId&content=$msg");
    final resp = await req.close().timeout(Duration(seconds: 10));
    final body = await resp.transform(utf8.decoder).join();
    print("[sendcontent] ${resp.statusCode}: $body");
  } catch (e) {
    print("[sendcontent] ERROR: $e");
  }

  // 方法2: POST /v1/danmu/send
  try {
    final req2 = await client.postUrl(Uri.parse("https://www.douyu.com/member/room/chat"));
    req2.headers.set("Cookie", cookie);
    req2.headers.set("Referer", "https://www.douyu.com/$roomId");
    req2.headers.set("User-Agent", "Mozilla/5.0");
    req2.headers.contentType = ContentType("application", "x-www-form-urlencoded", charset: "utf-8");
    req2.write("roomid=$roomId&content=$msg&col=0&pt=0&dms=5");
    final resp2 = await req2.close().timeout(Duration(seconds: 10));
    final body2 = await resp2.transform(utf8.decoder).join();
    print("[chat] ${resp2.statusCode}: $body2");
  } catch (e) {
    print("[chat] ERROR: $e");
  }

  // 方法3: 抓取页面获取弹幕token
  try {
    final req3 = await client.getUrl(Uri.parse("https://www.douyu.com/$roomId"));
    req3.headers.set("Cookie", cookie);
    req3.headers.set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)");
    final resp3 = await req3.close().timeout(Duration(seconds: 10));
    final body3 = await resp3.transform(utf8.decoder).join();
    // 搜索关键字段
    if (body3.contains("roomid")) print("[page] roomid found");
    if (body3.contains("token")) {
      final match = RegExp(r'"token"\s*:\s*"([^"]+)"').firstMatch(body3);
      if (match != null) print("[page] token: ${match.group(1)}");
    }
    // 搜索 stk 相关
    if (body3.contains("stk")) print("[page] stk reference found");
    print("[page] status: ${resp3.statusCode}, length: ${body3.length}");
  } catch (e) {
    print("[page] ERROR: $e");
  }

  client.close();
}