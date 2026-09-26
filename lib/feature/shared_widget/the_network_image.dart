import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Standard network image with a shimmer placeholder.
class TheNetworkImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  /// Optional overrides. When omitted, the decoded cache size is derived from
  /// [width]/[height] scaled by the current [MediaQuery.devicePixelRatio]. See
  /// RES-105: without these, source images (1600×1200 from the fake API) sit
  /// in RAM at full source resolution regardless of the box they paint into.
  final int? memCacheWidth;
  final int? memCacheHeight;

  const TheNetworkImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.memCacheWidth,
    this.memCacheHeight,
  });

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final resolvedCacheWidth = memCacheWidth ??
        (width != null && width!.isFinite ? (width! * dpr).round() : null);
    final resolvedCacheHeight = memCacheHeight ??
        (height != null && height!.isFinite ? (height! * dpr).round() : null);

    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: CachedNetworkImage(
        imageUrl: url,
        width: width,
        height: height,
        fit: fit,
        memCacheWidth: resolvedCacheWidth,
        memCacheHeight: resolvedCacheHeight,
        placeholder: (context, _) => Shimmer.fromColors(
          baseColor: Colors.grey.shade300,
          highlightColor: Colors.grey.shade100,
          child: Container(width: width, height: height, color: Colors.white),
        ),
        errorWidget: (context, _, __) => Container(
          width: width,
          height: height,
          color: Colors.grey.shade200,
          child: const Icon(Icons.image_not_supported_outlined),
        ),
      ),
    );
  }
}
