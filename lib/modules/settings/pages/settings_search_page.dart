import 'package:remixicon/remixicon.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/settings/pages/settings_search_entry.dart';
import 'package:pure_live/modules/settings/pages/settings_search_index.g.dart';

/// 设置项全局搜索：按标题/所属页面过滤，点击直达对应设置页。
/// 索引来自 settings_search_index.g.dart（自动生成）。
class SettingsSearchPage extends StatefulWidget {
  const SettingsSearchPage({super.key});

  @override
  State<SettingsSearchPage> createState() => _SettingsSearchPageState();
}

class _SettingsSearchPageState extends State<SettingsSearchPage> {
  String _keyword = '';

  List<SettingsSearchEntry> get _filtered {
    final keyword = _keyword.trim().toLowerCase();
    if (keyword.isEmpty) return GeneratedSettingsSearchIndex.entries;
    return GeneratedSettingsSearchIndex.entries.where((entry) {
      final title = i18n(entry.titleKey).toLowerCase();
      final group = i18n(entry.groupKey).toLowerCase();
      return title.contains(keyword) || group.contains(keyword);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = _filtered;
    return Scaffold(
      appBar: AppBar(title: Text(i18n('settings_search'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              autofocus: true,
              onChanged: (value) => setState(() => _keyword = value),
              decoration: InputDecoration(
                hintText: i18n('settings_search_hint'),
                prefixIcon: const Icon(Remix.search_line, size: 20),
                isDense: true,
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerLow,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          Expanded(
            child: results.isEmpty
                ? Center(
                    child: Text(
                      i18n('settings_search_empty'),
                      style: AppTextStyles.t14.copyWith(color: theme.hintColor),
                    ),
                  )
                : ListView.builder(
                    physics: const PureLiveScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    itemCount: results.length,
                    itemBuilder: (context, index) {
                      final entry = results[index];
                      return ListTile(
                        leading: Icon(
                          Remix.settings_4_line,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        title: Text(i18n(entry.titleKey)),
                        subtitle: Text(
                          i18n(entry.groupKey),
                          style: AppTextStyles.t12.copyWith(color: theme.hintColor),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        dense: true,
                        onTap: () => Get.to(() => entry.page),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
