import 'dart:convert';
import 'dart:io' as io;
import 'package:get/get.dart';
import 'package:dia/dia.dart';
import 'package:dia_cors/dia_cors.dart';
import 'package:dia_static/dia_static.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/routes/app_navigation.dart';
import 'package:dia_router/dia_router.dart' as dia_router;
import 'package:pure_live/modules/areas/areas_list_controller.dart';
import 'package:pure_live/modules/popular/popular_grid_controller.dart';
import 'package:pure_live/common/services/bilibili_account_service.dart';

class ContextWithRouting extends Context with dia_router.Routing {
  ContextWithRouting(super.request);
}

class LocalHttpServer {
  final SettingsService settings = Get.find<SettingsService>();
  static int port = 25685;
  void startServer() async {
    final app = App((req) {
      return ContextWithRouting(req);
    });
    app.use(serve('./lib/pure_live_web', index: 'index.html'));
    app.use(cors());

    final router = dia_router.Router('/api');
    router.get('/path/:id', (ctx, next) async {
      ctx.body = 'params=${ctx.params} query=${ctx.query}';
    });
    router.get('/getSettings', (ctx, next) async {
      ctx.body = jsonEncode(settings.toJson());
    });
    router.get('/getFavoriteRooms', (ctx, next) async {
      ctx.body = jsonEncode(settings.favoriteRooms.map<String>((e) => jsonEncode(e.toJson())).take(200).toList());
    });
    router.post('/postFavoriteRooms', (ctx, next) async {
      final FavoriteController controller = Get.find<FavoriteController>();
      final result = await controller.onRefresh();
      ctx.body = jsonEncode({'data': !result});
    });
    router.post('/exitRoom', (ctx, next) async {
      try {
        ctx.body = jsonEncode({'data': true});
        Get.offAndToNamed(RoutePath.kInitial)!;
      } catch (e) {
        ctx.body = jsonEncode({'data': false});
      }
    });
    router.post('/enterRoom', (ctx, next) async {
      try {
        final liveRoom = jsonDecode(ctx.query['liveRoom']!);
        final realLiveRoom = settings.getLiveRoomByRoomId(liveRoom['roomId'], platform: liveRoom['platform']);
        ctx.body = jsonEncode({'data': true});
        AppNavigator.toLiveRoomDetail(liveRoom: realLiveRoom);
      } catch (e) {
        ctx.body = jsonEncode({'data': false});
      }
    });

    router.post('/playRoom', (ctx, next) async {
      try {
        final liveRoom = jsonDecode(ctx.query['liveRoom']!);
        final realLiveRoom = settings.getLiveRoomByRoomId(liveRoom['roomId'], platform: liveRoom['platform']);
        Get.offAndToNamed(RoutePath.kInitial)!;
        AppNavigator.toLiveRoomDetail(liveRoom: realLiveRoom);
        ctx.body = jsonEncode({'data': true});
      } catch (e) {
        ctx.body = jsonEncode({'data': false});
      }
    });

    router.post('/getLibilibiLoginStatus', (ctx, next) async {
      final BiliBiliAccountService accountService = Get.find<BiliBiliAccountService>();
      ctx.body = jsonEncode({'data': accountService.logined.value, 'name': accountService.name.value});
    });

    router.post('/toBiliBiliLogin', (ctx, next) async {
      try {
        Get.toNamed(RoutePath.kBiliBiliQRLogin);
        ctx.body = jsonEncode({'data': true});
      } catch (e) {
        ctx.body = jsonEncode({'data': false});
      }
    });
    router.post('/exitBilibili', (ctx, next) async {
      try {
        BiliBiliAccountService.instance.logout();
        ctx.body = jsonEncode({'data': true});
      } catch (e) {
        ctx.body = jsonEncode({'data': false});
      }
    });
    router.post('/uploadSettingsConfig', (ctx, next) async {
      try {
        settings.fromJson(json.decode(ctx.query['setting']!));
        ctx.body = jsonEncode({'data': true});
      } catch (e) {
        ctx.body = jsonEncode({'data': false});
      }
    });
    router.post('/toggleHomeTab', (ctx, next) async {
      try {
        int index = int.parse(ctx.query['index']!);
        FavoriteController favoriteController = Get.find<FavoriteController>();
        switch (ctx.query['type']!) {
          case 'online':
            favoriteController.tabController.animateTo(index);
            break;
          case 'bottomTab':
            favoriteController.tabBottomIndex.value = index;
            break;
          case 'hotTab':
            PopularController popularController = Get.find<PopularController>();
            popularController.tabController.animateTo(index);
            break;
          case 'areaTab':
            AreasController areasController = Get.find<AreasController>();
            areasController.tabController.animateTo(index);
            break;
          default:
        }

        ctx.body = jsonEncode({'data': true});
      } catch (e) {
        ctx.body = jsonEncode({'data': false});
      }
    });
    router.post('/getTabData', (ctx, next) async {
      String data = '';
      try {
        String tag = ctx.query['tag']!;
        switch (ctx.query['type']!) {
          case 'hotTab':
            var controller = Get.find<PopularGridController>(tag: tag);
            data = jsonEncode(controller.list.map((LiveRoom element) => jsonEncode(element.toJson())).toList());
            break;
          case 'areaTab':
            var controller = Get.find<AreasListController>(tag: tag);
            data = jsonEncode(controller.list.map((AppLiveCategory element) => jsonEncode(element.toJson())).toList());
            break;
          default:
        }

        ctx.body = jsonEncode({'data': data});
      } catch (e) {
        ctx.body = jsonEncode({'data': data});
      }
    });
    app.use(router.middleware);
    app.listen(io.InternetAddress.anyIPv4.address, port);
  }
}
