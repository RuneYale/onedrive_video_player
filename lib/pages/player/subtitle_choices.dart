import '../../core/models/drive_item.dart';

/// What a row in the player's subtitle / audio dialog represents.
enum ChoiceKind { off, auto, embedded, external, audio }

/// One row of the player's choice dialog.
///
/// Choices are identified by stable strings (`off`, `auto`,
/// `embedded:<trackId>`, `external:<itemId>`, `audio:<trackId>`) so the picked
/// value can be persisted and restored across sessions.
class Choice {
  const Choice({required this.id, required this.label, required this.kind});

  final String id;
  final String label;
  final ChoiceKind kind;

  /// The track / drive-item id this choice points at, if any.
  String? get targetId => switch (kind) {
    ChoiceKind.embedded => id.substring(_embeddedPrefix.length),
    ChoiceKind.external => id.substring(_externalPrefix.length),
    ChoiceKind.audio => id.substring(_audioPrefix.length),
    ChoiceKind.off || ChoiceKind.auto => null,
  };
}

class ChoiceGroup {
  const ChoiceGroup(this.label, this.choices);

  final String label;
  final List<Choice> choices;
}

const subtitleOffId = 'off';
const subtitleAutoId = 'auto';

const _embeddedPrefix = 'embedded:';
const _externalPrefix = 'external:';
const _audioPrefix = 'audio:';

String embeddedChoiceId(String trackId) => '$_embeddedPrefix$trackId';
String externalChoiceId(String itemId) => '$_externalPrefix$itemId';
String audioChoiceId(String trackId) => '$_audioPrefix$trackId';

/// True when the id is one of the subtitle choices (not an audio one).
bool isSubtitleChoiceId(String id) =>
    id == subtitleOffId ||
    id == subtitleAutoId ||
    id.startsWith(_embeddedPrefix) ||
    id.startsWith(_externalPrefix);

/// A player-reported track, reduced to what the dialog needs.
typedef TrackInfo = ({String id, String? title, String? language});

String trackLabel(TrackInfo track) =>
    track.title ?? track.language ?? 'Track ${track.id}';

/// libmpv reports placeholder tracks with these ids; they are never listed.
bool _isPlaceholder(String id) => id == 'auto' || id == 'no';

/// Subtitle choices in display order: state first, then embedded tracks, then
/// external files. Empty groups are dropped so the dialog stays short.
List<ChoiceGroup> buildSubtitleChoices({
  required List<TrackInfo> embedded,
  required List<DriveItem> external,
}) {
  final embeddedChoices = <Choice>[
    for (final track in embedded)
      if (!_isPlaceholder(track.id))
        Choice(
          id: embeddedChoiceId(track.id),
          label: trackLabel(track),
          kind: ChoiceKind.embedded,
        ),
  ];
  final externalChoices = <Choice>[
    for (final item in external)
      Choice(
        id: externalChoiceId(item.id),
        label: item.name,
        kind: ChoiceKind.external,
      ),
  ];

  return <ChoiceGroup>[
    const ChoiceGroup('State', [
      Choice(id: subtitleOffId, label: 'Off', kind: ChoiceKind.off),
      Choice(id: subtitleAutoId, label: 'Auto', kind: ChoiceKind.auto),
    ]),
    if (embeddedChoices.isNotEmpty)
      ChoiceGroup('Embedded tracks', embeddedChoices),
    if (externalChoices.isNotEmpty)
      ChoiceGroup('External subtitles', externalChoices),
  ];
}

/// Audio choices (no on/off state: mpv always has at least one track).
List<ChoiceGroup> buildAudioChoices(List<TrackInfo> tracks) {
  final choices = <Choice>[
    for (final track in tracks)
      if (!_isPlaceholder(track.id))
        Choice(
          id: audioChoiceId(track.id),
          label: trackLabel(track),
          kind: ChoiceKind.audio,
        ),
  ];
  return <ChoiceGroup>[
    if (choices.isNotEmpty) ChoiceGroup('Tracks', choices),
  ];
}
