import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/l10n/app_locale.dart';

void main() {
  test('Korean localization covers every English localization key', () {
    expect(AppLocale.ko.keys, containsAll(AppLocale.en.keys));
    expect(AppLocale.ko.length, AppLocale.en.length);
  });

  test('Korean is exposed in the language picker', () {
    expect(AppLocale.supportedLanguages['ko'], '한국어');
    expect(AppLocale.ko[AppLocale.settings], '설정');
  });
}
