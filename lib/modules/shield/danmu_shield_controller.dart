import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/base/base_controller.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

class DanmuShieldController extends BaseController {
  final TextEditingController textEditingController = TextEditingController();
  final SettingsService settingsController = Get.find<SettingsService>();
  void add() {
    if (textEditingController.text.isEmpty) {
      SmartDialog.showToast("请输入关键词");
      return;
    }

    settingsController.addShieldList(textEditingController.text.trim());
    textEditingController.text = "";
  }

  Color get themeColor => HexColor(settingsController.themeColorSwitch.value);
  void remove(int itemIndex) {
    settingsController.removeShieldList(itemIndex);
  }
}
