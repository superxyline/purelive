import 'package:pure_live/common/index.dart';

class SearchController extends GetxController with GetSingleTickerProviderStateMixin {
  late TabController tabController;
  var index = 0.obs;
  final TextEditingController searchController = TextEditingController();

  /// 搜索结果（主播名模糊搜索 / 房间号精确搜索共用）
  final results = <LiveRoom>[].obs;

  /// 是否正在搜索
  final loading = false.obs;

  /// 是否已执行过搜索（用于区分初始提示与空结果状态）
  final searched = false.obs;

  /// 当前结果是否为"房间号精确搜索"
  final isRoomIdSearch = false.obs;

  /// 搜索失败提示
  final error = RxnString();

  int _page = 1;
  bool _hasMore = true;
  String _lastKeyword = '';
  String _lastPlatform = '';

  SearchController() {
    tabController = TabController(length: Sites().availableSites().length, vsync: this);
    tabController.addListener(() {
      if (index.value != tabController.index) {
        index.value = tabController.index;
        // 切换平台后，若已有搜索则在新平台重新搜索
        if (searched.value && searchController.text.trim().isNotEmpty) {
          doSearch();
        }
      }
    });
  }

  /// 输入是否为纯数字（判断为房间号精确搜索）
  bool get _isNumeric => RegExp(r'^\d+$').hasMatch(searchController.text.trim());

  void doSearch() {
    final keyword = searchController.text.trim();
    if (keyword.isEmpty) {
      ToastUtil.show(i18n("please_input_keyword"));
      return;
    }
    _page = 1;
    _hasMore = true;
    _lastKeyword = keyword;
    _lastPlatform = Sites().availableSites()[index.value].id;
    results.clear();
    error.value = null;
    searched.value = true;
    if (_isNumeric) {
      isRoomIdSearch.value = true;
      _searchByRoomId(keyword, _lastPlatform);
    } else {
      isRoomIdSearch.value = false;
      _searchByName(_lastKeyword, _lastPlatform, page: 1);
    }
  }

  /// 主播名/关键词模糊搜索
  Future<void> _searchByName(String keyword, String platform, {int page = 1}) async {
    loading.value = true;
    try {
      final site = Sites.of(platform);
      final list = await site.liveSite.searchRooms(keyword, page: page, pageSize: 30);
      if (page == 1) {
        results.value = list;
      } else {
        results.addAll(list);
      }
      _hasMore = list.length >= 30;
    } catch (e) {
      if (page == 1) {
        error.value = _friendlyError(e);
      } else {
        ToastUtil.show(_friendlyError(e));
      }
    } finally {
      loading.value = false;
    }
  }

  /// 将异常转换为用户可读的友好提示
  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.startsWith('Exception: ')) {
      return s.substring('Exception: '.length);
    }
    return s;
  }

  /// 房间号精确搜索
  Future<void> _searchByRoomId(String roomId, String platform) async {
    loading.value = true;
    try {
      final site = Sites.of(platform);
      final room = await site.liveSite.getRoomDetail(roomId: roomId, platform: platform);
      if (room.roomId == null || room.roomId!.isEmpty || (room.title ?? '').isEmpty) {
        error.value = i18n('search_room_id_not_found');
      } else {
        results.value = [room];
      }
    } catch (e) {
      error.value = i18n('search_room_id_not_found');
    } finally {
      loading.value = false;
    }
  }

  /// 滚动到底部加载更多（主播名搜索分页）
  void loadMore() {
    if (loading.value || isRoomIdSearch.value || !_hasMore) return;
    _page++;
    _searchByName(_lastKeyword, _lastPlatform, page: _page);
  }

  @override
  void onClose() {
    tabController.dispose();
    searchController.dispose();
    super.onClose();
  }
}
