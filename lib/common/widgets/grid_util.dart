import 'package:flutter/material.dart';
import 'package:get/get.dart';

final class GradUtil {
  static Widget count({
    Key? key,
    Axis scrollDirection = Axis.vertical,
    bool reverse = false,
    ScrollController? controller,
    bool? primary,
    ScrollPhysics? physics,
    bool shrinkWrap = false,
    EdgeInsetsGeometry? padding,
    required int crossAxisCount,
    mainAxisSpacing = 0.0,
    crossAxisSpacing = 0.0,
    required IndexedWidgetBuilder itemBuilder,
    int? itemCount,
    bool addAutomaticKeepAlives = true,
    bool addRepaintBoundaries = true,
    bool addSemanticIndexes = true,
    double? cacheExtent,
    int? semanticChildCount,
    ScrollViewKeyboardDismissBehavior keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
    String? restorationId,
    Clip clipBehavior = Clip.hardEdge,
  }) {
    return SliverGrid(
      key: key,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        // 行间距
        mainAxisSpacing: mainAxisSpacing,
        // 列间距
        crossAxisSpacing: crossAxisSpacing,
        // 列数
        crossAxisCount: crossAxisCount,
        mainAxisExtent: MediaQuery.of(Get.context!).size.width / crossAxisCount / 0.65 + MediaQuery.textScalerOf(Get.context!).scale(32.0),
      ),
      delegate: SliverChildBuilderDelegate(
        itemBuilder,
        childCount: itemCount,
      ),
    );
  }

}
