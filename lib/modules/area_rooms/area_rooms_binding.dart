import 'package:get/get.dart';
import 'package:pure_live/modules/area_rooms/area_rooms_controller.dart';

class AreaRoomsBinding extends Binding {
  @override
  List<Bind> dependencies() {
    return [Bind.lazyPut(() => AreaRoomsController(Get.arguments))];
  }
}
