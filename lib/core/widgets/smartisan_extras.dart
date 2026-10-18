import 'package:flutter/material.dart';

import '../../smartisan/smartisan_motion.dart' show SMotion;
import '../../smartisan/smartisan_palette.dart';
import '../../smartisan/smartisan_theme.dart' show SRadii, SHair;
import '../../smartisan/smartisan_widgets.dart' show SDivider, SPressable;

/// Bar icon button for the `SGlyphs` font — the kit's [SIconButtonPlain]
/// behaviour (resting tint, darkens and springs to 1.33x while held, no
/// background highlight) for the solid glyphs this app uses in app bars.
class SBarGlyphButton extends StatelessWidget {
  const SBarGlyphButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 24,
    this.color,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final base = color ?? IconTheme.of(context).color ?? context.sp.icon;
    final light = base.computeLuminance() > .6;
    return SPressable(
      onTap: onTap,
      builder: (context, p) => AnimatedScale(
        scale: p ? SMotion.barIconScale : 1,
        duration: SMotion.barIconSpring,
        curve: Curves.easeOutBack,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(
            icon,
            size: size,
            color: !p
                ? base
                : light
                ? base.withValues(alpha: .7)
                : Color.lerp(base, const Color(0xFF000000), .35),
          ),
        ),
      ),
    );
  }
}

/// One item of [SGlyphBottomNav].
class SNavGlyphItem {
  const SNavGlyphItem(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Bottom navigation (54dp) for glyph icons: selected 28dp #636363 / others
/// 22dp pale grey, exactly like the kit's [SBottomNav] — which only accepts its
/// own vector [SIcons].
class SGlyphBottomNav extends StatelessWidget {
  const SGlyphBottomNav({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  final List<SNavGlyphItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) => Container(
    height: 54,
    color: context.sp.card,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 48),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onTap(i),
            child: SizedBox(
              width: 38,
              height: 40,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SizedBox(
                    height: 28,
                    child: Center(
                      child: Icon(
                        items[i].icon,
                        size: i == currentIndex ? 28 : 22,
                        color: i == currentIndex
                            ? context.sp.titleOther
                            : context.sp.iconDisabled,
                      ),
                    ),
                  ),
                  Text(
                    items[i].label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      fontSize: 8,
                      height: 1.2,
                      color: i == currentIndex
                          ? context.sp.titleOther
                          : context.sp.subtitleOther,
                      fontFamilyFallback: const [
                        'Smartisan Compact',
                        'Inter',
                        'Noto Sans CJK SC',
                        'Microsoft YaHei',
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

/// Grouped-list card around a lazy list: the [SListGroup] chrome (white
/// surface, 0.8dp hairline border, 10dp radius, the kit's soft card shadow and
/// hairline row dividers) for folders that can hold hundreds of videos — the
/// kit's own group builds every row up front.
class SCardList extends StatelessWidget {
  const SCardList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.controller,
    this.padding = const EdgeInsets.fromLTRB(12, 8, 12, 24),
    this.maxWidth = 720,
  });

  final int itemCount;
  final NullableIndexedWidgetBuilder itemBuilder;
  final ScrollController? controller;
  final EdgeInsetsGeometry padding;

  /// Cards stay phone-sized and centred on a desktop window instead of
  /// stretching a row across the whole screen.
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(SRadii.button));
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: padding,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: context.sp.cardShadow,
            ),
            child: Material(
              color: context.sp.card,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: radius,
                side: BorderSide(color: context.sp.border, width: SHair.md),
              ),
              child: ListView.separated(
                controller: controller,
                padding: EdgeInsets.zero,
                itemCount: itemCount,
                itemBuilder: itemBuilder,
                separatorBuilder: (_, _) => const SDivider(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A card with side padding and the kit's shadow/border, for arbitrary content
/// (grids, previews) that isn't a list of rows.
class SCard extends StatelessWidget {
  const SCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.maxWidth = 720,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(SRadii.button));
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: padding,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: context.sp.cardShadow,
            ),
            child: Material(
              color: context.sp.card,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: radius,
                side: BorderSide(color: context.sp.border, width: SHair.md),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
