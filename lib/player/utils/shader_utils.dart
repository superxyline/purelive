import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Anime4K 超分 shader 管理：assets/shaders 下的 glsl 在首次使用时
/// 拷贝到应用目录（mpv 需要文件系统绝对路径），并提供各档位的组合顺序。
/// shader 文件来自 Anime4K 项目（MIT License）。
class ShaderUtils {
  ShaderUtils._();

  static const String _assetDir = 'assets/shaders';

  /// 质量优先档（画质最好，GPU 负载最高）
  static const List<String> _qualityShaders = [
    'Anime4K_Clamp_Highlights.glsl',
    'Anime4K_Restore_CNN_VL.glsl',
    'Anime4K_Upscale_CNN_x2_VL.glsl',
    'Anime4K_AutoDownscalePre_x2.glsl',
    'Anime4K_AutoDownscalePre_x4.glsl',
    'Anime4K_Upscale_CNN_x2_M.glsl',
  ];

  /// 效率优先档（画质与性能平衡）
  static const List<String> _efficiencyShaders = [
    'Anime4K_Clamp_Highlights.glsl',
    'Anime4K_Restore_CNN_M.glsl',
    'Anime4K_Restore_CNN_S.glsl',
    'Anime4K_Upscale_CNN_x2_M.glsl',
    'Anime4K_AutoDownscalePre_x2.glsl',
    'Anime4K_AutoDownscalePre_x4.glsl',
    'Anime4K_Upscale_CNN_x2_S.glsl',
  ];

  static Directory? _cacheDir;

  /// 返回 [mode]（efficiency/quality）下 shader 的绝对路径列表；
  /// 拷贝失败返回 null。文件每次覆盖写入，升级 shader 版本无需清理。
  static Future<List<String>?> shaderPathsFor(String mode) async {
    try {
      final names = mode == 'quality' ? _qualityShaders : _efficiencyShaders;
      final dir = await _ensureDirectory();
      final paths = <String>[];
      for (final name in names) {
        final file = File('${dir.path}${Platform.pathSeparator}$name');
        if (!file.existsSync()) {
          final data = await rootBundle.load('$_assetDir/$name');
          await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
        }
        paths.add(file.path);
      }
      return paths;
    } catch (_) {
      return null;
    }
  }

  static Future<Directory> _ensureDirectory() async {
    if (_cacheDir != null && _cacheDir!.existsSync()) return _cacheDir!;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}anime_shaders');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return _cacheDir = dir;
  }

  /// mpv change-list glsl-shaders 的路径分隔符：Windows 用 ';'，其余用 ':'
  static String get listSeparator => Platform.isWindows ? ';' : ':';
}
