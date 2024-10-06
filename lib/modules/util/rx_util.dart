import 'package:get/get.dart';

final class RxUtil {}

extension RxValueExtension<T> on Rx<T> {
  /// 更新值,d 当不一样时
  void updateValueNotEquate(T newValue) {
    if (value != newValue) {
      value = newValue;
    }
  }
}
