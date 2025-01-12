import 'package:get/get.dart';
import 'package:pure_live/common/l10n/generated/l10n.dart';

class SnackBarUtil {
  static void success(String text) {
    Get.snackbar(
      S.of(Get.context!).success,
      text,
      duration: const Duration(seconds: 2),
      backgroundColor: Get.theme.colorScheme.surfaceContainerHighest,
      colorText: Get.theme.colorScheme.onSurfaceVariant,
      snackPosition: SnackPosition.bottom,
    );
  }

  static void error(String text) {
    Get.snackbar(
      S.of(Get.context!).error,
      text,
      duration: const Duration(seconds: 2),
      backgroundColor: Get.theme.colorScheme.errorContainer,
      colorText: Get.theme.colorScheme.onErrorContainer,
      snackPosition: SnackPosition.bottom,
    );
  }
}
