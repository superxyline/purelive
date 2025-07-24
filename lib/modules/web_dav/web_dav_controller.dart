import 'dart:convert';
import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';
import 'package:date_format/date_format.dart';
import 'package:pure_live/plugins/utils.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;
import 'package:pure_live/modules/web_dav/webdav_config.dart';
import 'package:pure_live/modules/web_dav/webdav_service.dart';

class WebDavController extends GetxController {
  final RxList<WebDAVConfig> configs = <WebDAVConfig>[].obs;
  final Rx<WebDAVConfig?> currentConfig = Rx<WebDAVConfig?>(null);
  final RxList<webdav.File> files = <webdav.File>[].obs;
  final RxBool isLoading = true.obs;
  final RxString errorMessage = ''.obs;
  final RxString dirPath = '/'.obs;
  final RxList<String> breadcrumbParts = <String>[].obs;
  final RxBool isFromBreadcrumb = false.obs;

  late WebDAVService _webdavService;
  final SettingsService _settingsService = Get.find<SettingsService>();
  @override
  void onInit() {
    super.onInit();
    configs.assignAll(_settingsService.webDavConfigs);
    if (_settingsService.currentWebDavConfig.value.isNotEmpty) {
      currentConfig.value = WebDAVConfig.fromJson(jsonDecode(_settingsService.currentWebDavConfig.value));
      initializeWebDAV();
    }
    configs.listen((e) {
      _settingsService.webDavConfigs.assignAll(configs);
    });
    currentConfig.listen((e) {
      if (e != null) {
        _settingsService.currentWebDavConfig.value = jsonEncode(e.toJson());
      } else {
        _settingsService.currentWebDavConfig.value = '';
      }
    });
  }

  void initializeWebDAV() {
    if (currentConfig.value != null) {
      _webdavService = WebDAVService(
        url: currentConfig.value!.fullUrl,
        username: currentConfig.value!.username,
        password: currentConfig.value!.password,
      );
      loadFiles();
    }
  }

  Future<void> saveCurrentConfig(String configName) async {
    _settingsService.currentWebDavConfig.value = jsonEncode(currentConfig.value!.toJson());
  }

  Future<void> loadFiles() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final loadedFiles = await _webdavService.readDirectory(dirPath.value);
      files.assignAll(loadedFiles);
      isLoading.value = false;
    } catch (e) {
      isLoading.value = false;
      errorMessage.value = '无法加载目录: $e';
      Get.showSnackbar(
        GetSnackBar(message: '加载失败: $e', duration: Duration(seconds: 2), backgroundColor: Get.theme.colorScheme.error),
      );
    }
  }

  String buildPath(String fileName) {
    final cleanPath = dirPath.value.replaceAll(RegExp(r'/+'), '/');
    return cleanPath.endsWith('/') ? '$cleanPath$fileName/' : '$cleanPath/$fileName/';
  }

  void goToParentDirectory() {
    if (dirPath.value != '/') {
      final cleanPath = dirPath.value.endsWith('/')
          ? dirPath.value.substring(0, dirPath.value.length - 1)
          : dirPath.value;
      final newPath = cleanPath.substring(0, cleanPath.lastIndexOf('/') + 1);
      dirPath.value = newPath.isEmpty ? '/' : newPath;
      isFromBreadcrumb.value = true;
      triggerBreadcrumbScroll();
      loadFiles();
    } else {
      Navigator.pop(Get.context!); // 关闭抽屉
    }
  }

  void deleteConfig(WebDAVConfig config) async {
    configs.removeWhere((c) => c.name == config.name);
    if (currentConfig.value?.name == config.name) {
      currentConfig.value = null;
      dirPath.value = '/';
      if (configs.isNotEmpty) {
        await saveCurrentConfig('');
      }
      initializeWebDAV();
    }
    Navigator.pop(Get.context!); // 关闭抽屉
  }

  void rebuildBreadcrumb() {
    final cleanPath = dirPath.value.replaceAll(RegExp(r'/+'), '/').replaceAll(RegExp(r'^/|/$'), '');
    breadcrumbParts.assignAll(cleanPath.split('/'));

    if (dirPath.value == '/' || cleanPath.isEmpty) {
      breadcrumbParts.clear();
    }
  }

  void updateBreadcrumbParts() {
    if (!isFromBreadcrumb.value) {
      String path = dirPath.value;
      if (path.startsWith('/')) path = path.substring(1);
      if (path.endsWith('/')) path = path.substring(0, path.length - 1);
      breadcrumbParts.assignAll(path.isEmpty ? [] : path.split('/'));
    }
  }

  void triggerBreadcrumbScroll() {
    // 面包屑滚动逻辑保持不变（UI层实现）
  }

  void onConfigSelected(WebDAVConfig config) {
    currentConfig.value = config;
    dirPath.value = '/';
    breadcrumbParts.clear();
    saveCurrentConfig(config.name);
    initializeWebDAV();
    rebuildBreadcrumb();
    Navigator.pop(Get.context!);
  }

  void onFileTap(webdav.File file) {
    if (file.isDir ?? false) {
      final newPath = buildPath(file.name!);
      dirPath.value = newPath;
      isFromBreadcrumb.value = false;
      updateBreadcrumbParts();
      triggerBreadcrumbScroll();
      loadFiles();
    }
  }

  void uploadConfigSettings() async {
    try {
      // 1. 生成文件名（包含当前时间戳，避免重复）

      final dateStr = formatDate(DateTime.now(), [yyyy, '-', mm, '-', dd, 'T', HH, '_', nn, '_', ss]);
      final fileName = 'purelive_$dateStr.txt';
      // 2. 准备要上传的文件内容（这里假设是配置数据，根据实际需求替换）
      // 示例：将某个配置对象转换为 JSON 字符串
      final settingConfigs = _settingsService.toJson();
      final fileContent = jsonEncode(settingConfigs); // 转换为 JSON 字符串
      final dataBytes = utf8.encode(fileContent); // 转换为字节数据（WebDAV 通常需要字节流）

      // 3. 定义 WebDAV 服务器上的完整路径（例如上传到根目录下）
      String remoteFilePath = '${dirPath.value}$fileName'; // 注意路径格式，根据服务器要求调整
      if (dirPath.value == '/') {
        SnackBarUtil.error('请先选择配置目录');
        return;
      }
      // 4. 调用 WebDAV 客户端上传（假设 _webdavService.client 已初始化）
      await _webdavService.client.write(
        remoteFilePath, // 服务器上的路径
        dataBytes, // 要上传的字节数据
      );

      // 5. 上传成功提示
      SnackBarUtil.success('文件上传成功');
      // 6. 刷新当前目录文件列表
      loadFiles();
    } catch (e) {
      // 6. 处理错误（如网络异常、权限不足等）
      debugPrint('文件上传失败: $e');
      SnackBarUtil.error('文件上传失败: $e');
    }
  }

  void deleteFile(webdav.File file) async {
    var result = await Utils.showAlertDialog("确定要删除吗？", title: "删除");
    if (result) {
      try {
        _webdavService.client.remove(file.path!);
        loadFiles();
        SnackBarUtil.success('文件删除成功');
      } catch (e) {
        SnackBarUtil.error('文件删除失败: $e');
      }
    }
  }

  void downloadFile(webdav.File file) async {
    try {
      final bytes = await _webdavService.client.read(file.path!);
      _settingsService.fromJson(jsonDecode(utf8.decode(bytes)));
      SnackBarUtil.success('同步成功');
    } catch (e) {
      SnackBarUtil.error('文件下载失败: $e');
    }
  }
}
