import 'dart:io';
import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/routes/app_navigation.dart';
import 'package:pure_live/plugins/file_recover_utils.dart';
import 'package:pure_live/modules/auth/utils/constants.dart';
import 'package:pure_live/custom/custom_site_providder.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:pure_live/modules/areas/areas_list_controller.dart';
import 'package:pure_live/modules/popular/popular_grid_controller.dart';

class AreaCard extends StatefulWidget {
  const AreaCard({super.key, required this.category});
  final LiveArea category;

  @override
  State<AreaCard> createState() => _AreaCardState();
}

// id: widget.category.areaId!, siteTitle: widget.category.areaName!, siteUrl: widget.category.areaType!, siteIsHot: 0)
class _AreaCardState extends State<AreaCard> {
  Future<String?> showWebviewEditDialog() async {
    final TextEditingController textEditingController = TextEditingController();
    final TextEditingController urlEditingController = TextEditingController();
    textEditingController.text = widget.category.areaName!;
    urlEditingController.text = widget.category.areaType!;
    final isHotSite = (widget.category.shortName == '1').obs;
    var result = await Get.dialog(
        AlertDialog(
          title: const Text('编辑站点信息'),
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
                if (!FileRecoverUtils.isUrl(urlEditingController.text)) {
                  SmartDialog.showToast('请输入正确的站点地址');
                  return;
                }
                var res = CustomSiteProvider.instance.updateCustomSites(SiteInfoMation(
                  id: widget.category.areaId!,
                  siteTitle: textEditingController.text,
                  siteUrl: urlEditingController.text,
                  siteIsHot: isHotSite.value ? '1' : '0',
                ));
                if (res) {
                  refresh();
                  SmartDialog.showToast('编辑成功');
                  Get.back();
                }
              },
              child: const Text("确定"),
            ),
            TextButton(
              onPressed: () {
                deleteSite();
              },
              child: const Text("删除"),
            ),
            TextButton(
              onPressed: Get.back,
              child: const Text("关闭"),
            ),
          ],
        ),
        barrierDismissible: false);
    return result;
  }

  deleteSite() async {
    var index = CustomSiteProvider.instance.service.customSites
        .indexWhere((SiteInfoMation element) => element.id.toString() == widget.category.areaId!);

    CustomSiteProvider.instance.service.removeCustomSites(index);
    SmartDialog.showToast('删除成功');
    refresh();
    Get.back();
  }

  refresh() {
    var controller = Get.find<AreasListController>(tag: 'custom');
    var popularController = Get.find<PopularGridController>(tag: 'custom');
    controller.refreshData();
    popularController.refreshData();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(7.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15.0),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(15.0),
        onLongPress: () {
          if (widget.category.platform == 'custom') {
            showWebviewEditDialog();
          }
        },
        onTap: () {
          if (widget.category.platform == 'iptv') {
            var roomItem = LiveRoom(
              roomId: widget.category.areaId,
              title: widget.category.typeName,
              cover: '',
              nick: widget.category.areaName,
              watching: '',
              avatar:
                  'https://img95.699pic.com/xsj/0q/x6/7p.jpg%21/fw/700/watermark/url/L3hzai93YXRlcl9kZXRhaWwyLnBuZw/align/southeast',
              area: '',
              liveStatus: LiveStatus.live,
              status: true,
              platform: 'iptv',
            );
            AppNavigator.toLiveRoomDetail(liveRoom: roomItem);
          } else if (widget.category.platform == 'custom') {
            AppNavigator.toWebViewPage(
                site: SiteInfoMation(
              id: widget.category.areaId!,
              siteTitle: widget.category.areaName!,
              siteUrl: widget.category.areaType!,
              siteIsHot: widget.category.shortName!,
            ));
          } else {
            AppNavigator.toCategoryDetail(site: Sites.of(widget.category.platform!), category: widget.category);
          }
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Card(
                margin: const EdgeInsets.all(0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15.0),
                ),
                clipBehavior: Clip.antiAlias,
                color: Colors.white,
                elevation: 0,
                child: CachedNetworkImage(
                  imageUrl: widget.category.areaPic!,
                  cacheManager: CustomCacheManager.instance,
                  fit: BoxFit.fill,
                  errorWidget: (context, error, stackTrace) => const Center(
                    child: Icon(
                      Icons.live_tv_rounded,
                      size: 38,
                    ),
                  ),
                ),
              ),
            ),
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10),
              title: Text(
                widget.category.areaName!,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Text(
                    widget.category.typeName!,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
