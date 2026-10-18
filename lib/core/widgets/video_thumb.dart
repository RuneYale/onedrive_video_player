import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/smartisan_kit.dart';

/// The 16:9 thumbnail at the head of a video row: a hairline-framed image when
/// OneDrive has one, otherwise a pale glyph on the kit's light grey.
class VideoThumb extends StatelessWidget {
  const VideoThumb({
    super.key,
    this.url,
    this.width = 64,
    this.height = 36,
    this.glyph = SGlyphs.film,
  });

  final String? url;
  final double width;
  final double height;
  final IconData glyph;

  @override
  Widget build(BuildContext context) {
    final p = context.sp;
    const radius = BorderRadius.all(Radius.circular(SRadii.small));
    final hasImage = url != null && url!.isNotEmpty;
    return Container(
      width: width,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.pageStripe,
        borderRadius: radius,
        border: Border.all(color: p.border, width: SHair.xs),
      ),
      child: hasImage
          ? CachedNetworkImage(
              imageUrl: url!,
              fit: BoxFit.cover,
              placeholder: (_, _) => _Glyph(glyph: glyph),
              errorWidget: (_, _, _) => _Glyph(glyph: glyph),
            )
          : _Glyph(glyph: glyph),
    );
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph({required this.glyph});

  final IconData glyph;

  @override
  Widget build(BuildContext context) =>
      Center(child: Icon(glyph, size: 18, color: context.sp.iconDisabled));
}
