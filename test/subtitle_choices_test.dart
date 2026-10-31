import 'package:flutter_test/flutter_test.dart';
import 'package:onedrive_video_player/core/models/drive_item.dart';
import 'package:onedrive_video_player/pages/player/subtitle_choices.dart';

DriveItem _subtitleFile(String id, String name) =>
    DriveItem(id: id, name: name, isFolder: false);

List<String> _ids(List<ChoiceGroup> groups) => [
  for (final group in groups)
    for (final choice in group.choices) choice.id,
];

void main() {
  group('buildSubtitleChoices', () {
    test('always offers off and auto first', () {
      final groups = buildSubtitleChoices(embedded: const [], external: const []);

      expect(groups, hasLength(1));
      expect(groups.single.label, 'State');
      expect(groups.single.choices.map((c) => c.id), [
        subtitleOffId,
        subtitleAutoId,
      ]);
    });

    test('lists embedded tracks and skips mpv placeholders', () {
      final groups = buildSubtitleChoices(
        embedded: const [
          (id: 'auto', title: null, language: null),
          (id: 'no', title: null, language: null),
          (id: '1', title: 'English', language: 'en'),
          (id: '2', title: null, language: 'zh'),
        ],
        external: const [],
      );

      expect(_ids(groups), [
        subtitleOffId,
        subtitleAutoId,
        'embedded:1',
        'embedded:2',
      ]);
      final embedded = groups[1];
      expect(embedded.label, 'Embedded tracks');
      expect(embedded.choices.first.label, 'English');
      // No title: fall back to the language, then to the track id.
      expect(embedded.choices.last.label, 'zh');
    });

    test('labels a track without title or language by id', () {
      final groups = buildSubtitleChoices(
        embedded: const [(id: '7', title: null, language: null)],
        external: const [],
      );
      expect(groups[1].choices.single.label, 'Track 7');
    });

    test('lists external files with their names', () {
      final groups = buildSubtitleChoices(
        embedded: const [],
        external: [
          _subtitleFile('s1', 'Movie.zh.srt'),
          _subtitleFile('s2', 'Movie.en.ass'),
        ],
      );

      final external = groups.last;
      expect(external.label, 'External subtitles');
      expect(external.choices.map((c) => c.label), [
        'Movie.zh.srt',
        'Movie.en.ass',
      ]);
      expect(external.choices.first.id, 'external:s1');
      expect(external.choices.first.kind, ChoiceKind.external);
    });

    test('drops empty groups but keeps the order', () {
      final groups = buildSubtitleChoices(
        embedded: const [],
        external: [_subtitleFile('s1', 'a.srt')],
      );
      expect(groups.map((g) => g.label), ['State', 'External subtitles']);
    });
  });

  group('buildAudioChoices', () {
    test('skips placeholders and returns no group when empty', () {
      expect(
        buildAudioChoices(const [(id: 'auto', title: null, language: null)]),
        isEmpty,
      );
    });

    test('lists real tracks', () {
      final groups = buildAudioChoices(const [
        (id: 'no', title: null, language: null),
        (id: '1', title: 'Japanese 5.1', language: 'ja'),
      ]);
      expect(groups.single.label, 'Tracks');
      expect(groups.single.choices.single.id, 'audio:1');
      expect(groups.single.choices.single.kind, ChoiceKind.audio);
    });
  });

  group('Choice ids', () {
    test('encode and decode their target', () {
      const embedded = Choice(
        id: 'embedded:42',
        label: 'x',
        kind: ChoiceKind.embedded,
      );
      const external = Choice(
        id: 'external:item-9',
        label: 'y',
        kind: ChoiceKind.external,
      );
      const audio = Choice(id: 'audio:3', label: 'z', kind: ChoiceKind.audio);
      const off = Choice(
        id: subtitleOffId,
        label: 'Off',
        kind: ChoiceKind.off,
      );

      expect(embedded.targetId, '42');
      expect(external.targetId, 'item-9');
      expect(audio.targetId, '3');
      expect(off.targetId, isNull);
      expect(
        embeddedChoiceId('42'),
        'embedded:42',
      );
      expect(externalChoiceId('item-9'), 'external:item-9');
      expect(audioChoiceId('3'), 'audio:3');
    });

    test('distinguish subtitle choices from audio ones', () {
      expect(isSubtitleChoiceId(subtitleOffId), isTrue);
      expect(isSubtitleChoiceId(subtitleAutoId), isTrue);
      expect(isSubtitleChoiceId('embedded:1'), isTrue);
      expect(isSubtitleChoiceId('external:s1'), isTrue);
      expect(isSubtitleChoiceId('audio:1'), isFalse);
      expect(isSubtitleChoiceId('nonsense'), isFalse);
    });
  });
}
