import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pure_live/core/common/core_log.dart';

class CacheNetWorkUtils {
  // static Widget getCacheImage(String imageUrl,
  //     {double radius = 0.0, required Widget errorWidget, bool full = false}) {
  //   return imageUrl.isNotEmpty
  //       ? CachedNetworkImage(
  //           imageUrl: imageUrl,
  //           cacheManager: CustomCacheManager.instance,
  //           placeholder: (context, url) => const CircularProgressIndicator(
  //                 color: Colors.white,
  //               ),
  //           errorWidget: (context, error, stackTrace) => errorWidget,
  //           imageBuilder: (context, image) => full == false
  //               ? CircleAvatar(
  //                   foregroundImage: image,
  //                   radius: radius,
  //                   backgroundColor: Theme.of(context).disabledColor,
  //                 )
  //               : Image(image: image))
  //       : errorWidget;
  // }

  /// 图片缓存
  static ImageProvider? getNetworkImageProvider(String? avatar) {
    try {
      if (avatar == null || avatar == "") {
        return null;
      }
      return ExtendedNetworkImageProvider(
        avatar,
        cache: true,
        retries: 3,
        timeLimit: const Duration(milliseconds: 5000),
        timeRetry: const Duration(milliseconds: 100),
        cacheMaxAge: const Duration(days: 3),
        // cacheManager: CustomCacheManager.instance, errorListener: (err) {
        // log(err.toString());
        // CoreLog.e("", (err as Error).stackTrace!);
        // log("CachedNetworkImageProvider: Image failed to load!");
        // CoreLog.error(err);
      );
    } catch (e) {
      CoreLog.error(e);
      return null;
    }
  }

  /// 圆形头像
  static getCircleAvatar2(
    String? avatar, {
    double radius = 17,
  }) {
    return CircleAvatar(
      foregroundImage: avatar != null && avatar.isNotEmpty
          ? CacheNetWorkUtils.getNetworkImageProvider(avatar)
          : null,
      radius: radius,
      backgroundColor: Theme.of(Get.context!).disabledColor,
    );
  }

  /// 圆形头像
  static getCircleAvatar(
    String? avatar, {
    double radius = 17,
  }) {
    if (avatar == null) {
      return null;
    }
    return CircleAvatar(
        radius: radius,
        child: getCacheImageV2(avatar,
            radius: radius, fit: BoxFit.fitWidth, shape: BoxShape.circle, cacheWidth: 60));
  }

  static Widget getCacheImageV2(
    String? imageUrl, {
    double radius = 0.0,
    bool full = false,
    BoxFit fit = BoxFit.fitWidth,
    BoxShape? shape,
    int? cacheWidth,
    int? cacheHeight,
  }) {
    if (imageUrl == null || imageUrl.isEmpty) {
      return const SizedBox(
        child: Icon(
          Icons.image_not_supported_outlined,
        ),
      );
    }
    return ExtendedImage.network(
      imageUrl,
      cache: true,
      fit: fit,
      borderRadius: BorderRadius.all(Radius.circular(radius)),
      shape: shape,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      width: cacheWidth?.toDouble(),
      height: cacheWidth?.toDouble(),
      loadStateChanged: (ExtendedImageState state) {
        switch (state.extendedImageLoadState) {
          case LoadState.loading:
            return ExtendedImage.asset(
              clearMemoryCacheWhenDispose: true,
              "assets/images/loading.gif",
              fit: BoxFit.fitWidth,
            );

          ///if you don't want override completed widget
          ///please return null or state.completedWidget
          //return null;
          //return state.completedWidget;
          case LoadState.completed:
            return state.completedWidget;
          case LoadState.failed:
            return const Icon(
              Icons.image_not_supported_outlined,
            );
          /*GestureDetector(
              child: const Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  Icon(
                    Icons.error,
                    color: Colors.red,
                  ),
                ],
              ),
              onTap: () {
                state.reLoadImage();
              },
            );*/
        }
      },
    );
  }
}
