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
  Future<String?> encrypt(String data, bool isHasEncrypt, bool isLzs) async {
    if (isHasEncrypt) {
      return await LZString.compress(CryptoSimple.decrypt(encrypted: data));
    }
    return await LZString.compress(data);
  }

  // 解密
  Future<String?> decrypti(String data, bool isHasEncrypt, bool isLzs) async {
    if (isLzs) {
      return await LZString.decompress(data);
    } else {
      if (isHasEncrypt) {
        return CryptoSimple.decrypt(encrypted: data);
      }
      return data;
    }
  }
}
