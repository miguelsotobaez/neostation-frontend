import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/l10n/app_locale.dart';

/// Every locale map must define exactly the keys English defines. A key that is
/// missing from a translation falls back to the raw key name at runtime, which
/// nobody sees until they switch language, so it is caught here instead.
void main() {
  const locales = <String, Map<String, dynamic>>{
    'en': appLocaleEn,
    'es': appLocaleEs,
    'pt': appLocalePt,
    'ru': appLocaleRu,
    'zh': appLocaleZh,
    'zh_Hant': appLocaleZhHant,
    'fr': appLocaleFr,
    'de': appLocaleDe,
    'it': appLocaleIt,
    'id': appLocaleId,
    'ja': appLocaleJa,
    'ko': appLocaleKo,
  };

  for (final entry in locales.entries) {
    final code = entry.key;
    final map = entry.value;
    final file = 'app_locale_$code.dart';

    test('$code defines every English key', () {
      final missing =
          appLocaleEn.keys.where((k) => !map.containsKey(k)).toList()..sort();
      expect(
        missing,
        isEmpty,
        reason: '${missing.length} key(s) missing from $file',
      );
    });

    test('$code defines no key English does not', () {
      final extra = map.keys.where((k) => !appLocaleEn.containsKey(k)).toList()
        ..sort();
      expect(
        extra,
        isEmpty,
        reason: '${extra.length} stale key(s) in $file — removed from English?',
      );
    });
  }

  test('every language in the picker has a locale map', () {
    expect(
      AppLocale.supportedLanguages.keys.toSet(),
      locales.keys.toSet(),
      reason: 'supportedLanguages and the locale maps have drifted apart',
    );
  });

  test('Korean is exposed in the language picker', () {
    expect(AppLocale.supportedLanguages['ko'], '한국어');
    expect(AppLocale.ko[AppLocale.settings], '설정');
  });
}
