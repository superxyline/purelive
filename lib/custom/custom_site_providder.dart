import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';

// 注册时模拟表
class CustomSiteProvider {
  CustomSiteProvider._();
  static final CustomSiteProvider instance = CustomSiteProvider._();
  final SettingsService service = Get.find<SettingsService>();

  bool inset(SiteInfoMation siteInfoMation) {
    var exits = service.addCustomSites(siteInfoMation);
    if (!exits) {
      SmartDialog.showToast('${siteInfoMation.siteTitle}已存在');
    }
    return exits;
  }

  bool updateCustomSites(SiteInfoMation siteInfoMation) {
    var updateRes = service.updateCustomSites(siteInfoMation);

    if (!updateRes) {
      SmartDialog.showToast('修改失败');
    }
    return updateRes;
  }

  List<SiteInfoMation> querySite() {
    return service.customSites.value;
  }

  deleteMusicWithIndex(int index) {
    service.removeCustomSites(index);
  }
}

class SiteInfoMation {
  final String id;
  final String siteTitle;
  final String siteIsHot;
  final String siteUrl;
  String? siteCover;
  SiteInfoMation(
      {required this.id, required this.siteTitle, required this.siteUrl, required this.siteIsHot, this.siteCover});

  factory SiteInfoMation.fromJson(Map<String, dynamic> json) => SiteInfoMation(
        id: json['id'],
        siteTitle: json['site_title'],
        siteUrl: json['site_url'],
        siteIsHot: json['site_is_hot'].toString(),
        siteCover: json['site_cover'],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'site_title': siteTitle,
        'site_url': siteUrl,
        'site_is_hot': siteIsHot.toString(),
        'site_cover': siteCover
      };
}
