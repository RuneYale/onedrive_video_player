# Vendored: Smartisan OS UI Kit (Unofficial) — Flutter port

These files are **not written by this project**. They are the Flutter kit
shipped with the `smartisan-ui` skill, copied verbatim (except for the three
patches below) so the whole app can follow Smartisan OS without depending on a
third-party package.

## Source and license

- **Smartisan OS UI Kit (Unofficial)** by **Paix Chan**,
  <https://www.figma.com/community/file/1419385240874679870>,
  licensed **CC BY 4.0**.
- Measurements and motion values were taken from a Smartisan R2 running
  Smartisan OS 8.5.3.
- `smartisan_glyphs.dart` + `assets/fonts/smartisan_glyphs.ttf` are generated
  from **Phosphor Icons** (MIT).

See `THIRD_PARTY_NOTICES.md` at the repository root.

## Files

| File | Contents |
|---|---|
| `smartisan_theme.dart` | kit tokens (`SColors`, `SGradients`, `SShadows`, `SRadii`, `SText`, `SDims`) |
| `smartisan_palette.dart` | light/dark `SPalette` theme extension (`context.sp`) |
| `smartisan_component_theme.dart` | derived component colours |
| `smartisan_material_theme.dart` | full `ThemeData` (`SmartisanMaterialTheme.build`) |
| `smartisan_widgets.dart` | `S*` components (bars, buttons, lists, switch, slider, dialog, sheet, wheel, menu…) |
| `smartisan_adapters.dart` | `SmartisanTile`, `SmartisanListSection`, `SmartisanSwitch` |
| `smartisan_bars.dart` | brand bar, pinstripe page, section gap |
| `smartisan_interaction.dart` | swipe-right row, quick bar, empty state, check circle, part switcher |
| `smartisan_motion.dart` | `SMotion`, `SPageRoute`, `SModalPageRoute`, `SDialogRoute`, scroll behaviour |
| `smartisan_tabs.dart` | `SmartisanTabBar` |
| `smartisan_icons.dart` | 23 vector icons (`SIcons`) |
| `smartisan_glyphs.dart` | 166 glyph font icons (`SGlyphs`) |
| `smartisan_accent.dart` | accent presets + HSL helpers |

`lib/core/theme/smartisan_kit.dart` re-exports this directory (plus the palette
extension) as the app's single import.

## Local patches (re-apply when updating the kit)

1. **`smartisan_widgets.dart` — `SAppBar`**: the title is `maxLines: 1` with
   ellipsis so long OneDrive file/folder names cannot push it out of the 48dp
   bar.
2. **`smartisan_widgets.dart` — `SPopupMenu`**: menu labels are wrapped in
   `Expanded` with ellipsis, for long English labels.
3. **`smartisan_interaction.dart` / `smartisan_widgets.dart`**: four
   fire-and-forget `HapticFeedback` / animation futures are wrapped in
   `unawaited(...)` to satisfy this project's `discarded_futures` lint.

`analysis_options.yaml` excludes this directory from analysis because of those
style differences; the code is still compiled by every build.
