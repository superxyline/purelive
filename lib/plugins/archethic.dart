import 'package:pure_live/plugins/lzstring.dart';

class ArchethicUtils {
  // 加密
  String? encrypt(String data) {
    return LZString.compressSync(data)!;
  }

  // 解密
  String? decrypti(String data) {
    return LZString.decompressSync(data)!;
  }
}
