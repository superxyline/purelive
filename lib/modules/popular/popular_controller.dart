import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/modules/popular/popular_grid_controller.dart';

import '../../core/sites.dart';

class PopularController extends GetxController
    with GetSingleTickerProviderStateMixin {
  late TabController tabController;
  int index = 0;

  PopularController() {
    final preferPlatform = Get.find<SettingsService>().preferPlatform.value;
    final pIndex = Sites.supportSites.indexWhere((e) => e.id == preferPlatform);
    tabController = TabController(
      initialIndex: pIndex == -1 ? 0 : pIndex,
      length: Sites.supportSites.length,
      vsync: this,
    );
    index = pIndex == -1 ? 0 : pIndex;

    tabController.animation?.addListener(() {
      var currentIndex = (tabController.animation?.value ?? 0).round();
      if (index == currentIndex) {
        return;
      }

      index = currentIndex;
      var controller =
          Get.find<PopularGridController>(tag: Sites.supportSites[index].id);

      if (controller.list.isEmpty) {
        controller.loadData();
      }
    });
  }

  @override
  void onInit() {
    for (var site in Sites.supportSites) {
      var controller = Get.put(PopularGridController(site), tag: site.id);
      if (controller.list.isEmpty) {
        controller.loadData();
      }
    }
    super.onInit();
  }
}
