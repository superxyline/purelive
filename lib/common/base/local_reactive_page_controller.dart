import 'dart:async';
import 'package:pure_live/common/index.dart';

abstract class LocalReactivePageController<T> extends BasePageScrollAndStateBone<T> {
  final List<T> _localRawPool = [];

  void Function()? onExternalRefresh;

  void updateLocalReactivePool(List<T> freshData) {
    _localRawPool.clear();
    _localRawPool.addAll(freshData);
    currentPage = 1;
    _processDataDistribution();
  }

  @override
  Future<void> refreshData() async {
    onExternalRefresh?.call();
    currentPage = 1;
    _processDataDistribution();
  }

  @override
  Future<void> goToPage(int page) async {
    // 早退分支补 footer 复位（翻过最后一页再上拉此前"正在刷新"永转）。
    if (loadding.value || page < 1) {
      finishRefreshControllers(IndicatorResult.noMore);
      return;
    }
    if (Get.width <= 680) return;

    final maxPage = (_localRawPool.length / pageSize.value).ceil();
    if (page > maxPage) {
      finishRefreshControllers(IndicatorResult.noMore);
      return;
    }
    currentPage = page;
    _processDataDistribution();
  }

  @override
  void setPageSize(int? newSize) {
    if (newSize == null || pageSize.value == newSize) return;
    if (Get.width <= 680) {
      pageSize.value = newSize;
      return;
    }

    final int currentFirstItemIndex = (currentPage - 1) * pageSize.value;
    pageSize.value = newSize;
    currentPage = (currentFirstItemIndex ~/ newSize) + 1;
    _processDataDistribution();
  }

  @override
  Future<void> loadData() async {
    _processDataDistribution();
  }

  void _processDataDistribution() {
    totalCount.value = _localRawPool.length;
    // 平板/桌面与手机统一为全量展示：桌面切片翻页会让上滑"换一批"
    // （关注页上滑后看到列表另一段，如只剩 B 站直播间），且翻到末页
    // 后上拉 footer 卡死。本地池数据量有限，全量显示无分页必要。
    _processMobileDisplayAll();
  }

  void _processMobileDisplayAll() {
    if (_localRawPool.isEmpty) {
      list.clear();
      canLoadMore.value = false;
      pageEmpty.value = true;
      finishRefreshControllers(IndicatorResult.noMore);
      return;
    }

    pageEmpty.value = false;
    list.assignAll(_localRawPool);
    canLoadMore.value = false;
    finishRefreshControllers(IndicatorResult.noMore);
  }
}
