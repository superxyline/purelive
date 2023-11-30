import 'dart:io';
import 'dart:convert';
import 'dart:io' as io;
import 'package:get/get.dart';
import 'package:dia/dia.dart';
import 'package:path/path.dart' as p;
import 'package:dia_cors/dia_cors.dart';
import 'package:dia_body/dia_body.dart';
import 'package:dia_static/dia_static.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/routes/app_navigation.dart';
import 'package:dia_router/dia_router.dart' as dia_router;
import 'package:pure_live/plugins/file_recover_utils.dart';
import 'package:pure_live/modules/areas/areas_list_controller.dart';
import 'package:pure_live/modules/popular/popular_grid_controller.dart';
import 'package:pure_live/modules/area_rooms/area_rooms_controller.dart';
import 'package:pure_live/common/services/bilibili_account_service.dart';

class ContextRequest extends Context with dia_router.Routing, ParsedBody {
  ContextRequest(super.request);
}

class LocalHttpServer {
  final SettingsService settings = Get.find<SettingsService>();
  static int port = 25685;
  void startServer() async {
    final app = App((req) => ContextRequest(req));
    final directory = await getExternalStorageDirectory();

    app.use(serve(p.join(directory!.path, 'pure_live_web'), prefix: '/pure_live', index: 'index.html'));
    app.use(body());
    app.use(cors());

    final router = dia_router.Router('/api');
    router.get('/path/:id', (ctx, next) async {
      ctx.body = 'params=${ctx.params} query=${ctx.query}';
    });
    router.get('/getSettings', (ctx, next) async {
      ctx.body = jsonEncode(settings.toJson());
    });

    router.get('/getFavoriteRooms', (ctx, next) async {
      ctx.body = jsonEncode(settings.favoriteRooms.map((e) => jsonEncode(e.toJson())).toList());
    });

    router.post('/getHistoryData', (ctx, next) async {
      ctx.body = jsonEncode(settings.historyRooms.map((e) => jsonEncode(e.toJson())).toList());
    });

    router.post('/postFavoriteRooms', (ctx, next) async {
      final FavoriteController controller = Get.find<FavoriteController>();
      final result = await controller.onRefresh();
      ctx.body = jsonEncode({'data': !result});
    });
    router.post('/exitRoom', (ctx, next) async {
      try {
        String type = ctx.query['type']!;
        ctx.body = jsonEncode({'data': true});
        if (type == 'favoriteRooms') {
          Get.offAndToNamed(RoutePath.kInitial)!;
        } else if (type == 'areasRooms') {
          Get.offAndToNamed(RoutePath.kAreas)!;
        } else {
          if (Get.currentRoute != RoutePath.kInitial) {
            Get.back();
          }
        }
      } catch (e) {
        ctx.body = jsonEncode({'data': false});
      }
    });
    router.post('/enterRoom', (ctx, next) async {
      try {
        final liveRoom = jsonDecode(ctx.query['liveRoom']!);
        ctx.body = jsonEncode({'data': true});
        AppNavigator.toLiveRoomDetail(liveRoom: LiveRoom.fromJson(liveRoom));
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
        String tag = ctx.query['tag']!;
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
          case 'areaSubTab':
            AreasListController controller = Get.find<AreasListController>(tag: tag);
            controller.tabIndex.value = index;
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
        int page = int.parse(ctx.query['page']!);
        int pageSize = int.parse(ctx.query['pageSize']!);
        switch (ctx.query['type']!) {
          case 'hotTab':
            var controller = Get.find<PopularGridController>(tag: tag);
            var sizeData = await controller.getData(page, pageSize);
            controller.list.addAll(sizeData);
            controller.scrollToBottom();

            data = jsonEncode(sizeData.map((LiveRoom element) => jsonEncode(element.toJson())).toList());
            break;
          case 'areaTab':
            var controller = Get.find<AreasListController>(tag: tag);
            data = jsonEncode(controller.list.value);
            break;
          case 'areaRoomsTab':
            AreaRoomsController areaRoomController = Get.find<AreaRoomsController>();
            var sizeData = await areaRoomController.getData(page, pageSize);
            areaRoomController.list.addAll(sizeData);
            areaRoomController.scrollToBottom();
            data = jsonEncode(sizeData.map((LiveRoom element) => jsonEncode(element.toJson())).toList());
            break;
          default:
        }
        ctx.body = jsonEncode({'data': data});
      } catch (e) {
        ctx.body = jsonEncode({'data': data});
      }
    });
    router.post('/toAreaDetail', (ctx, next) async {
      try {
        String tag = ctx.query['tag']!;
        String area = ctx.query['area']!;
        var site = Sites.of(tag);
        var areaRoom = LiveArea.fromJson(jsonDecode(area));
        AppNavigator.toCategoryDetail(site: site, category: areaRoom);
        ctx.body = jsonEncode({'data': true});
      } catch (e) {
        ctx.body = jsonEncode({'data': false});
      }
    });
    router.post('/uploadFile', (ctx, next) async {
      try {
        ctx.body = jsonEncode({'data': true});
      } catch (e) {
        ctx.body = jsonEncode({'data': false});
      }
    });

    app.use(router.middleware);
    app.use((ctx, next) async {
      if (ctx.query['type'] != null) {
        String? type = ctx.query['type'];
        if (type == 'uploadM3u8File') {
          FileRecoverUtils().recoverM3u8BackupByWeb(ctx.parsed['file'], ctx.parsed['name']);
        } else if (type == 'uploadRecoverFile') {
          var dir = await getApplicationCacheDirectory();
          final file = File('${dir.path}${Platform.pathSeparator}${ctx.parsed['name']}');
          file.writeAsStringSync(ctx.parsed['file']);
          if (settings.recover(file)) {
            SnackBarUtil.success(S.of(Get.context!).recover_backup_success);
          } else {
            SnackBarUtil.error(S.of(Get.context!).recover_backup_failed);
          }
        } else {
          await next();
        }
      } else {
        await next();
      }
    });
    app.listen(io.InternetAddress.anyIPv4.address, port);
  }
}
