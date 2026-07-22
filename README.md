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
- Polished, theme-aware UI (neutral cool-gray light + near-black dark) with a
  single blue accent, Material 3, staggered list entries, and consistent
  loading / empty / error states
- One codebase for both Android and Windows

## Architecture
```
lib/
  main.dart                     # bootstrap + MediaKit.ensureInitialized
  app.dart                      # MaterialApp + auth gate
  config/auth_config.dart       # Azure client_id, tenant, scopes
  core/
    models/
      auth_tokens.dart          # token model
      drive_item.dart           # OneDrive item model (video/subtitle helpers)
    services/
      auth_service.dart         # device code flow + token refresh
      graph_service.dart        # Graph API (list children / streaming URL)
      subtitle_service.dart     # match external subtitles to a video
      token_storage.dart        # SharedPreferences persistence
      playback_progress_service.dart  # resume-position persistence
    theme/
      app_theme.dart            # cohesive light/dark theme + tabular figures
    widgets/
      states.dart               # EmptyState / ErrorState / LoadingState
      motion.dart               # FadeSlideIn staggered entrance
  providers/
    auth_provider.dart          # auth state (Riverpod StateNotifier)
    drive_provider.dart         # folder navigation state
    playback_provider.dart      # resume-position state (Riverpod)
  pages/
    login_page.dart             # device-code sign-in UI
    browser_page.dart           # file/folder browser
    player_page.dart            # media_kit video player + subtitle picker
```
Layers: UI → Riverpod providers → services (auth / graph) → models.

## Prerequisites
- Flutter 3.41+ (stable channel)
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

> `flutter analyze` passes with **no issues**, and `flutter test` passes
> (29/29: 15 resume-position + 13 subtitle-matching + 1 placeholder). A full
> native build was not completed during scaffolding (it can exceed an
> automated run's time limit); run `flutter run -d windows` /
> `flutter run -d android` to build and launch.
