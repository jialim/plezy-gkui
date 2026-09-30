import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/mpv/models.dart';
import 'package:plezy/services/track_selection_service.dart';

SubtitleTrack subtitle({String? language, String? title}) => SubtitleTrack(
  id: '${language ?? 'none'}-${title ?? 'untitled'}',
  language: language,
  title: title,
);

void main() {
  test('ranks Simplified Chinese before Traditional, generic Chinese, and English', () {
    final ranked = [
      subtitle(language: 'en'),
      subtitle(language: 'zh'),
      subtitle(language: 'zh-Hant'),
      subtitle(language: 'zh-CN'),
    ]..sort((a, b) => familyProjectorSubtitleRank(b).compareTo(familyProjectorSubtitleRank(a)));

    expect(ranked.map((track) => track.language), ['zh-CN', 'zh-Hant', 'zh', 'en']);
  });

  test('uses CHS and CHT title hints only when language metadata is absent', () {
    expect(familyProjectorSubtitleRank(subtitle(title: 'Movie CHS')), greaterThan(familyProjectorSubtitleRank(subtitle(title: 'Movie CHT'))));
    expect(familyProjectorSubtitleRank(subtitle(language: 'en', title: 'Movie CHS')), 100);
  });

  test('recognizes ISO 639 Chinese aliases', () {
    expect(familyProjectorSubtitleRank(subtitle(language: 'zho')), 200);
    expect(familyProjectorSubtitleRank(subtitle(language: 'chi')), 200);
  });
}
