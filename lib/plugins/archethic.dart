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
  encrypt(String data) {
    return CryptoSimple.encrypt(inputString: data);
  }

  // 解密
  decrypti(String data) {
    return CryptoSimple.decrypt(encrypted: data);
  }
}
