import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class CacheNetWorkUtils {
  static Widget getCacheImage(String imageUrl,
      {double radius = 0.0, required Widget errorWidget,bool full = false}) {
    return imageUrl.isNotEmpty ? CachedNetworkImage(
        imageUrl: imageUrl,
        placeholder: (context, url) => const CircularProgressIndicator(
              color: Colors.white,
            ),
        errorWidget: (context, error, stackTrace) => errorWidget,
        imageBuilder: (context, image) => full == false ? CircleAvatar(
              foregroundImage: image,
              radius: radius,
              backgroundColor: Theme.of(context).disabledColor,
            ) : Image(image: image)) : errorWidget ;
  }
}
