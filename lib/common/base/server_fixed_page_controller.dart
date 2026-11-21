import 'dart:async';
import 'package:pure_live/common/index.dart';

/// 大页固定尺寸网络分页模型：接口按 fixedServerPageSize 翻大页，客户端按
/// pageSize 切片消费。平板/桌面与手机统一为"无限往下追加"（此前桌面为
/// 切片替换翻页，上拉到无更多时 footer 卡死，体验与手机不一致）。
abstract class ServerFixedPageController<T> extends BasePageScrollAndStateBone<T> {
  final int fixedServerPageSize;
  final Map<int, List<T>> _bigPageCache = {};

  ServerFixedPageController({required this.fixedServerPageSize}) : super();

  Future<List<T>> fetchFixedNetworkData(int bigPage, int fixedSize);

  @override
  Future<void> refreshData() async {
    _bigPageCache.clear();
    currentPage = 1;
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
    // 统一追加：只更新页大小，下一页生效（不再重算切片游标）。
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

    final int currentGlobalStart = (currentPage - 1) * pageSize.value;
    final int currentGlobalEnd = currentGlobalStart + pageSize.value;

    try {
      loadding.value = true;
      pageError.value = false;
      pageEmpty.value = false;
      notLogin.value = false;
      if (list.isEmpty) pageLoadding.value = true;

      List<T> combinedData = [];
      int currentFetchOffset = currentGlobalStart;

      while (currentFetchOffset < currentGlobalEnd) {
        final int serverBigPage = (currentFetchOffset ~/ fixedServerPageSize) + 1;
        List<T> bigPageData;

        if (_bigPageCache.containsKey(serverBigPage)) {
          bigPageData = _bigPageCache[serverBigPage]!;
        } else {
          bigPageData = await fetchFixedNetworkData(serverBigPage, fixedServerPageSize);
          _bigPageCache[serverBigPage] = bigPageData;
        }

        if (bigPageData.isEmpty) break;

        final int innerStart = currentFetchOffset % fixedServerPageSize;
        if (innerStart >= bigPageData.length) break;

        final int neededCount = currentGlobalEnd - currentFetchOffset;
        final int availableCount = bigPageData.length - innerStart;
        final int takeCount = neededCount < availableCount ? neededCount : availableCount;

        combinedData.addAll(bigPageData.sublist(innerStart, innerStart + takeCount));
        currentFetchOffset += takeCount;

        if (bigPageData.length < fixedServerPageSize) break;
      }

      if (combinedData.isEmpty && currentPage > 1) {
        canLoadMore.value = false;
        finishRefreshControllers(IndicatorResult.noMore);
        return;
      }

      // 平板/桌面与手机统一：追加到列表尾部（不再切片替换）。
      canLoadMore.value = combinedData.length >= pageSize.value;
      list.addAll(combinedData);
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
