import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';

class AreasController extends GetxController
    with GetSingleTickerProviderStateMixin {
  late TabController tabController;

  AreasController() {
    final preferPlatform = Get.find<SettingsService>().preferPlatform.value;
    final index = Sites.supportSites.indexWhere((e) => e.id == preferPlatform);
    tabController = TabController(
      initialIndex: index == -1 ? 0 : index,
      length: Sites.supportSites.length,
      vsync: this,
    );
  }

  Map<String, Map> data = {};

  @override
  void onInit() async {
    for (var site in Sites.supportSites) {
      var areas = await site.liveSite.getAreaList();
      var lables = areas.map<String>((e) => e.first.typeName).toList();
      data[site.id] = {
        'labels': lables,
        'areas': areas,
      };
    }
    super.onInit();
  }
}
