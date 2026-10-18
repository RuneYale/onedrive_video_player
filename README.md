# OneDrive Video Player

A cross-platform (Android + Windows) Flutter app that plays the videos stored
in your OneDrive — folder browsing plus streaming playback powered by
`media_kit` (libmpv).

## Features
- Sign in with a Microsoft account (OAuth 2.0 **device code flow**)
- Browse OneDrive folders; video files are highlighted
- Stream videos directly (no full download) with seek support
- Stays signed in across restarts (tokens persisted + auto-refreshed)
- **Resume playback**: remembers where you left off and auto-seeks back on
  reopen; in-progress videos show a "Resume from mm:ss" label and a progress
  bar in the browser (long-press a video to clear its resume position)
- **Subtitles**: pick embedded tracks or external subtitle files (`.srt` /
  `.vtt` / `.ass` / `.ssa` / `.sub` / `.smi` / `.sbv`) stored next to the
  video. Matching is by file-name base (`Movie.en.srt` → `Movie.mp4`); files
  are streamed over HTTP — no local download. The subtitle button lives in the
  video controls bar (next to fullscreen). Videos with available subtitles
  show a count badge in the browser
- **Customizable subtitle appearance**: font size, weight, text color,
  background (on/off + color), and outline (on/off + color + width). Choices
  are previewed live and persisted across restarts
- **Smartisan OS (锤子 / 坚果) UI**: flat `#F5F5F5` page with white grouped
  cards, hairline 0.8dp borders, one low-saturation blue accent, centred bar
  titles, a 54dp bottom navigation, segmented tabs, an inset slider, a real
  wheel picker for playback speed, swipe-right-to-remove rows, a spring on
  held bar icons, and horizontal push / rise-from-bottom page transitions
  (no ripples, no Material leftovers)
- One codebase for both Android and Windows

## Architecture
```
lib/
  main.dart                     # bootstrap + MediaKit.ensureInitialized
  app.dart                      # MaterialApp (Smartisan theme) + auth gate
  smartisan/                    # vendored Smartisan OS UI kit (Flutter)
    smartisan_widgets.dart      #   S* components (bar, buttons, lists, dialog…)
    smartisan_palette.dart      #   light / dark palette + context.sp
    smartisan_material_theme.dart # full ThemeData (no splash, inset slider…)
    smartisan_motion.dart       # SPageRoute / SModalPageRoute / SDialogRoute
    smartisan_glyphs.dart       #   166 solid glyphs (SGlyphs)
  config/auth_config.dart       # Azure client_id, tenant, scopes
  core/
    models/
      auth_tokens.dart          # token model
      drive_item.dart           # OneDrive item model (video/subtitle helpers)
      subtitle_style.dart       # subtitle appearance + persistence
    services/
      auth_service.dart         # device code flow + token refresh
      graph_service.dart        # Graph API (list children / streaming URL)
      subtitle_service.dart     # match external subtitles to a video
      token_storage.dart        # SharedPreferences persistence
      playback_progress_service.dart  # resume-position persistence
    theme/
      smartisan_kit.dart        # one import for the whole kit
      app_theme.dart            # accent + light/dark themes + player surface
    utils/format.dart           # duration / size / relative time
    widgets/
      smartisan_extras.dart     # glyph bar button, bottom nav, lazy card list
      dialogs.dart              # confirm dialog, context menu
      video_thumb.dart          # 16:9 row thumbnail
      states.dart               # EmptyState / ErrorState / LoadingState
  providers/
    auth_provider.dart          # auth state (Riverpod Notifier)
    drive_provider.dart         # folder navigation state
    playback_provider.dart      # resume-position state
    folder_provider.dart        # chosen video-library folder
    subtitle_style_provider.dart
  pages/
    login_page.dart             # device-code sign-in UI
    home_page.dart              # shell: Videos / Recent / Settings tabs
    browser_page.dart           # OneDrive folder browser
    recent_page.dart            # recently played (swipe right to remove)
    settings_page.dart          # account, folder, subtitle look, sign out
    folder_picker_page.dart     # video-library root picker
    player_page.dart            # media_kit player + subtitle/audio/speed
  widgets/
    subtitle_controls.dart      # player control bar (Smartisan glyphs)
    player_gesture_overlay.dart # seek / brightness / volume drags
    speed_picker.dart           # wheel-picker bottom sheet
    subtitle_style_editor.dart  # full-screen subtitle appearance editor
```
Layers: UI → Riverpod providers → services (auth / graph) → models.

## Design language

The UI follows Smartisan OS: a flat grey page, white grouped cards with 0.8dp
hairlines and a soft shadow, a grey text hierarchy (never pure black), and a
single low-saturation blue accent used for buttons, switches, sliders, selected
rows and links. Presses change colour instantly — there is no ripple, no
hover-scale and no Material component left in the app.

The component kit vendored in `lib/smartisan/` comes from the
[Smartisan OS UI Kit (Unofficial)](https://www.figma.com/community/file/1419385240874679870)
by **Paix Chan**, licensed **CC BY 4.0**, and was measured against a real
Smartisan R2. The glyph font `assets/fonts/smartisan_glyphs.ttf` is generated
from **Phosphor Icons** (MIT).

Rendered screens of every page (light + dark) live in
[`docs/screenshots/`](docs/screenshots).

## Prerequisites
- Flutter 3.47+ (stable channel)
- **Windows**: Visual Studio 2022 with the "Desktop development with C++" workload
- **Android**: Android SDK (API 21+); Android Studio recommended (provides JDK)

## 1. Register an Azure app (required once)
1. https://portal.azure.com → Microsoft Entra ID → App registrations → New registration.
2. Supported account types: **"Accounts in any organizational directory and
   personal Microsoft accounts"** (lets both personal & work/school OneDrive work).
3. Redirect URI: choose **"Public client/native (mobile & desktop)"** and add
   none — the device code flow needs no redirect URI.
4. Authentication → Advanced settings → **"Allow public client flows" = Yes**.
5. Copy the **Application (client) ID**.

## 2. Configure the app
Open `lib/config/auth_config.dart` and set your client id:
```dart
static const String clientId = 'YOUR_COPIED_CLIENT_ID';
```
Optionally change `tenant` to `consumers` (personal accounts only).

## 3. Run
Windows desktop:
```
flutter run -d windows
```
Android (connect a device or start an emulator):
```
flutter run -d android
```

## How it works
- **Auth (device code flow)**: the app shows a code; you visit
  `microsoft.com/devicelogin` on any device and enter it. Identical on both
  platforms — no redirect URIs, intent filters, or WebView2 dependency. Tokens
  (including a refresh token) are stored locally and auto-refreshed.
- **Browsing**: `GET /me/drive/items/{id}/children` via Microsoft Graph.
- **Playback**: `GET /me/drive/items/{id}/content` is followed (HTTP 302) to a
  short-lived pre-authenticated CDN URL, handed straight to `media_kit` (libmpv),
  which streams with HTTP Range requests so seeking works without downloading
  the whole file.

## Scopes
`Files.Read` (read OneDrive), `offline_access` (refresh token),
`User.Read` (display the signed-in user's name).

## Roadmap / ideas
- ✅ Resume playback position (断点续播) — done
- ✅ Subtitle picker / external subtitle support — done
- Search and "recently played"
- Thumbnails / poster wall (刮削 metadata)
- Multiple accounts

> `flutter analyze` passes with **no issues**, `flutter test` passes
> (**89/89**, including layout smoke tests for every screen at phone and
> desktop widths), and `flutter build windows --debug` completes. Android has
> not been run on a device yet — run `flutter run -d android` to build and
> launch.
