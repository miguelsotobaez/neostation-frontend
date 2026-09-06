import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/utils/count_label.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The count labels on system cards, the collections browser header and its
/// footer.
///
/// Two properties matter and neither is visible in English alone: the form has
/// to change at exactly one, and the number has to be interpolated into the
/// translated template rather than glued to the front of a translated noun —
/// several shipped languages do not put it first.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await FlutterLocalization.instance.ensureInitialized();
    FlutterLocalization.instance.init(
      mapLocales: [
        const MapLocale('en', AppLocale.en),
        const MapLocale('ru', AppLocale.ru),
        const MapLocale('ko', AppLocale.ko),
      ],
      initLanguageCode: 'en',
    );
  });

  /// Renders [build] and returns the single string it produced.
  Future<String> label(
    WidgetTester tester,
    String languageCode,
    String Function(BuildContext) build,
  ) async {
    FlutterLocalization.instance.translate(languageCode);
    late String result;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates:
            FlutterLocalization.instance.localizationsDelegates,
        supportedLocales: FlutterLocalization.instance.supportedLocales,
        locale: Locale(languageCode),
        home: Builder(
          builder: (context) {
            result = build(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();
    return result;
  }

  testWidgets('the form changes at exactly one', (tester) async {
    expect(await label(tester, 'en', (c) => gamesCountLabel(c, 0)), '0 Games');
    expect(await label(tester, 'en', (c) => gamesCountLabel(c, 1)), '1 Game');
    expect(await label(tester, 'en', (c) => gamesCountLabel(c, 2)), '2 Games');
  });

  testWidgets('every noun has both forms', (tester) async {
    expect(await label(tester, 'en', (c) => appsCountLabel(c, 1)), '1 App');
    expect(await label(tester, 'en', (c) => appsCountLabel(c, 3)), '3 Apps');
    expect(await label(tester, 'en', (c) => tracksCountLabel(c, 1)), '1 Track');
    expect(
      await label(tester, 'en', (c) => tracksCountLabel(c, 3)),
      '3 Tracks',
    );
    expect(
      await label(tester, 'en', (c) => collectionsCountLabel(c, 1)),
      '1 Collection',
    );
    expect(
      await label(tester, 'en', (c) => collectionsCountLabel(c, 3)),
      '3 Collections',
    );
  });

  testWidgets('the number goes where the translation puts it, not first', (
    tester,
  ) async {
    // ru trails the number behind a label; ko puts it mid-phrase. Both would
    // come out backwards if a caller concatenated a count onto a bare noun,
    // which is why no bare-noun helper exists.
    expect(
      await label(tester, 'ru', (c) => gamesCountLabel(c, 7)),
      startsWith('Игр'),
    );
    expect(
      await label(tester, 'ru', (c) => gamesCountLabel(c, 7)),
      endsWith('7'),
    );
    expect(
      await label(tester, 'ko', (c) => collectionsCountLabel(c, 7)),
      '컬렉션 7개',
    );
  });

  testWidgets('a language that marks number uses its singular at one', (
    tester,
  ) async {
    expect(
      await label(tester, 'ru', (c) => collectionsCountLabel(c, 1)),
      'Коллекция: 1',
    );
  });
}
