import 'package:get/get.dart';
import 'package:pure_live/core/site/huya_site.dart';
import 'package:pure_live/common/services/utils/hive_rx.dart';

class StartupController extends GetxController {
  final RxBool enableStartUp = hiveBool('enableStartUp', true);

  @override
  void onInit() {
    super.onInit();
    loadHuyaUa();
  }

  Future<void> loadHuyaUa() async {
    HuyaSite().getHuYaUA();
  }

  void enableStartup() {
    enableStartUp.v = true;
  }

  void disableStartup() {
    enableStartUp.v = false;
  }

  void toggleStartup() {
    enableStartUp.v = !enableStartUp.v;
  }

  Map<String, dynamic> toJson() {
    return {'enableStartUp': enableStartUp.v};
  }

  void fromJson(Map<String, dynamic> json) {
    enableStartUp.v = json['enableStartUp'] ?? true;
  }

  static Map<String, dynamic> extractConfig(Map<String, dynamic>? rootConfig) {
    final startup = rootConfig?['startup'] as Map<String, dynamic>? ?? {};
    return {'enableStartUp': startup['enableStartUp'] ?? true};
  }

  static Map<String, dynamic> mergeConfig(Map<String, dynamic> rootConfig, Map<String, dynamic> updateFields) {
    final startup = Map<String, dynamic>.from(rootConfig['startup'] ?? {});
    updateFields.forEach((k, v) => startup[k] = v);
    rootConfig['startup'] = startup;
    return rootConfig;
  }
}
