import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit_video/media_kit_video_controls/media_kit_video_controls.dart' as controls;

/// A [VideoControlsBuilder] that renders the default Material controls but
/// inserts subtitle, speed, and lock buttons into the bottom button bar.
///
/// Desktop (Windows/macOS/Linux) and mobile (Android/iOS) get the matching
/// control set with the extra buttons injected before the fullscreen button.
VideoControlsBuilder subtitleVideoControlsBuilder({
  required VoidCallback onSubtitleTap,
  required VoidCallback onSpeedTap,
  VoidCallback? onAudioTap,
  VoidCallback? onLockTap,
  bool locked = false,
}) {
  return (state) => _SubtitleVideoControls(
    state: state,
    onSubtitleTap: onSubtitleTap,
    onSpeedTap: onSpeedTap,
    onAudioTap: onAudioTap,
    onLockTap: onLockTap,
    locked: locked,
  );
}

class _SubtitleVideoControls extends StatelessWidget {
  const _SubtitleVideoControls({
    required this.state,
    required this.onSubtitleTap,
    required this.onSpeedTap,
    this.onAudioTap,
    this.onLockTap,
    this.locked = false,
  });

  final VideoState state;
  final VoidCallback onSubtitleTap;
  final VoidCallback onSpeedTap;
  final VoidCallback? onAudioTap;
  final VoidCallback? onLockTap;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final isDesktop = switch (defaultTargetPlatform) {
      TargetPlatform.windows ||
      TargetPlatform.macOS ||
      TargetPlatform.linux =>
        true,
      _ => false,
    };

    if (isDesktop) {
      final data = controls.MaterialDesktopVideoControlsThemeData(
        bottomButtonBar: [
          const controls.MaterialDesktopSkipPreviousButton(),
          const controls.MaterialDesktopPlayOrPauseButton(),
          const controls.MaterialDesktopSkipNextButton(),
          const controls.MaterialDesktopVolumeButton(),
          const controls.MaterialDesktopPositionIndicator(),
          const Spacer(),
          if (onAudioTap != null)
            controls.MaterialDesktopCustomButton(
              icon: const Icon(Icons.audiotrack_rounded),
              onPressed: onAudioTap!,
            ),
          controls.MaterialDesktopCustomButton(
            icon: const Icon(Icons.subtitles_rounded),
            onPressed: onSubtitleTap,
          ),
          controls.MaterialDesktopCustomButton(
            icon: const Icon(Icons.speed_rounded),
            onPressed: onSpeedTap,
          ),
          const controls.MaterialDesktopFullscreenButton(),
        ],
      );
      return controls.MaterialDesktopVideoControlsTheme(
        normal: data,
        fullscreen: data,
        child: controls.MaterialDesktopVideoControls(state),
      );
    }

    final data = controls.MaterialVideoControlsThemeData(
      bottomButtonBar: [
        const controls.MaterialPositionIndicator(),
        const Spacer(),
        if (onLockTap != null)
          controls.MaterialCustomButton(
            icon: Icon(locked
                ? Icons.lock_rounded
                : Icons.lock_open_rounded),
            onPressed: onLockTap!,
          ),
        if (onAudioTap != null)
          controls.MaterialCustomButton(
            icon: const Icon(Icons.audiotrack_rounded),
            onPressed: onAudioTap!,
          ),
        controls.MaterialCustomButton(
          icon: const Icon(Icons.subtitles_rounded),
          onPressed: onSubtitleTap,
        ),
        controls.MaterialCustomButton(
          icon: const Icon(Icons.speed_rounded),
          onPressed: onSpeedTap,
        ),
        const controls.MaterialFullscreenButton(),
      ],
    );
    return controls.MaterialVideoControlsTheme(
      normal: data,
      fullscreen: data,
      child: controls.MaterialVideoControls(state),
    );
  }
}