/// Single import point for the vendored Smartisan OS kit in `lib/smartisan`.
///
/// The kit's own entry point (`smartisan_widgets.dart`) re-exports the
/// widgets, motion, icons, tabs and tokens, but not the palette extension that
/// gives `context.sp`, so every screen imports this file instead.
library;

export '../../smartisan/smartisan_accent.dart';
export '../../smartisan/smartisan_component_theme.dart';
export '../../smartisan/smartisan_material_theme.dart';
export '../../smartisan/smartisan_palette.dart';
export '../../smartisan/smartisan_widgets.dart';
