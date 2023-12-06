import 'dart:io';
import 'package:get/get.dart';
import 'areas_grid_view.dart';
import 'favorite_areas_page.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/plugins/file_recover_utils.dart';
import 'package:pure_live/custom/custom_site_providder.dart';
import 'package:pure_live/modules/auth/utils/constants.dart';
import 'package:pure_live/modules/areas/areas_list_controller.dart';
import 'package:pure_live/modules/popular/popular_grid_controller.dart';

class AreasPage extends GetView<AreasController> {
  const AreasPage({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraint) {
      bool showAction = constraint.maxWidth <= 680;
      return Scaffold(
        appBar: AppBar(
          centerTitle: true,
          scrolledUnderElevation: 0,
          leading: showAction ? const MenuButton() : null,
          actions: showAction ? [const SearchButton()] : null,
          title: TabBar(
            controller: controller.tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.center,
            labelStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            labelPadding: const EdgeInsets.symmetric(horizontal: 12),
            indicatorSize: TabBarIndicatorSize.label,
            tabs: Sites().availableSites().map((e) => Tab(text: e.name)).toList(),
          ),
        ),
        body: TabBarView(
          controller: controller.tabController,
          children: Sites().availableSites().map((e) => AreaGridView(e.id)).toList(),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        floatingActionButton: Obx(() => FloatingActionButton(
              onPressed: () {
                if (controller.isCustomSite.value == false) {
                  Get.to(() => const FavoriteAreasPage());
                } else {
                  showWebviewDialog();
                }
              },
              child: Icon(controller.isCustomSite.value == false ? Icons.favorite_rounded : Icons.add),
            )),
      );
    });
  }

  Future<String?> showWebviewDialog() async {
    final TextEditingController textEditingController = TextEditingController();
    final TextEditingController urlEditingController = TextEditingController();
    urlEditingController.text = 'http://';
    final isHotSite = false.obs;
    var result = await Get.dialog(
        AlertDialog(
          title: const Text('添加站点信息'),
          content: SizedBox(
            width: Platform.isAndroid
                ? MediaQuery.of(Get.context!).size.width
                : MediaQuery.of(Get.context!).size.width * 0.6,
            height: 540.0,
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  children: [
                    TextField(
                      controller: textEditingController,
                      keyboardType: TextInputType.text,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.all(12),
                        hintText: '站点名称',
                      ),
                    ),
                    spacer(20.0),
                    TextField(
                      controller: urlEditingController,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.all(12),
                        hintText: '站点地址',
                      ),
                    ),
                    spacer(20.0),
                    Obx(() => SwitchListTile(
                          title: const Text('是否设置为热门'),
                          value: isHotSite.value,
                          activeColor: Theme.of(Get.context!).colorScheme.primary,
                          onChanged: (bool value) {
                            isHotSite.value = value;
                          },
                        ))
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                if (textEditingController.text.isEmpty) {
                  SmartDialog.showToast('请输入站点名称');
                  return;
                }
                if (urlEditingController.text.isEmpty) {
                  SmartDialog.showToast('请输入站点地址');
                  return;
                }
                if (!FileRecoverUtils.isHostUrl(urlEditingController.text)) {
                  SmartDialog.showToast('请输入正确的站点地址,以http://或https://开头');
                  return;
                }
                var res = CustomSiteProvider.instance.inset(SiteInfoMation(
                  id: FileRecoverUtils.getUUid(),
                  siteTitle: textEditingController.text,
                  siteUrl: urlEditingController.text,
                  siteIsHot: isHotSite.value ? '1' : '0',
                ));
                if (res) {
                  await refresh();
                  SmartDialog.showToast('添加成功');
                  Get.back();
                }
              },
              child: const Text("确定"),
            ),
            TextButton(
              onPressed: Get.back,
              child: const Text("取消添加"),
            ),
          ],
        ),
        barrierDismissible: false);
    return result;
  }

  refresh() {
    var controller = Get.find<AreasListController>(tag: 'custom');
    var popularController = Get.find<PopularGridController>(tag: 'custom');
    controller.refreshData();
    popularController.refreshData();
  }
}
