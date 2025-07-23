import 'dart:io';
import 'dart:convert';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;
import 'package:pure_live/modules/web_dav/webdav_service.dart';
import 'package:pure_live/modules/web_dav/webdav_config.dart' show WebDAVConfig;

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
  final String _mainConfigFile = 'config.json';
  final String _configDir = 'conf.d';

  @override
  void onInit() {
    super.onInit();
    loadConfigs().then((loadedConfigs) {
      configs.assignAll(loadedConfigs);
      if (configs.isNotEmpty) {
        loadCurrentConfig().then((config) {
          currentConfig.value = config;
          initializeWebDAV();
        });
      } else {
        isLoading.value = false;
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

  Future<List<WebDAVConfig>> loadConfigs() async {
    try {
      final appDocDir = await getApplicationSupportDirectory();
      final configDir = Directory('${appDocDir.path}/$_configDir');

      if (!configDir.existsSync()) {
        configDir.createSync(recursive: true);
        return [];
      }

      final configFiles = configDir
          .listSync()
          .where((entity) => entity is File && entity.path.endsWith('.json'))
          .map((entity) => File(entity.path))
          .toList();

      final List<WebDAVConfig> loadedConfigs = [];
      for (final file in configFiles) {
        final configJson = jsonDecode(file.readAsStringSync());
        final configName = file.path.split('/').last.replaceAll('.json', '');
        loadedConfigs.add(WebDAVConfig.fromJson(configName, configJson));
      }
      return loadedConfigs;
    } catch (e) {
      errorMessage.value = '加载配置失败: $e';
      return [];
    }
  }

  Future<WebDAVConfig?> loadCurrentConfig() async {
    final appDocDir = await getApplicationSupportDirectory();
    final mainConfigFile = File('${appDocDir.path}/$_mainConfigFile');

    if (!mainConfigFile.existsSync()) {
      return configs.isNotEmpty ? configs.first : null;
    }

    final configName = jsonDecode(mainConfigFile.readAsStringSync())['current_config'];
    return configs.firstWhereOrNull((config) => config.name == configName);
  }

  Future<void> saveCurrentConfig(String configName) async {
    final appDocDir = await getApplicationSupportDirectory();
    final mainConfigFile = File('${appDocDir.path}/$_mainConfigFile');
    await mainConfigFile.writeAsString(jsonEncode({'current_config': configName}));
  }

  Future<void> saveConfig(WebDAVConfig config) async {
    final appDocDir = await getApplicationSupportDirectory();
    final configDir = Directory('${appDocDir.path}/$_configDir');
    if (!configDir.existsSync()) {
      configDir.createSync(recursive: true);
    }

    final configFile = File('${configDir.path}/${config.name}.json');
    configFile.writeAsStringSync(jsonEncode(config.toJson()));
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
      Get.showSnackbar(const GetSnackBar(message: '已经是根目录', duration: Duration(seconds: 1)));
    }
  }

  void deleteConfig(WebDAVConfig config) async {
    final appDocDir = await getApplicationSupportDirectory();
    final configFile = File('${appDocDir.path}/$_configDir/${config.name}.json');

    if (configFile.existsSync()) {
      configFile.deleteSync();
    }

    configs.removeWhere((c) => c.name == config.name);
    if (currentConfig.value?.name == config.name) {
      currentConfig.value = null;
      dirPath.value = '/';
      if (configs.isNotEmpty) {
        await saveCurrentConfig('');
      }
      initializeWebDAV();
    }
    Get.back(); // 关闭对话框
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
    Get.back(); // 关闭抽屉
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
}
