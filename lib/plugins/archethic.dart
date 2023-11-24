import 'package:crypto_simple/crypto_simple.dart';

class ArchethicUtils {
  static const int superKey = 20156587414;
  static const int subKey = 66;
  init({required String superPass}) {
    CryptoSimple(
      superKey: superKey,
      subKey: subKey,
      secretKey: superPass,
      encryptionMode: EncryptionMode.Randomized,
    );
  }

  // 加密
  encrypt(data) {
    return CryptoSimple.encrypt(inputString: data);
  }

  // 解密
  decrypti(data) {
    return CryptoSimple.decrypt(encrypted: data);
  }
}
