import 'package:cached_network_image/cached_network_image.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/routes/app_pages.dart';

class AreaCard extends StatelessWidget {
  const AreaCard({
    Key? key,
    required this.area,
  }) : super(key: key);

  final LiveArea area;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(7.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15.0),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(15.0),
        onTap: () => AppPages.toAreaRooms(area),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Card(
                margin: const EdgeInsets.all(0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15.0),
                ),
                clipBehavior: Clip.antiAlias,
                color: Colors.white,
                elevation: 0,
                child: CachedNetworkImage(
                  imageUrl: area.areaPic,
                  cacheManager: CustomCacheManager.instance,
                  fit: BoxFit.fill,
                  errorWidget: (context, error, stackTrace) => const Center(
                    child: Icon(
                      Icons.live_tv_rounded,
                      size: 38,
                    ),
                  ),
                ),
              ),
            ),
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10),
              title: Text(
                area.areaName,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    area.typeName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                  Text(
                    area.platform.toUpperCase(),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
