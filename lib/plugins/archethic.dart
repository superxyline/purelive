import 'package:pure_live/plugins/lzstring.dart';
import 'package:crypto_simple/crypto_simple.dart';

class ArchethicUtils {
  static const int superKey = 20156587414;
  static const int subKey = 66;
  String password = '';
  init({required String superPass}) {
    password = superPass;
    CryptoSimple(
      superKey: superKey,
      subKey: subKey,
      secretKey: superPass,
      encryptionMode: EncryptionMode.Randomized,
    );
  }

  // 加密
  String? encrypt(String data, bool isHasEncrypt, bool isLzs) {
    return LZString.compressSync(data)!;
  }

  // 解密
  String? decrypti(String data, bool isHasEncrypt, bool isLzs) {
    if (isLzs) {
      return LZString.decompressSync(data)!;
    } else {
      if (isHasEncrypt) {
        return CryptoSimple.decrypt(encrypted: data);
      }
      return data;
    }
  }
}
