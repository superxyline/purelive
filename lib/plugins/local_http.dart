import 'dart:convert';
import 'dart:io' as io;
import 'package:get/get.dart';
import 'package:dia/dia.dart';
import 'package:dia_cors/dia_cors.dart';
import 'package:pure_live/common/index.dart';
import 'package:dia_router/dia_router.dart' as dia_router;

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
    app.use(router.middleware);
    app.listen(io.InternetAddress.anyIPv4.address, port);
  }
}
