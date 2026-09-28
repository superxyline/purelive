// 设置搜索索引生成器。
//
// 扫描设置页源码中条目的 `title: i18n('key')`（兼容 `title: Text(i18n('key'))`）
// 与页面 AppBar 标题，生成 settings_search_index.g.dart。
// 新增设置页/设置项后无需手工维护搜索索引——重新运行本脚本即可：
//
//   dart tool/gen_settings_index.dart
//
// （构建流程中应先执行本脚本，见 HANDOFF。）
import 'dart:io';

const List<String> scanDirs = [
  'lib/modules/settings/pages',
];

/// 散落在其他目录的设置页（白名单）。
const List<String> scanFiles = [
  'lib/modules/live_play/widgets/danmaku_settings_page.dart',
  'lib/modules/live_play/widgets/keyword_block_page.dart',
];

const String outPath = 'lib/modules/settings/pages/settings_search_index.g.dart';
const String packagePrefix = 'package:pure_live/';

/// title: i18n('x') / title: Text(i18n('x')) / title: Text(i18n('x'), style: ...)
final _titleEntryRe = RegExp(
    r'''title:\s*(?:const\s+)?(?:Text\(\s*)?i18n\(\s*['"]([A-Za-z0-9_]+)['"]''');
/// 页面主类：StatelessWidget / StatefulWidget / GetView<T>
final _classRe = RegExp(r'class\s+(\w+)\s+extends\s+(?:State(?:less|ful)Widget|GetView<[^>]+>)');
/// AppBar 标题：AppBar(title: Text(i18n('key'))) 或 AppBar(title: Text('字面量'))
final _appBarKeyRe =
    RegExp(r'''AppBar\(\s*title:\s*Text\(\s*i18n\(\s*['"]([A-Za-z0-9_]+)['"]''');
final _appBarLiteralRe =
    RegExp(r'''AppBar\(\s*title:\s*Text\(\s*['"]([^'"]+)['"]''');

/// video_settings_page.dart -> VideoSettingsPage（选文件名对应的类，避免抓到页内小组件）
String _expectedClassName(String fileName) {
  final base = fileName
      .replaceAll('.dart', '')
      .split(RegExp(r'[_\-]'))
      .where((s) => s.isNotEmpty)
      .map((s) => s[0].toUpperCase() + s.substring(1))
      .join();
  return base.endsWith('Page') ? base : '${base}Page';
}

/// 页面能否被 `const Page()` 无参构造：
/// - 有显式构造器时必须 `const` 开头且无 `required` 参数
///   （如 DanmakuSettingsPage 依赖直播间 VideoController，无法从搜索直达）；
/// - 无显式构造器时隐式默认构造可 const（Dart 对全 final 字段的规则）。
bool _constNoRequired(String src, String cls) {
  final ctorRe = RegExp(r'(?:const\s+)?' + RegExp.escape(cls) + r'\s*\(');
  final m = ctorRe.firstMatch(src);
  if (m == null) return true; // 无显式构造器
  final head = src.substring(m.start, m.start + 6);
  if (!head.startsWith('const')) return false;
  // 构造参数段：到第一个 `);` 为止
  final end = src.indexOf(');', m.end);
  final params = end == -1 ? '' : src.substring(m.end, end);
  return !params.contains('required');
}

void main() {
  final dir = Directory.current.path.replaceAll('\\', '/');
  final files = <File>[];
  for (final d in scanDirs) {
    final target = Directory('$dir/$d');
    if (!target.existsSync()) continue;
    for (final f in target.listSync(recursive: false)) {
      if (f is File && f.path.endsWith('.dart')) {
        final name = f.uri.pathSegments.last;
        if (name == 'settings_search_page.dart' ||
            name == 'settings_search_index.g.dart' ||
            name == 'settings_search_entry.dart') {
          continue;
        }
        files.add(f);
      }
    }
  }
  for (final p in scanFiles) {
    final f = File('$dir/$p');
    if (f.existsSync()) files.add(f);
  }

  final entries = <_Entry>[];
  final imports = <String>[];
  final skipped = <String>[];

  for (final f in files) {
    final src = f.readAsStringSync();
    final fileName = f.uri.pathSegments.last;

    final allClasses = _classRe.allMatches(src).map((m) => m.group(1)!).toList();
    if (allClasses.isEmpty) continue;
    final expected = _expectedClassName(fileName);
    final cls = allClasses.contains(expected) ? expected : allClasses.first;
    // 页内小组件排在主类前会被误选时兜底：类名含 Page 的优先
    final pageClass = allClasses.firstWhere((c) => c.endsWith('Page'),
        orElse: () => cls);

    final titles =
        _titleEntryRe.allMatches(src).map((m) => m.group(1)!).toSet();
    if (titles.isEmpty) {
      skipped.add(fileName);
      continue;
    }
    if (!_constNoRequired(src, pageClass)) {
      skipped.add('$fileName ($pageClass 构造器含必填参数，无法从搜索直达)');
      continue;
    }

    final groupKey = _appBarKeyRe.firstMatch(src)?.group(1) ?? 'settings';

    final relPath = f.path.replaceAll('\\', '/');
    var rel = relPath.startsWith('$dir/')
        ? relPath.substring(dir.length + 1)
        : relPath;
    if (rel.startsWith('lib/')) rel = rel.substring(4); // package URI 不含 lib/
    imports.add('$packagePrefix$rel');

    for (final t in titles) {
      entries.add(_Entry(t, groupKey, pageClass));
    }
  }

  entries.sort((a, b) => a.titleKey.compareTo(b.titleKey));

  final buf = StringBuffer();
  buf.writeln('// GENERATED CODE - 由 tool/gen_settings_index.dart 生成，请勿手工编辑。');
  buf.writeln('// 重新生成：dart tool/gen_settings_index.dart');
  buf.writeln();
  buf.writeln(
      "import 'package:pure_live/modules/settings/pages/settings_search_entry.dart';");
  for (final imp in imports.toSet().toList()..sort()) {
    buf.writeln("import '$imp';");
  }
  buf.writeln();
  buf.writeln('/// 自动生成的设置搜索索引：(条目标题 i18n key, 分组 i18n key, 页面构造)。');
  buf.writeln('class GeneratedSettingsSearchIndex {');
  buf.writeln('  GeneratedSettingsSearchIndex._();');
  buf.writeln();
  buf.writeln('  static const List<SettingsSearchEntry> entries = [');
  for (final e in entries) {
    buf.writeln(
        "    SettingsSearchEntry('${e.titleKey}', '${e.groupKey}', const ${e.pageClass}()),");
  }
  buf.writeln('  ];');
  buf.writeln('}');

  File('$dir/$outPath').writeAsStringSync(buf.toString());
  stdout.writeln('生成 $outPath：${entries.length} 条，页面 ${imports.length} 个');
  if (skipped.isNotEmpty) {
    stdout.writeln('无 title 条目跳过：${skipped.join(', ')}');
  }
}

class _Entry {
  final String titleKey;
  final String groupKey;
  final String pageClass;
  _Entry(this.titleKey, this.groupKey, this.pageClass);
}
