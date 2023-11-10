import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:date_format/date_format.dart' hide S;
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/core/iptv/iptv_utils.dart';
import 'package:pure_live/modules/auth/utils/constants.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({Key? key}) : super(key: key);

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  final settings = Get.find<SettingsService>();
  late String backupDirectory = settings.backupDirectory.value;
  late String m3uDirectory = settings.m3uDirectory.value;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        children: [
          SectionTitle(title: S.of(context).backup_recover),
          ListTile(
            title: const Text('网络电视'),
            subtitle: const Text('导入M3u直播源'),
            onTap: () => showImportSetDialog(),
          ),
          ListTile(
            title: Text(S.of(context).create_backup),
            subtitle: Text(S.of(context).create_backup_subtitle),
            onTap: () => createBackup(),
          ),
          ListTile(
            title: Text(S.of(context).recover_backup),
            subtitle: Text(S.of(context).recover_backup_subtitle),
            onTap: () => recoverBackup(),
          ),
          SectionTitle(title: S.of(context).auto_backup),
          ListTile(
            title: Text(S.of(context).backup_directory),
            subtitle: Text(backupDirectory),
            onTap: () => selectBackupDirectory(),
          ),
        ],
      ),
    );
  }

  Future<bool> requestStoragePermission() async {
    if (await Permission.manageExternalStorage.isDenied) {
      final status = Permission.manageExternalStorage.request();
      return status.isGranted;
    }
    return true;
  }

  void showImportSetDialog() {
    List<String> list = ["本地导入", "网络导入"];
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return SimpleDialog(
          title: const Text('导入M3u直播源'),
          children: list.map<Widget>((name) {
            return RadioListTile<String>(
              activeColor: Theme.of(context).colorScheme.primary,
              groupValue: '',
              value: name,
              title: Text(name),
              onChanged: (value) {
                importFile(value!);
              },
            );
          }).toList(),
        );
      },
    );
  }

  ///验证URL
  bool isUrl(String value) {
    final urlRegExp = RegExp(
        r"((https?:www\.)|(https?:\/\/)|(www\.))[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9]{1,6}(\/[-a-zA-Z0-9()@:%_\+.~#?&\/=]*)?");
    List<String?> urlMatches =
        urlRegExp.allMatches(value).map((m) => m.group(0)).toList();
    return urlMatches.isNotEmpty;
  }

  Future<String?> showEditTextDialog() async {
    final TextEditingController urlEditingController = TextEditingController();
    final TextEditingController textEditingController = TextEditingController();
    var result = await Get.dialog(
        AlertDialog(
          title: const Text('请输入下载地址'),
          content: SizedBox(
            width: 400.0,
            height: 300.0,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                children: [
                  TextField(
                    controller: urlEditingController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      //prefixText: title,
                      contentPadding: EdgeInsets.all(12),
                      hintText: '下载地址',
                    ),
                    autofocus: true,
                  ),
                  spacer(12.0),
                  TextField(
                    controller: textEditingController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      //prefixText: title,
                      contentPadding: EdgeInsets.all(12),
                      hintText: '文件名',
                    ),
                    autofocus: false,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: Get.back,
              child: const Text("取消"),
            ),
            TextButton(
              onPressed: () {
                if (urlEditingController.text.isEmpty) {
                  SmartDialog.showToast('请输入下载链接');
                  return;
                }
                bool validate = isUrl(urlEditingController.text);
                if (!validate) {
                  SmartDialog.showToast('请输入正确的下载链接');
                  return;
                }
                if (textEditingController.text.isEmpty) {
                  SmartDialog.showToast('请输入文件名');
                  return;
                }
                recoverNetworkM3u8Backup(
                    urlEditingController.text, textEditingController.text);
              },
              child: const Text("确定"),
            ),
          ],
        ),
        barrierDismissible: false);
    return result;
  }

  importFile(String value) {
    if (value == '本地导入') {
      recoverM3u8Backup();
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pop(false);
      showEditTextDialog();
      // recoverNetworkM3u8Backup();
    }
  }

  recoverNetworkM3u8Backup(String url, String fileName) async {
    Dio dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      //响应时间为3秒
      receiveTimeout: const Duration(seconds: 10),
    ));
    var dir = await getApplicationDocumentsDirectory();
    final m3ufile = File("${dir.path}/$fileName.m3u");
    try {
      await dio.download(url, m3ufile.path);
      List jsonArr = [];
      final categories = File('${dir.path}/categories.json');
      String jsonData = await categories.readAsString();
      jsonArr = jsonData.isNotEmpty ? jsonDecode(jsonData) : [];
      List<IptvCategory> categoriesArr =
          jsonArr.map((e) => IptvCategory.fromJson(e)).toList();

      if (!categories.existsSync()) {
        categories.createSync();
      }
      bool isNotExit = categoriesArr.indexWhere((element) => element.id == url) == -1 ;
      if (isNotExit) {
        categoriesArr.add(IptvCategory(
            id: url,
            name: getName(m3ufile.path).replaceAll(RegExp(r'.m3u'), ''),
            path: m3ufile.path));
      }else{
        var index = categoriesArr.indexWhere((element) => element.id == url);
        categoriesArr[index].name = fileName;
      }

      categories.writeAsStringSync(
          jsonEncode(categoriesArr.map((e) => e.toJson()).toList()));
      SnackBarUtil.success(S.of(Get.context!).recover_backup_success);
    } catch (e) {
      SnackBarUtil.error(S.of(Get.context!).recover_backup_failed);
    }
    Get.back();
  }

  String getName(String fullName) {
    return fullName.split('/').last;
  }

  String getUUid() {
    var currentTime = DateTime.now().millisecondsSinceEpoch;
    var randomValue = Random().nextInt(4294967295);
    var result = (currentTime % 10000000000 * 1000 + randomValue) % 4294967295;
    return result.toString();
  }

  void recoverM3u8Backup() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      dialogTitle: S.of(context).select_recover_file,
      type: FileType.custom,
      allowedExtensions: ['m3u'],
    );
    if (result == null || result.files.single.path == null) return;

    try {
      final file = File(result.files.single.path!);
      var dir = await getApplicationDocumentsDirectory();
      final m3ufile = File('${dir.path}/${getName(file.path)}');
      List jsonArr = [];
      final categories = File('${dir.path}/categories.json');
      String jsonData = await categories.readAsString();
      jsonArr = jsonData.isNotEmpty ? jsonDecode(jsonData) : [];
      List<IptvCategory> categoriesArr =
          jsonArr.map((e) => IptvCategory.fromJson(e)).toList();

      if (!categories.existsSync()) {
        categories.createSync();
      }
      if (categoriesArr.indexWhere((element) => element.path == m3ufile.path) ==
          -1) {
        categoriesArr.add(IptvCategory(
            id: getUUid(),
            name: getName(m3ufile.path).replaceAll(RegExp(r'.m3u'), ''),
            path: m3ufile.path));
      }

      categories.writeAsStringSync(
          jsonEncode(categoriesArr.map((e) => e.toJson()).toList()));
      file.copySync(m3ufile.path);
      SnackBarUtil.success(S.of(Get.context!).recover_backup_success);
    } catch (e) {
      SnackBarUtil.error(S.of(Get.context!).recover_backup_failed);
    }
  }

  void createBackup() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final granted = await requestStoragePermission();
      if (!granted) {
        SnackBarUtil.error('请先授予读写文件权限');
        return;
      }
    }

    String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
      initialDirectory: backupDirectory.isEmpty ? '/' : backupDirectory,
    );
    if (selectedDirectory == null) return;

    final dateStr = formatDate(
      DateTime.now(),
      [yyyy, '-', mm, '-', dd, 'T', HH, '_', nn, '_', ss],
    );
    final file = File('$selectedDirectory/purelive_$dateStr.txt');
    if (settings.backup(file)) {
      SnackBarUtil.success(S.of(Get.context!).create_backup_success);
      // 首次同步备份目录
      if (settings.backupDirectory.isEmpty) {
        settings.backupDirectory.value = selectedDirectory;
        setState(() => backupDirectory = selectedDirectory);
      }
    } else {
      SnackBarUtil.error(S.of(Get.context!).create_backup_failed);
    }
  }

  void recoverBackup() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      dialogTitle: S.of(context).select_recover_file,
      type: FileType.custom,
      allowedExtensions: ['txt'],
    );
    if (result == null || result.files.single.path == null) return;

    final file = File(result.files.single.path!);
    if (settings.recover(file)) {
      SnackBarUtil.success(S.of(Get.context!).recover_backup_success);
    } else {
      SnackBarUtil.error(S.of(Get.context!).recover_backup_failed);
    }
  }

  void selectBackupDirectory() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory == null) return;

    settings.backupDirectory.value = selectedDirectory;
    setState(() => backupDirectory = selectedDirectory);
  }
}
