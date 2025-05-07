import 'dart:async';
import 'package:get/get.dart';
import 'package:flutter/widgets.dart';
import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:pure_live/core/common/core_log.dart';

import 'base_controller.dart';

/// 只加载一次数据
class OneBaseController<T> extends BasePageController<T> {

  @override
  void onInit() {
    refreshData();
  }

  @override
  Future loadData() async {
    try {
      if (loadding.value) return;
      loadding.value = true;
      pageError.value = false;
      pageEmpty.value = false;
      notLogin.value = false;
      pageLoadding.value = false;

      /// 只加载一页
      if(currentPage > 1) return;

      var result = await getData(currentPage, pageSize);
      canLoadMore.value = false;
      pageEmpty.value = result.isEmpty;
      currentPage++;

      // 赋值数据
      list.value = result;
    } catch (e) {
      handleError(e, showPageError: currentPage == 1);
    } finally {
      loadding.value = false;
      pageLoadding.value = false;
    }
  }
}
