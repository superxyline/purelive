import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:pure_live/plugins/app_image_cache_manager.dart';

/// 电竞游戏图标（Simple Icons 单色 SVG，随主题/传入颜色着色）。
///
/// gameKey 与 [EsportsMatch.gameKey] 一致：cs / lol / valorant；
/// 无对应图标（未知游戏）时渲染等宽占位，调用方无需判空。
class EsportsGameIcon extends StatelessWidget {
  const EsportsGameIcon(this.gameKey, {super.key, this.size = 14, this.color});

  final String gameKey;
  final double size;
  final Color? color;

  static const Map<String, String> _assets = {
    'cs': 'assets/icons/esports/counterstrike.svg',
    'lol': 'assets/icons/esports/leagueoflegends.svg',
    'valorant': 'assets/icons/esports/valorant.svg',
  };

  @override
  Widget build(BuildContext context) {
    final asset = _assets[gameKey];
    if (asset == null) return SizedBox(width: size, height: size);
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(
        color ?? Theme.of(context).colorScheme.onSurface,
        BlendMode.srcIn,
      ),
    );
  }
}

/// 赛事/联赛图标：数据源自带的官方 logo（IEM→ESL、PGL、Worlds 等）优先，
/// 无 logo（URL 为空或加载失败）时回退到游戏图标。
class EsportsSeriesIcon extends StatelessWidget {
  const EsportsSeriesIcon(
    this.seriesLogo,
    this.gameKey, {
    super.key,
    this.size = 14,
    this.color,
  });

  final String seriesLogo;
  final String gameKey;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (seriesLogo.isEmpty) {
      return EsportsGameIcon(gameKey, size: size, color: color);
    }
    return CachedNetworkImage(
      imageUrl: seriesLogo,
      width: size,
      height: size,
      fit: BoxFit.contain,
      cacheManager: AppImageCacheManager.instance,
      placeholder: (_, _) => SizedBox(width: size, height: size),
      errorWidget: (_, _, _) => EsportsGameIcon(gameKey, size: size, color: color),
    );
  }
}
