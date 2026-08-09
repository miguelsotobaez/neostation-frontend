import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/l10n/app_locale.dart';

/// The startup screens run before FlutterLocalization is initialized and read
/// the raw locale maps directly, so a missing key there is a crash on the very
/// first frame rather than a fallback string.
void main() {
  const startupKeys = <String>[
    AppLocale.startupLoading,
    AppLocale.startupStorageUnavailable,
    AppLocale.startupStorageRetry,
    AppLocale.startupStorageUseDefault,
  ];

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
    test('${entry.key} defines every startup string', () {
      for (final key in startupKeys) {
        final value = entry.value[key];
        expect(
          value,
          isA<String>().having((s) => s.isNotEmpty, 'isNotEmpty', isTrue),
          reason: '$key missing from app_locale_${entry.key}.dart',
        );
      }
    });
  }
}
