import 'package:pure_live/common/index.dart';
import 'package:pure_live/core/site/bilibili_shield.dart';
import 'package:pure_live/core/site/bilibili_site.dart';

/// B 站官方弹幕屏蔽管理页（云端直同步语义）。
///
/// 本页展示的是 B 站账号的云端屏蔽列表快照：
/// - 添加关键词 = 直接调用 AddShieldKeyword 上传云端，成功后并入本地快照；
/// - 删除关键词 = 直接调用 DelShieldKeyword 删除云端，成功后移出本地快照；
/// - 屏蔽用户列表只读（shield_user 接口必须带直播间 roomid，只能在直播间内发起）。
class OfficialShieldPage extends StatefulWidget {
  const OfficialShieldPage({super.key});

  @override
  State<OfficialShieldPage> createState() => _OfficialShieldPageState();
}

class _OfficialShieldPageState extends State<OfficialShieldPage> {
  final TextEditingController _keywordController = TextEditingController();
  final RxBool _busy = false.obs;
  late final BiliBiliSite _site = BiliBiliSite();

  bool get _logined => _site.hasShieldCredentials;

  @override
  void dispose() {
    _keywordController.dispose();
    _busy.close();
    super.dispose();
  }

  /// 拉取云端列表覆盖本地快照（关键词 + 屏蔽用户）。
  Future<void> _fetch() async {
    if (_busy.v) return;
    if (!_logined) {
      ToastUtil.show(i18n('official_shield_need_login'));
      return;
    }
    _busy.v = true;
    final (ok, msg, keywordCount, userCount) = await _site.fetchAndSaveShieldSnapshot();
    _busy.v = false;
    if (!ok) {
      ToastUtil.show(msg);
      return;
    }
    ToastUtil.show(i18n('official_shield_fetch_done', args: {
      'count': '$keywordCount',
      'userCount': '$userCount',
    }));
  }

  /// 添加关键词：本地列表立即生效（无需登录）；已登录B站时自动同步到账号云端。
  Future<void> _addKeyword() async {
    final keyword = _keywordController.text.trim();
    if (keyword.isEmpty) {
      ToastUtil.show(i18n('please_enter_keyword'));
      return;
    }
    if (_busy.v) return;
    final dm = SettingsService.to.danmaku;
    final snapshot = dm.officialShieldKeywords;
    if (snapshot.contains(keyword)) {
      ToastUtil.show(i18n('official_shield_already_exists'));
      return;
    }
    snapshot.add(keyword);
    _keywordController.clear();
    if (!_site.hasShieldCredentials) {
      ToastUtil.show(i18n('official_shield_add_local'));
      return;
    }
    _busy.v = true;
    final (ok, msg) = await _site.addShieldKeyword(keyword);
    _busy.v = false;
    ToastUtil.show(ok ? i18n('official_shield_add_synced') : msg);
  }

  /// 删除关键词：本地列表立即移除（无需登录）；已登录B站时后台同步删除云端。
  /// 云端删除失败时静默（该词可能从未上传过云端），本地删除已是最终状态。
  Future<void> _removeKeyword(String keyword) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Theme.of(dialogContext).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(i18n('official_shield_del_confirm_title')),
        content: Text(
          i18n('official_shield_del_confirm_msg', args: {'keyword': keyword}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(i18n('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              i18n('confirm'),
              style: TextStyle(color: Theme.of(dialogContext).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final dm = SettingsService.to.danmaku;
    dm.officialShieldKeywords.remove(keyword);
    ToastUtil.show(i18n('official_shield_del_done'));
    if (_site.hasShieldCredentials) {
      await _site.delShieldKeyword(keyword);
    }
  }

  String _lastFetchText() {
    final ts = SettingsService.to.danmaku.lastOfficialShieldFetch.v;
    if (ts <= 0) return i18n('official_shield_never_fetched');
    final time = DateTime.fromMillisecondsSinceEpoch(ts);
    return i18n('official_shield_last_fetch', args: {
      'time': '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} '
          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(i18n('official_shield_manager')),
        actions: [
          Obx(() => IconButton(
                tooltip: i18n('official_shield_fetch'),
                onPressed: _busy.v ? null : _fetch,
                icon: const Icon(Icons.sync_rounded),
              )),
        ],
      ),
      body: ListView(
        physics: const PureLiveScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          Text(
            i18n('official_shield_desc'),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Obx(() => Text(
                _lastFetchText(),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              )),
          const SizedBox(height: 4),
          // 关键词分组：输入行 + 快照列表
          context.buildGroupTitle(i18n('official_shield_keywords')),
          context.buildModernCard([
            _buildKeywordInput(theme),
            Obx(() {
              final keywords = List<String>.from(SettingsService.to.danmaku.officialShieldKeywords);
              if (keywords.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    i18n('official_shield_empty'),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                );
              }
              return Column(
                children: [for (final keyword in keywords) _buildKeywordTile(theme, keyword)],
              );
            }),
          ]),
          // 屏蔽用户分组：只读展示
          context.buildGroupTitle(i18n('official_shield_users')),
          context.buildModernCard([
            Obx(() {
              final entries = List<String>.from(SettingsService.to.danmaku.officialShieldUsers);
              if (entries.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    i18n('official_shield_empty'),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                );
              }
              return Column(
                children: [for (final entry in entries) _buildUserTile(theme, entry)],
              );
            }),
            const SizedBox(height: 4),
            Text(
              i18n('official_shield_users_readonly'),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildKeywordInput(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: TextField(
        controller: _keywordController,
        keyboardType: TextInputType.text,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _addKeyword(),
        decoration: InputDecoration(
          isDense: true,
          hintText: i18n('official_shield_keyword_hint'),
          filled: true,
          fillColor: theme.colorScheme.surfaceContainerLow,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          suffixIcon: Obx(() => IconButton(
                onPressed: _busy.v ? null : _addKeyword,
                icon: const Icon(Icons.add_circle_outline_rounded),
                tooltip: i18n('add'),
              )),
        ),
      ),
    );
  }

  Widget _buildKeywordTile(ThemeData theme, String keyword) {
    return ListTile(
      dense: true,
      leading: Icon(Icons.filter_alt_off_rounded, size: 19, color: theme.colorScheme.primary),
      title: Text(keyword, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: IconButton(
        tooltip: i18n('click_to_remove'),
        icon: const Icon(Icons.close_rounded, size: 18),
        onPressed: _busy.v ? null : () => _removeKeyword(keyword),
      ),
    );
  }

  Widget _buildUserTile(ThemeData theme, String entry) {
    final parts = entry.split('|');
    final uid = parts.first.trim();
    final uname = parts.length > 1 ? parts.sublist(1).join('|') : '';
    return ListTile(
      dense: true,
      leading: Icon(Icons.person_off_rounded, size: 19, color: theme.colorScheme.primary),
      title: Text(uname.isEmpty ? uid : uname, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: uname.isEmpty ? null : Text(uid, style: theme.textTheme.bodySmall),
      // 一期只读：shield_user 接口需要直播间 roomid，取消屏蔽留待直播间内入口
      trailing: const SizedBox(width: 18),
    );
  }
}
