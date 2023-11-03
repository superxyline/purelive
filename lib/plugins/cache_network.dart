import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class CacheNetWorkUtils {
  static Widget getCacheImage(imageUrl,
      {double radius = 0.0, required Widget errorWidget}) {
    return CachedNetworkImage(
        imageUrl: imageUrl,
        placeholder: (context, url) => const CircularProgressIndicator(
              color: Colors.white,
            ),
        errorWidget: (context, error, stackTrace) => errorWidget,
        imageBuilder: (context, image) => CircleAvatar(
              foregroundImage: image,
              radius: radius,
              backgroundColor: Theme.of(context).disabledColor,
            ));
  }
}
