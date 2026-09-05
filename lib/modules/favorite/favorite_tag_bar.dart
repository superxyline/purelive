import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/tags/tag_management_controller.dart';

/// 关注页标签筛选行（"全部" + 用户自定义标签）。
///
/// 固定在平台 TabBar 下方、EasyRefresh 滚动区之外：
/// 下拉刷新/上拉加载的浮动指示器出现在列表顶部，不会再与标签名重叠。
class FavoriteTagBar extends GetView<FavoriteController> {
  const FavoriteTagBar({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Obx(() {
      if (controller.visibleTags.isEmpty) {
        return const SizedBox.shrink();
      }
      return Container(
        height: 44,
        width: double.infinity,
        color: Colors.transparent,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          physics: const PureLiveScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          itemCount: controller.visibleTags.length + 1,
          itemBuilder: (context, index) {
            final isAll = index == 0;
            final tag = isAll ? null : controller.visibleTags[index - 1];
            final isSelected = isAll
                ? controller.selectedTagId.value == TagManagementController.allTagKey
                : controller.selectedTagId.value == tag!.id;
            final String label = isAll ? (i18n('recorder_tab_all')) : tag!.name;
            // 分区自动标签带角标图标，与用户手动创建的标签区分开
            final isAreaTag = tag != null && TagManagementController.isAreaTag(tag.id);
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                showCheckmark: false,
                avatar: isAreaTag
                    ? Icon(
                        Icons.category_rounded,
                        size: 14,
                        color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant,
                      )
                    : null,
                label: Text(
                  label,
                  style: AppTextStyles.t12.copyWith(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                selected: isSelected,
                selectedColor: theme.colorScheme.primary,
                backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: isSelected ? Colors.transparent : theme.dividerColor.withValues(alpha: 0.04),
                    width: 0.5,
                  ),
                ),
                onSelected: (bool selected) {
                  if (selected) {
                    final targetTagId = isAll ? TagManagementController.allTagKey : tag!.id;
                    controller.changeSelectedTag(targetTagId);
                  }
                },
              ),
            );
          },
        ),
      );
    });
  }
}
