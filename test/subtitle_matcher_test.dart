import 'package:flutter_test/flutter_test.dart';

import 'package:onedrive_video_player/core/models/drive_item.dart';
import 'package:onedrive_video_player/core/services/subtitle_service.dart';

DriveItem _file(String name, {String? id, bool folder = false}) {
  return DriveItem(id: id ?? name, name: name, isFolder: folder, size: 1234);
}

void main() {
  const matcher = SubtitleMatcher();
  const resolver = SubtitleLanguageResolver();

  group('SubtitleMatcher.matchCounts', () {
    test('counts equal per-video match() results', () {
      final items = [
        _file('Movie.mp4', id: 'v1'),
        _file('Movie.srt', id: 's1'),
        _file('Movie.en.srt', id: 's2'),
        _file('Show.EP01.mkv', id: 'v2'),
        _file('show.ep01.zh-Hans.ass', id: 's3'),
        _file('Other.mp4', id: 'v3'),
        _file('unrelated.srt', id: 's4'),
      ];
      final counts = matcher.matchCounts(items);
      for (final video in items.where((i) => i.isVideo)) {
        expect(
          counts[video.id],
          matcher.match(video, items).length,
          reason: video.name,
        );
      }
    });

    test('one subtitle can count for multiple videos', () {
      final items = [
        _file('Movie.mp4', id: 'v1'),
        _file('Movie.En.mp4', id: 'v2'),
        _file('movie.en.srt', id: 's1'),
      ];
      final counts = matcher.matchCounts(items);
      // movie.en matches 'movie' (language tag) and 'movie.en' (exact).
      expect(counts['v1'], 1);
      expect(counts['v2'], 1);
    });

    test('only videos get counts; folders and non-videos are skipped', () {
      final items = [
        _file('docs', id: 'f1', folder: true),
        _file('notes.txt', id: 't1'),
        _file('Movie.mp4', id: 'v1'),
      ];
      final counts = matcher.matchCounts(items);
      expect(counts.keys, ['v1']);
      expect(counts['v1'], 0);
    });
  });

  group('SubtitleMatcher.match', () {
    test('exact base-name match (Movie.mp4 ↔ Movie.srt)', () {
      final siblings = [
        _file('Movie.mp4', id: 'v1'),
        _file('Movie.srt', id: 's1'),
      ];
      final result = matcher.match(siblings[0], siblings);
      expect(result.map((e) => e.id), ['s1']);
    });

    test('language-tagged subtitle matches (Movie.mp4 ↔ Movie.en.srt)', () {
      final siblings = [
        _file('Movie.mp4', id: 'v1'),
        _file('Movie.en.srt', id: 's1'),
        _file('Movie.zh.vtt', id: 's2'),
      ];
      final result = matcher.match(siblings[0], siblings);
      expect(result.map((e) => e.id), ['s1', 's2']);
    });

    test('matches multiple formats and sorts alphabetically', () {
      final siblings = [
        _file('Show.mkv', id: 'v1'),
        _file('Show.zh.srt', id: 's_zh'),
        _file('Show.en.srt', id: 's_en'),
        _file('Show.ass', id: 's_ass'),
      ];
      final result = matcher.match(siblings[0], siblings);
      // Alphabetical, case-insensitive: Show.ass, Show.en.srt, Show.zh.srt
      expect(result.map((e) => e.id), ['s_ass', 's_en', 's_zh']);
    });

    test('case-insensitive matching', () {
      final siblings = [
        _file('MOVIE.mp4', id: 'v1'),
        _file('movie.srt', id: 's1'),
        _file('Movie.EN.VTT', id: 's2'),
      ];
      final result = matcher.match(siblings[0], siblings);
      // Sorted alphabetically by lower-cased name: 'movie.en.vtt' < 'movie.srt'.
      expect(result.map((e) => e.id), ['s2', 's1']);
    });

    test('does not match a different file (Ab.srt is not for A.mp4)', () {
      final siblings = [_file('A.mp4', id: 'v1'), _file('Ab.srt', id: 's1')];
      final result = matcher.match(siblings[0], siblings);
      expect(result, isEmpty);
    });

    test('does not match subtitles of another video', () {
      final siblings = [
        _file('A.mp4', id: 'v1'),
        _file('B.mp4', id: 'v2'),
        _file('B.srt', id: 's_b'),
      ];
      final result = matcher.match(siblings[0], siblings);
      expect(result, isEmpty);
    });

    test('only subtitle extensions are considered', () {
      final siblings = [
        _file('Movie.mp4', id: 'v1'),
        _file('Movie.txt', id: 't1'), // not a subtitle
        _file('Movie.jpg', id: 'i1'), // not a subtitle
        _file('Movie.srt', id: 's1'),
      ];
      final result = matcher.match(siblings[0], siblings);
      expect(result.map((e) => e.id), ['s1']);
    });

    test('ignores folders even if named like a subtitle', () {
      final siblings = [
        _file('Movie.mp4', id: 'v1'),
        _file('Movie.srt', id: 'f1', folder: true),
      ];
      final result = matcher.match(siblings[0], siblings);
      expect(result, isEmpty);
    });

    test('returns empty for a folder video', () {
      final siblings = [
        _file('Folder', id: 'folder1', folder: true),
        _file('Folder.srt', id: 's1'),
      ];
      final result = matcher.match(siblings[0], siblings);
      expect(result, isEmpty);
    });

    test('returns empty when no siblings match', () {
      final video = _file('Lonely.mp4', id: 'v1');
      expect(matcher.match(video, const []), isEmpty);
    });
  });

  group('DriveItem subtitle helpers', () {
    test('isSubtitle true for supported extensions', () {
      for (final n in [
        'a.srt',
        'b.vtt',
        'c.ass',
        'D.SSA',
        'e.sub',
        'f.smi',
        'g.sbv',
      ]) {
        expect(_file(n).isSubtitle, isTrue, reason: n);
      }
    });

    test('isSubtitle false for non-subtitle extensions and folders', () {
      expect(_file('a.mp4').isSubtitle, isFalse);
      expect(_file('a.txt').isSubtitle, isFalse);
      expect(_file('a.srt', folder: true).isSubtitle, isFalse);
    });

    test('baseName strips final extension and lower-cases', () {
      expect(_file('Movie.mp4').baseName, 'movie');
      expect(_file('Movie.EN.SRT').baseName, 'movie.en');
      expect(_file('noext').baseName, 'noext');
    });
  });

  group('SubtitleLanguageResolver.labelOf', () {
    test('exact-name match has no language tag', () {
      final video = _file('Movie.mp4', id: 'v');
      expect(resolver.labelOf(video, _file('Movie.srt')), isNull);
    });

    test('recognizes common language codes', () {
      final video = _file('Movie.mp4', id: 'v');
      expect(resolver.labelOf(video, _file('Movie.en.srt')), 'English');
      expect(resolver.labelOf(video, _file('Movie.eng.srt')), 'English');
      expect(resolver.labelOf(video, _file('Movie.zh.vtt')), 'Chinese');
      expect(resolver.labelOf(video, _file('Movie.ja.ass')), 'Japanese');
      expect(resolver.labelOf(video, _file('Movie.fr.srt')), 'French');
    });

    test('recognizes script subtags (zh-Hans → Chinese (Simplified))', () {
      final video = _file('Movie.mp4', id: 'v');
      expect(
        resolver.labelOf(video, _file('Movie.zh-Hans.srt')),
        'Chinese (Simplified)',
      );
      expect(
        resolver.labelOf(video, _file('Movie.cht.srt')),
        'Chinese (Traditional)',
      );
    });

    test('finds language among multiple tag segments', () {
      final video = _file('Show.S02E01.mp4', id: 'v');
      expect(resolver.labelOf(video, _file('Show.S02E01.eng.srt')), 'English');
    });

    test('appends (forced) qualifier', () {
      final video = _file('Movie.mp4', id: 'v');
      expect(
        resolver.labelOf(video, _file('Movie.en.forced.srt')),
        'English (forced)',
      );
    });

    test('appends (SDH) qualifier for sdh', () {
      final video = _file('Movie.mp4', id: 'v');
      expect(
        resolver.labelOf(video, _file('Movie.en.sdh.srt')),
        'English (SDH)',
      );
    });

    test('treats hi as SDH only alongside another language', () {
      final video = _file('Movie.mp4', id: 'v');
      expect(
        resolver.labelOf(video, _file('Movie.en.hi.srt')),
        'English (SDH)',
      );
      // 'hi' alone resolves to Hindi, not SDH.
      expect(resolver.labelOf(video, _file('Movie.hi.srt')), 'Hindi');
    });

    test('unknown tag yields null', () {
      final video = _file('Movie.mp4', id: 'v');
      expect(resolver.labelOf(video, _file('Movie.xyz.srt')), isNull);
    });

    test('case-insensitive', () {
      final video = _file('MOVIE.MP4', id: 'v');
      expect(resolver.labelOf(video, _file('Movie.EN.SRT')), 'English');
    });
  });

  group('SubtitleLanguageResolver.nameOfCode', () {
    test('maps ISO 639-1 and 639-2 codes', () {
      expect(resolver.nameOfCode('en'), 'English');
      expect(resolver.nameOfCode('eng'), 'English');
      expect(resolver.nameOfCode('jpn'), 'Japanese');
      expect(resolver.nameOfCode('fra'), 'French');
    });

    test('maps exact script-subtag codes', () {
      expect(resolver.nameOfCode('zh-Hans'), 'Chinese (Simplified)');
      expect(resolver.nameOfCode('zh-Hant'), 'Chinese (Traditional)');
    });

    test('falls back to primary subtag for other region codes', () {
      expect(resolver.nameOfCode('en-US'), 'English');
      expect(resolver.nameOfCode('fr-CA'), 'French');
      expect(resolver.nameOfCode('ja-JP'), 'Japanese');
    });

    test('null / empty / unknown yield null', () {
      expect(resolver.nameOfCode(null), isNull);
      expect(resolver.nameOfCode(''), isNull);
      expect(resolver.nameOfCode('xyz'), isNull);
    });

    test('case-insensitive', () {
      expect(resolver.nameOfCode('ENG'), 'English');
      expect(resolver.nameOfCode('JA'), 'Japanese');
    });
  });

  group('SubtitleMatcher.pickForAutoLoad', () {
    test('prefers Simplified Chinese over Traditional and English', () {
      final video = _file('Movie.mp4', id: 'v');
      final subs = [
        _file('Movie.en.srt', id: 's-en'),
        _file('Movie.zh-Hant.ass', id: 's-zhant'),
        _file('Movie.zh-Hans.ass', id: 's-zhans'),
      ];
      expect(matcher.pickForAutoLoad(video, subs)?.id, 's-zhans');
    });

    test('plain zh and chs/zho/chi variants count as Simplified', () {
      final video = _file('Movie.mp4', id: 'v');
      for (final tag in ['zh', 'zh-cn', 'chs', 'zho', 'chi']) {
        final subs = [
          _file('Movie.en.srt', id: 's-en'),
          _file('Movie.$tag.srt', id: 's-$tag'),
        ];
        expect(matcher.pickForAutoLoad(video, subs)?.id, 's-$tag', reason: tag);
      }
    });

    test('prefers Traditional Chinese over other languages', () {
      final video = _file('Movie.mp4', id: 'v');
      final subs = [
        _file('Movie.en.srt', id: 's-en'),
        _file('Movie.cht.srt', id: 's-cht'),
      ];
      expect(matcher.pickForAutoLoad(video, subs)?.id, 's-cht');
    });

    test('falls back to an untagged subtitle when no Chinese exists', () {
      final video = _file('Movie.mp4', id: 'v');
      final subs = [
        _file('Movie.en.srt', id: 's-en'),
        _file('Movie.srt', id: 's-plain'),
      ];
      expect(matcher.pickForAutoLoad(video, subs)?.id, 's-plain');
    });

    test('falls back to another tagged language when nothing else matches', () {
      final video = _file('Movie.mp4', id: 'v');
      final subs = [
        _file('Movie.fr.srt', id: 's-fr'),
        _file('Movie.de.srt', id: 's-de'),
      ];
      expect(matcher.pickForAutoLoad(video, subs)?.id, 's-de');
    });

    test('prefers non-forced over forced within the same tier', () {
      final video = _file('Movie.mp4', id: 'v');
      final subs = [
        _file('Movie.zh-Hans.forced.srt', id: 's-forced'),
        _file('Movie.zh-Hans.srt', id: 's-normal'),
      ];
      expect(matcher.pickForAutoLoad(video, subs)?.id, 's-normal');
    });

    test('forced Simplified Chinese still beats a plain English sub', () {
      final video = _file('Movie.mp4', id: 'v');
      final subs = [
        _file('Movie.en.srt', id: 's-en'),
        _file('Movie.zh-Hans.forced.srt', id: 's-forced'),
      ];
      expect(matcher.pickForAutoLoad(video, subs)?.id, 's-forced');
    });

    test('returns null when nothing matches', () {
      final video = _file('Movie.mp4', id: 'v');
      expect(
        matcher.pickForAutoLoad(video, [_file('Other.srt', id: 'x')]),
        isNull,
      );
      expect(matcher.pickForAutoLoad(video, const []), isNull);
    });

    test('does not pick folders or non-subtitle files', () {
      final video = _file('Movie.mp4', id: 'v');
      final subs = [
        _file('Movie.txt', id: 's-txt'),
        _file('subs', id: 's-folder', folder: true),
        _file('Movie.zh-Hans.ass', id: 's-good'),
      ];
      expect(matcher.pickForAutoLoad(video, subs)?.id, 's-good');
    });
  });
}
