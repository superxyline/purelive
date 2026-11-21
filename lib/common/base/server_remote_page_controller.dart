import 'dart:async';

import 'package:pure_live/common/index.dart';

/// 真分页网络模型：按页请求、去重凑满 pageSize。平板/桌面与手机统一为
/// "无限往下追加"（此前桌面为页缓存切片替换翻页，上拉到无更多时 footer
/// 卡死，体验与手机不一致）。
abstract class ServerRemotePageController<T> extends BasePageScrollAndStateBone<T> {
  /// 网络翻页游标：连续请求递增，去重后凑满一屏为止。
  int _virtualNetworkPage = 1;

  ServerRemotePageController() : super();

  Future<List<T>> fetchNetworkData(int page, int pageSize);

  @override
  Future<void> refreshData() async {
    currentPage = 1;
    _virtualNetworkPage = 1;
    list.clear();
    await loadData();
  }

  @override
  Future<void> goToPage(int page) async {
    // 统一追加模式后不再有外部翻页入口（loadMoreData 直接 currentPage++）。
    // 早退补 footer 复位以防历史调用方触发"正在刷新"永转。
    if (loadding.value || page < 1) {
      finishRefreshControllers(IndicatorResult.noMore);
      return;
    }
    currentPage = page;
    await loadData();
  }

  @override
  void setPageSize(int? newSize) {
    if (newSize == null || pageSize.value == newSize) return;
    // 统一追加：只更新页大小，下一页生效。
    pageSize.value = newSize;
  }

  @override
  Future<void> loadData() async {
    if (loadding.value) return;
    totalCount.value = null;

    final bool isNetworkSafe = await checkNetworkBeforeRequest();
    if (!isNetworkSafe) {
      finishRefreshControllers(IndicatorResult.fail);
      return;
    }

    final int previousPageSnapshot = currentPage;
    try {
      loadding.value = true;
      pageError.value = false;
      pageEmpty.value = false;
      notLogin.value = false;
      if (list.isEmpty) pageLoadding.value = true;

      List<T> combinedResult = [];
      // 去重基准含已有列表（追加模式）：接口重复条目不再追加。
      final seen = <T>{...list};
      final int sizeToFetch = pageSize.value;
      var requestCount = 0;
      var noProgressCount = 0;

      while (combinedResult.length < sizeToFetch && requestCount < 20 && noProgressCount < 2) {
        final int neededCount = sizeToFetch - combinedResult.length;
        final result = await fetchNetworkData(_virtualNetworkPage, neededCount);
        requestCount++;
        if (result.isEmpty) break;

        final previousLength = combinedResult.length;
        for (final item in result) {
          if (seen.add(item)) combinedResult.add(item);
          if (combinedResult.length >= sizeToFetch) break;
        }
        noProgressCount = combinedResult.length == previousLength ? noProgressCount + 1 : 0;
        _virtualNetworkPage++;
      }

      if (combinedResult.isEmpty && currentPage > 1) {
        canLoadMore.value = false;
        finishRefreshControllers(IndicatorResult.noMore);
        return;
      }

      // 平板/桌面与手机统一：追加到列表尾部（不再切片替换）。
      canLoadMore.value = combinedResult.length >= pageSize.value;
      list.addAll(combinedResult);
      pageEmpty.value = list.isEmpty;
      finishRefreshControllers(canLoadMore.value ? IndicatorResult.success : IndicatorResult.noMore);
    } catch (e) {
      currentPage = previousPageSnapshot;
      handleError(e, showPageError: list.isEmpty);
      finishRefreshControllers(IndicatorResult.fail);
    } finally {
      loadding.value = false;
      pageLoadding.value = false;
    }
  }
}
