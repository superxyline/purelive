import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/routes/route_path.dart';


class SearchButton extends StatelessWidget {
  const SearchButton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => Get.toNamed(RoutePath.kSearch),
      icon: const Icon(CustomIcons.search),
    );
  }
}
