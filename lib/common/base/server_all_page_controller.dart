import 'dart:async';
import 'package:pure_live/common/index.dart';

/// 一次拉全模型：接口一次性返回全部数据，客户端全量展示（无分页追加）。
/// 平板/桌面与手机统一为全量显示（此前桌面为本地切片翻页，翻到末页后
/// 上拉 footer 卡死，体验与手机不一致）。
abstract class ServerAllPageController<T> extends BasePageScrollAndStateBone<T> {
  List<T>? _rawAllData;

  Future<List<T>> fetchAllServerData();

  @override
  Future<void> refreshData() async {
    _rawAllData = null;
    currentPage = 1;
    await loadData();
  }

  @override
  Future<void> goToPage(int page) async {
    // 统一全量显示后无翻页概念；早退补 footer 复位以防历史调用方触发
    // "正在刷新"永转。
    if (loadding.value || page < 1 || _rawAllData == null) {
      finishRefreshControllers(IndicatorResult.noMore);
      return;
    }
    currentPage = page;
    processLocalPaging();
  }

  @override
  void setPageSize(int? newSize) {
    if (newSize == null || pageSize.value == newSize) return;
    // 全量显示不分页，页大小仅作记录。
    pageSize.value = newSize;
  }

  @override
  Future<void> loadData() async {
    if (loadding.value) return;

    if (_rawAllData != null) {
      processLocalPaging();
      return;
    }

    final bool isNetworkSafe = await checkNetworkBeforeRequest();
    if (!isNetworkSafe) {
      finishRefreshControllers(IndicatorResult.fail);
      return;
    }

    try {
      loadding.value = true;
      pageError.value = false;
      pageEmpty.value = false;
      notLogin.value = false;
      pageLoadding.value = true;

      _rawAllData = await fetchAllServerData();
      processLocalPaging();
    } catch (e) {
      handleError(e, showPageError: list.isEmpty);
      finishRefreshControllers(IndicatorResult.fail);
    } finally {
      loadding.value = false;
      pageLoadding.value = false;
    }
  }

  void processLocalPaging() {
    if (_rawAllData == null) return;
    final allItems = _rawAllData!;
    totalCount.value = allItems.length;

    // 平板/桌面与手机统一：全量展示（数据一次性拉全，无更多分页）。
    list.assignAll(allItems);
    canLoadMore.value = false;
    pageEmpty.value = list.isEmpty;
    finishRefreshControllers(IndicatorResult.noMore);
  }
}
