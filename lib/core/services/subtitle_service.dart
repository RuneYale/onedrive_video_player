import '../models/drive_item.dart';

/// Matches external subtitle files to a video by file-name base.
///
/// Convention: a subtitle belongs to a video when its base name (file name
/// without the final extension, lower-cased) equals the video's base name, or
/// extends it with a language/tag segment. Examples for `Movie.mp4`:
///   `Movie.srt`      → base `movie`     == `movie`        ✓ exact
///   `Movie.en.srt`   → base `movie.en`  starts `movie.`   ✓ language tag
///   `Movie.en.srt`   → matches `Movie.mp4`
///   `Ab.srt`         → base `ab`        does not match `a` ✗
///
/// This is pure logic with no I/O, so it is unit-testable in isolation.
class SubtitleMatcher {
  const SubtitleMatcher();

  /// Returns the external subtitle [DriveItem]s in [siblings] that match
  /// [video], sorted alphabetically (case-insensitive) for a stable picker.
  List<DriveItem> match(DriveItem video, List<DriveItem> siblings) {
    if (video.isFolder) return const [];
    final videoBase = video.baseName;
    final prefix = '$videoBase.';
    final result = siblings
        .where(
          (s) =>
              s.isSubtitle &&
              (s.baseName == videoBase || s.baseName.startsWith(prefix)),
        )
        .toList();
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  /// Counts, for every video in [items], how many external subtitles match
  /// it — equivalent to running [match] per video, but in a single pass.
  ///
  /// A subtitle with base name `b` matches videos whose base name is `b`
  /// itself (exact) or any dot-delimited prefix of `b` (language/tag
  /// segments), so per-base-name counts are accumulated in
  /// O(total name length) instead of O(videos × items).
  Map<String, int> matchCounts(List<DriveItem> items) {
    final byBaseName = <String, int>{};
    for (final s in items) {
      if (!s.isSubtitle) continue;
      final base = s.baseName;
      byBaseName.update(base, (c) => c + 1, ifAbsent: () => 1);
      for (var i = 0; i < base.length; i++) {
        if (base[i] == '.') {
          byBaseName.update(
            base.substring(0, i),
            (c) => c + 1,
            ifAbsent: () => 1,
          );
        }
      }
    }
    return {
      for (final item in items)
        if (item.isVideo) item.id: byBaseName[item.baseName] ?? 0,
    };
  }

  /// The best matching subtitle for [video] to load automatically, or
  /// `null` when no external subtitle matches.
  ///
  /// Preference order:
  ///   1. Simplified Chinese (`zh` / `zh-Hans` / `zh-CN` / `chs` / `zho` / `chi`)
  ///   2. Traditional Chinese (`zh-Hant` / `zh-TW` / `cht`)
  ///   3. Untagged subtitle (base name equals the video's)
  ///   4. Any other language-tagged subtitle
  ///
  /// Within a tier, non-forced and non-SDH variants win, then alphabetical.
  DriveItem? pickForAutoLoad(DriveItem video, List<DriveItem> siblings) {
    const simplified = <String>{'zh', 'zho', 'chi', 'zh-hans', 'zh-cn', 'chs'};
    const traditional = <String>{'zh-hant', 'zh-tw', 'cht'};
    const resolver = SubtitleLanguageResolver();

    int tier(DriveItem s) {
      final tag = resolver.tagOf(video, s);
      if (tag != null && simplified.contains(tag)) return 0;
      if (tag != null && traditional.contains(tag)) return 1;
      if (tag == null) return 2; // Untagged — likely the original language.
      return 3;
    }

    int forcedPenalty(DriveItem s) =>
        resolver.tagOf(video, s) != null &&
            s.baseName.toLowerCase().endsWith('.forced')
        ? 1
        : 0;
    int sdhPenalty(DriveItem s) =>
        s.baseName.toLowerCase().endsWith('.sdh') ? 1 : 0;

    DriveItem? best;
    int bestTier = 4;
    int bestForced = 0;
    int bestSdh = 0;
    for (final s in match(video, siblings)) {
      final t = tier(s);
      final f = forcedPenalty(s);
      final h = sdhPenalty(s);
      final better =
          best == null ||
          t < bestTier ||
          (t == bestTier &&
              (f < bestForced ||
                  (f == bestForced &&
                      (h < bestSdh ||
                          (h == bestSdh &&
                              s.name.toLowerCase().compareTo(
                                    best.name.toLowerCase(),
                                  ) <
                                  0)))));
      if (better) {
        best = s;
        bestTier = t;
        bestForced = f;
        bestSdh = h;
      }
    }
    return best;
  }
}

/// Resolves a human-readable language label from an external subtitle's file
/// name, relative to the video it matches.
///
/// Convention: the language is encoded as a tag between the video base name
/// and the subtitle extension — `Movie.en.srt`, `Show.zh-Hans.ass`,
/// `Ep01.eng.srt`. This maps ISO 639-1 / 639-2 codes and common fansub
/// variants (`chs`/`cht`/`zh-Hans`…) to display names, and appends qualifiers
/// like "(forced)" or "(SDH)" when present in a *separate* segment.
///
/// Returns `null` when no recognized tag is found (e.g. an exact-name match
/// `Movie.srt`), so the caller can fall back to showing the raw file name.
class SubtitleLanguageResolver {
  const SubtitleLanguageResolver();

  static const _labels = <String, String>{
    'en': 'English',
    'eng': 'English',
    'zh': 'Chinese',
    'zho': 'Chinese',
    'chi': 'Chinese',
    'zh-hans': 'Chinese (Simplified)',
    'zh-cn': 'Chinese (Simplified)',
    'chs': 'Chinese (Simplified)',
    'zh-hant': 'Chinese (Traditional)',
    'zh-tw': 'Chinese (Traditional)',
    'cht': 'Chinese (Traditional)',
    'ja': 'Japanese',
    'jpn': 'Japanese',
    'ko': 'Korean',
    'kor': 'Korean',
    'fr': 'French',
    'fra': 'French',
    'fre': 'French',
    'de': 'German',
    'deu': 'German',
    'ger': 'German',
    'es': 'Spanish',
    'spa': 'Spanish',
    'ru': 'Russian',
    'rus': 'Russian',
    'pt': 'Portuguese',
    'por': 'Portuguese',
    'pt-br': 'Portuguese (Brazil)',
    'it': 'Italian',
    'ita': 'Italian',
    'ar': 'Arabic',
    'ara': 'Arabic',
    'hi': 'Hindi',
    'hin': 'Hindi',
    'th': 'Thai',
    'tha': 'Thai',
    'vi': 'Vietnamese',
    'vie': 'Vietnamese',
    'pl': 'Polish',
    'pol': 'Polish',
    'nl': 'Dutch',
    'nld': 'Dutch',
    'dut': 'Dutch',
    'sv': 'Swedish',
    'swe': 'Swedish',
    'tr': 'Turkish',
    'tur': 'Turkish',
    'id': 'Indonesian',
    'ind': 'Indonesian',
    'uk': 'Ukrainian',
    'ukr': 'Ukrainian',
    'cs': 'Czech',
    'ces': 'Czech',
    'cze': 'Czech',
    'da': 'Danish',
    'dan': 'Danish',
    'fi': 'Finnish',
    'fin': 'Finnish',
    'hu': 'Hungarian',
    'hun': 'Hungarian',
    'no': 'Norwegian',
    'nor': 'Norwegian',
    'ro': 'Romanian',
    'ron': 'Romanian',
    'rum': 'Romanian',
    'el': 'Greek',
    'ell': 'Greek',
    'gre': 'Greek',
    'he': 'Hebrew',
    'heb': 'Hebrew',
    'bn': 'Bengali',
    'ben': 'Bengali',
    'fa': 'Persian',
    'fas': 'Persian',
    'per': 'Persian',
    'ms': 'Malay',
    'msa': 'Malay',
    'may': 'Malay',
    'ta': 'Tamil',
    'tam': 'Tamil',
    'te': 'Telugu',
    'tel': 'Telugu',
  };

  /// Returns a display label like "English" / "Chinese (Simplified)" /
  /// "English (forced)", or `null` when [subtitle] carries no recognized
  /// language tag relative to [video].
  String? labelOf(DriveItem video, DriveItem subtitle) {
    final tag = tagOf(video, subtitle);
    if (tag == null) return null;
    final label = _labels[tag];
    if (label == null) return null;
    final segments = _tagSegments(video, subtitle);

    // Qualifiers live in their own segments, so 'hi' alone stays Hindi while
    // 'en.hi' becomes "English (SDH)".
    for (final seg in segments) {
      final key = seg.toLowerCase();
      if (key == 'forced') return '$label (forced)';
      if (key == 'sdh') return '$label (SDH)';
    }
    if (label.toLowerCase() != 'hindi') {
      for (final seg in segments) {
        if (seg.toLowerCase() == 'hi') return '$label (SDH)';
      }
    }
    return label;
  }

  /// The normalized language tag of [subtitle] relative to [video]
  /// (e.g. `zh-hans` for `Movie.zh-Hans.ass`), or `null` when no recognized
  /// tag is present (e.g. an exact-name match `Movie.srt`).
  String? tagOf(DriveItem video, DriveItem subtitle) {
    if (subtitle.isFolder) return null;
    final videoBase = video.baseName;
    final subBase = subtitle.baseName;
    if (subBase == videoBase) return null;
    final prefix = '$videoBase.';
    if (!subBase.startsWith(prefix)) return null;
    for (final seg in _tagSegments(video, subtitle)) {
      final key = seg.toLowerCase();
      if (_labels.containsKey(key)) return key;
      // Try the primary subtag for hyphenated codes (zh-Hans → zh).
      final dash = key.indexOf('-');
      if (dash > 0) {
        final primary = key.substring(0, dash);
        if (_labels.containsKey(primary)) return primary;
      }
    }
    return null;
  }

  /// The dot-separated segments between the video base name and the subtitle
  /// extension, lower-cased (e.g. `Movie.en.forced.srt` → `[en, forced]`).
  List<String> _tagSegments(DriveItem video, DriveItem subtitle) {
    final prefix = '${video.baseName}.';
    final suffix = subtitle.baseName.substring(prefix.length);
    return suffix.split('.');
  }

  /// Maps a raw language code (e.g. "eng", "zh-Hans", "jpn") to a display
  /// name, reusing the same table as [labelOf]. Returns `null` for unknown
  /// codes. Used for audio track language display.
  String? nameOfCode(String? code) {
    if (code == null || code.isEmpty) return null;
    final key = code.toLowerCase();
    if (_labels.containsKey(key)) return _labels[key];
    final dash = key.indexOf('-');
    if (dash > 0) {
      final primary = key.substring(0, dash);
      if (_labels.containsKey(primary)) return _labels[primary];
    }
    return null;
  }
}
