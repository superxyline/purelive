import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/tags/tag_management_controller.dart';

/// 关注页批量管理模式底部浮动工具条：批量打标签 / 批量备注 / 批量移出。
class BatchActionsBar extends StatelessWidget {
  const BatchActionsBar({super.key, required this.controller});

  final FavoriteController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Obx(() {
      final count = controller.selectedKeys.length;
      final enabled = count > 0;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _barButton(
              context,
              icon: Icons.style_rounded,
              label: i18n('batch_add_tags'),
              enabled: enabled,
              onTap: () => _showBatchTagDialog(context, theme),
            ),
            _barButton(
              context,
              icon: Icons.edit_note_rounded,
              label: i18n('batch_set_note'),
              enabled: enabled,
              onTap: () => _showBatchNoteDialog(context, theme),
            ),
            _barButton(
              context,
              icon: Icons.heart_broken_rounded,
              label: i18n('batch_remove'),
              enabled: enabled,
              onTap: () => _confirmBatchRemove(context, theme, count),
              danger: true,
            ),
          ],
        ),
      );
    });
  }

  Widget _barButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final theme = Theme.of(context);
    final color = enabled ? (danger ? theme.colorScheme.error : theme.colorScheme.primary) : theme.disabledColor;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }

  /// 批量打标签：列出全部标签多选，确认后并集合并到所选房间。
  void _showBatchTagDialog(BuildContext context, ThemeData theme) {
    final tagController = Get.find<TagManagementController>();
    final selected = <String>{}.obs;
    Get.dialog(
      AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(i18n('batch_add_tags'), style: AppTextStyles.t16.copyWith(fontWeight: FontWeight.bold)),
        content: Obx(
          () => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (tagController.tags.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(i18n('tags_empty'), style: AppTextStyles.t14.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                )
              else
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final tag in tagController.tags)
                          CheckboxListTile(
                            value: selected.contains(tag.id),
                            onChanged: (v) {
                              if (v == true) {
                                selected.add(tag.id);
                              } else {
                                selected.remove(tag.id);
                              }
                            },
                            title: Text(tag.name, style: AppTextStyles.t14),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(i18n('cancel'), style: AppTextStyles.t14.copyWith(color: theme.colorScheme.secondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              if (selected.isEmpty) {
                SmartDialog.showToast(i18n('batch_no_tag_selected'));
                return;
              }
              controller.batchAddTags(selected.toList());
              Navigator.of(context).pop();
            },
            child: Text(i18n('confirm'), style: AppTextStyles.t14.copyWith(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// 批量备注：一个备注应用到所有所选房间，留空清除。
  void _showBatchNoteDialog(BuildContext context, ThemeData theme) {
    final textController = TextEditingController();
    Get.dialog(
      AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(i18n('batch_set_note'), style: AppTextStyles.t16.copyWith(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: textController,
          autofocus: true,
          maxLength: 30,
          decoration: InputDecoration(hintText: i18n('note_hint'), counterText: ''),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(i18n('cancel'), style: AppTextStyles.t14.copyWith(color: theme.colorScheme.secondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              controller.batchSetNote(textController.text.trim());
              Navigator.of(context).pop();
            },
            child: Text(i18n('confirm'), style: AppTextStyles.t14.copyWith(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmBatchRemove(BuildContext context, ThemeData theme, int count) {
    Get.dialog(
      AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(i18n('batch_remove'), style: AppTextStyles.t16.copyWith(fontWeight: FontWeight.bold)),
        content: Text(
          i18n('batch_remove_confirm', args: {'n': '$count'}),
          style: AppTextStyles.t14.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(i18n('cancel'), style: AppTextStyles.t14.copyWith(color: theme.colorScheme.secondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.of(context).pop();
              controller.batchRemoveSelected();
            },
            child: Text(i18n('confirm'), style: AppTextStyles.t14.copyWith(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
