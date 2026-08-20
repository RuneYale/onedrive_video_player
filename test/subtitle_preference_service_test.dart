import 'package:flutter_test/flutter_test.dart';
import 'package:onedrive_video_player/core/services/subtitle_preference_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SubtitlePreferenceService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = const SubtitlePreferenceService();
  });

  group('SubtitlePreferenceService', () {
    test('returns null when nothing was saved', () async {
      expect(await service.get('video-1'), isNull);
    });

    test('round-trips a choice id', () async {
      await service.save('video-1', 'external:item-9');
      expect(await service.get('video-1'), 'external:item-9');
    });

    test('keeps multiple videos independent', () async {
      await service.save('video-1', 'off');
      await service.save('video-2', 'auto');
      expect(await service.get('video-1'), 'off');
      expect(await service.get('video-2'), 'auto');
      expect(await service.get('video-3'), isNull);
    });

    test('later saves overwrite earlier ones', () async {
      await service.save('video-1', 'auto');
      await service.save('video-1', 'embedded:1');
      expect(await service.get('video-1'), 'embedded:1');
    });

    test('clear removes only the requested video', () async {
      await service.save('video-1', 'off');
      await service.save('video-2', 'auto');
      await service.clear('video-1');
      expect(await service.get('video-1'), isNull);
      expect(await service.get('video-2'), 'auto');
    });

    test('clearAll empties the map', () async {
      await service.save('video-1', 'off');
      await service.clearAll();
      expect(await service.get('video-1'), isNull);
    });

    test('ignores a corrupt payload and keeps working', () async {
      SharedPreferences.setMockInitialValues({
        'odvp_subtitle_preferences': 'not json{{{',
      });
      expect(await service.get('video-1'), isNull);
      await service.save('video-1', 'off');
      expect(await service.get('video-1'), 'off');
    });
  });
}
