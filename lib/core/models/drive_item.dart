/// A OneDrive drive item: either a folder or a file.
class DriveItem {
  DriveItem({
    required this.id,
    required this.name,
    required this.isFolder,
    this.size,
    this.parentId,
    this.lastModified,
    this.thumbnailUrl,
  });

  final String id;
  final String name;
  final bool isFolder;
  final int? size;
  final String? parentId;
  final DateTime? lastModified;
  final String? thumbnailUrl;

  /// Video file extensions we treat as playable.
  static const _videoExtensions = <String>[
    '.mp4', '.mkv', '.mov', '.avi', '.webm', '.flv', '.ts', '.m4v',
    '.wmv', '.mpg', '.mpeg', '.m2ts', '.rmvb', '.rm', '.3gp', '.vob',
  ];

  bool get isVideo {
    if (isFolder) return false;
    final lower = name.toLowerCase();
    return _videoExtensions.any(lower.endsWith);
  }

  String get extension {
    final dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(dot).toLowerCase() : '';
  }

  /// External subtitle file extensions we treat as subtitle candidates.
  static const _subtitleExtensions = <String>[
    '.srt', '.vtt', '.webvtt', '.ass', '.ssa', '.sub', '.smi', '.sbv',
  ];

  /// `true` for an external subtitle file (matched by extension).
  bool get isSubtitle {
    if (isFolder) return false;
    final lower = name.toLowerCase();
    return _subtitleExtensions.any(lower.endsWith);
  }

  /// File name without its final extension, lower-cased. Used to match an
  /// external subtitle to its video (e.g. `Movie.en.srt` → `movie`).
  String get baseName {
    final lower = name.toLowerCase();
    final dot = lower.lastIndexOf('.');
    return dot >= 0 ? lower.substring(0, dot) : lower;
  }

  /// Builds a drive item from a Microsoft Graph driveItem JSON object.
  factory DriveItem.fromJson(Map<String, dynamic> json) {
    final isFolder = json['folder'] != null;
    final parent = json['parentReference'] as Map<String, dynamic>?;
    final thumbnails = json['thumbnails'] as List<dynamic>?;
    String? thumbnailUrl;
    if (thumbnails != null && thumbnails.isNotEmpty) {
      final first = thumbnails.first as Map<String, dynamic>;
      final medium = first['medium'] as Map<String, dynamic>?;
      final small = first['small'] as Map<String, dynamic>?;
      thumbnailUrl =
          (medium?['url'] as String?) ?? (small?['url'] as String?);
    }
    return DriveItem(
      id: json['id'] as String,
      name: json['name'] as String,
      isFolder: isFolder,
      size: (json['size'] as num?)?.toInt(),
      parentId: parent?['id'] as String?,
      lastModified: json['lastModifiedDateTime'] != null
          ? DateTime.tryParse(json['lastModifiedDateTime'] as String)
          : null,
      thumbnailUrl: thumbnailUrl,
    );
  }
}
