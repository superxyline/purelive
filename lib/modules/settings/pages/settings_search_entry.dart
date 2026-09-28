import 'package:flutter/widgets.dart';

/// 搜索索引条目：条目标题 i18n key、所属页面标题 i18n key、跳转页面构造。
/// 索引列表由 tool/gen_settings_index.dart 从设置页源码自动生成
/// （见 settings_search_index.g.dart），新增设置项无需手工登记。
class SettingsSearchEntry {
  final String titleKey;
  final String groupKey;
  final Widget page;

  const SettingsSearchEntry(this.titleKey, this.groupKey, this.page);
}
