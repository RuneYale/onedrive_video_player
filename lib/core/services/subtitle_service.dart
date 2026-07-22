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
        .where((s) =>
            s.isSubtitle &&
            (s.baseName == videoBase || s.baseName.startsWith(prefix)))
        .toList();
    result.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
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
    'en': 'English', 'eng': 'English',
    'zh': 'Chinese', 'zho': 'Chinese', 'chi': 'Chinese',
    'zh-hans': 'Chinese (Simplified)', 'zh-cn': 'Chinese (Simplified)',
    'chs': 'Chinese (Simplified)',
    'zh-hant': 'Chinese (Traditional)', 'zh-tw': 'Chinese (Traditional)',
    'cht': 'Chinese (Traditional)',
    'ja': 'Japanese', 'jpn': 'Japanese',
    'ko': 'Korean', 'kor': 'Korean',
    'fr': 'French', 'fra': 'French', 'fre': 'French',
    'de': 'German', 'deu': 'German', 'ger': 'German',
    'es': 'Spanish', 'spa': 'Spanish',
    'ru': 'Russian', 'rus': 'Russian',
    'pt': 'Portuguese', 'por': 'Portuguese',
    'pt-br': 'Portuguese (Brazil)',
    'it': 'Italian', 'ita': 'Italian',
    'ar': 'Arabic', 'ara': 'Arabic',
    'hi': 'Hindi', 'hin': 'Hindi',
    'th': 'Thai', 'tha': 'Thai',
    'vi': 'Vietnamese', 'vie': 'Vietnamese',
    'pl': 'Polish', 'pol': 'Polish',
    'nl': 'Dutch', 'nld': 'Dutch', 'dut': 'Dutch',
    'sv': 'Swedish', 'swe': 'Swedish',
    'tr': 'Turkish', 'tur': 'Turkish',
    'id': 'Indonesian', 'ind': 'Indonesian',
    'uk': 'Ukrainian', 'ukr': 'Ukrainian',
    'cs': 'Czech', 'ces': 'Czech', 'cze': 'Czech',
    'da': 'Danish', 'dan': 'Danish',
    'fi': 'Finnish', 'fin': 'Finnish',
    'hu': 'Hungarian', 'hun': 'Hungarian',
    'no': 'Norwegian', 'nor': 'Norwegian',
    'ro': 'Romanian', 'ron': 'Romanian', 'rum': 'Romanian',
    'el': 'Greek', 'ell': 'Greek', 'gre': 'Greek',
    'he': 'Hebrew', 'heb': 'Hebrew',
    'bn': 'Bengali', 'ben': 'Bengali',
    'fa': 'Persian', 'fas': 'Persian', 'per': 'Persian',
    'ms': 'Malay', 'msa': 'Malay', 'may': 'Malay',
    'ta': 'Tamil', 'tam': 'Tamil',
    'te': 'Telugu', 'tel': 'Telugu',
  };

  /// Returns a display label like "English" / "Chinese (Simplified)" /
  /// "English (forced)", or `null` when [subtitle] carries no recognized
  /// language tag relative to [video].
  String? labelOf(DriveItem video, DriveItem subtitle) {
    if (subtitle.isFolder) return null;
    final videoBase = video.baseName;
    final subBase = subtitle.baseName;
    if (subBase == videoBase) return null;
    final prefix = '$videoBase.';
    if (!subBase.startsWith(prefix)) return null;
    final suffix = subBase.substring(prefix.length);
    final segments = suffix.split('.');

    String? label;
    for (final seg in segments) {
      final key = seg.toLowerCase();
      if (_labels.containsKey(key)) {
        label = _labels[key]!;
        break;
      }
      // Try the primary subtag for hyphenated codes (zh-Hans → zh).
      final dash = key.indexOf('-');
      if (dash > 0) {
        final primary = key.substring(0, dash);
        if (_labels.containsKey(primary)) {
          label = _labels[primary]!;
          break;
        }
      }
    }
    if (label == null) return null;

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
