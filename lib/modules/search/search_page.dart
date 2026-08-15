import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/search/search_controller.dart' as pure_live;
import 'package:waterfall_flow/waterfall_flow.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  pure_live.SearchController get controller => Get.find<pure_live.SearchController>();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 300) {
      controller.loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: TextField(
          controller: controller.searchController,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: i18n("search_input_hint"),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12.0),
            prefixIcon: IconButton(
              onPressed: () {
                if (Navigator.canPop(Get.context!)) {
                  Navigator.of(Get.context!).pop();
                }
              },
              icon: const Icon(Icons.arrow_back),
            ),
            suffixIcon: IconButton(onPressed: controller.doSearch, icon: const Icon(Icons.search)),
          ),
          onSubmitted: (e) {
            controller.doSearch();
          },
        ),
        bottom: TabBar(
          controller: controller.tabController,
          padding: EdgeInsets.zero,
          tabs: Sites().availableSites().map((e) => Tab(text: e.name)).toList(),
          isScrollable: true,
        ),
      ),
      body: Column(
        children: [
          _buildModeHint(theme),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  /// 顶部模式提示条：说明当前是"主播名搜索"还是"房间号搜索"
  Widget _buildModeHint(ThemeData theme) {
    return Obx(() {
      final String text;
      if (!controller.searched.value) {
        text = i18n('search_hint_both');
      } else if (controller.isRoomIdSearch.value) {
        text = i18n('search_hint_room_id');
      } else {
        text = i18n('search_hint_name');
      }
      return Container(
        width: double.infinity,
        color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          text,
          style: AppTextStyles.t12.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    });
  }

  Widget _buildBody() {
    return Obx(() {
      if (controller.loading.value && controller.results.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      if (controller.error.value != null && controller.results.isEmpty) {
        return EmptyView(
          title: i18n('search_failed_title'),
          subtitle: controller.error.value ?? i18n('search_failed_subtitle'),
          buttonText: i18n('retry'),
          onButtonPressed: controller.doSearch,
        );
      }
      if (!controller.searched.value) {
        return EmptyView(
          title: i18n('search_initial_title'),
          subtitle: i18n('search_hint_both'),
        );
      }
      if (controller.results.isEmpty) {
        return EmptyView(
          title: i18n('empty_search_title'),
          subtitle: i18n('empty_search_subtitle'),
        );
      }
      return _buildResultGrid();
    });
  }

  Widget _buildResultGrid() {
    final width = Get.width;
    final dense = SettingsService.to.app.enableDenseFavorites.v;
    int crossAxisCount = width > 1280 ? 4 : (width > 960 ? 3 : (width > 640 ? 2 : 1));
    if (dense) {
      crossAxisCount = width > 1280 ? 5 : (width > 960 ? 4 : (width > 640 ? 3 : 2));
    }
    return WaterfallFlow.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      controller: _scrollController,
      gridDelegate: SliverWaterfallFlowDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: SettingsService.to.theme.crossAxisSpacing.v,
        mainAxisSpacing: SettingsService.to.theme.mainAxisSpacing.v,
      ),
      itemCount: controller.results.length + (controller.loading.value ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= controller.results.length) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5))),
          );
        }
        return RoomCard(room: controller.results[index], dense: dense, showFollowButton: true);
      },
    );
  }
}
