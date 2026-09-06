import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/config_model.dart';
import 'package:neostation/providers/sqlite_config_provider.dart';
import 'package:neostation/widgets/header_sort_dropdown.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The systems view picker is shared by the systems screen and the collections
/// browser. The browser's cards preview the games a collection holds, so it
/// also offers the box-art/fanart switch that decides which artwork the preview
/// samples; the systems screen, whose cards come from theme artwork, must not
/// grow that row.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await FlutterLocalization.instance.ensureInitialized();
    FlutterLocalization.instance.init(
      mapLocales: [MapLocale('en', AppLocale.en)],
      initLanguageCode: 'en',
    );
  });

  Widget host({required bool includeCardStyle}) => ScreenUtilInit(
    designSize: const Size(1920, 1080),
    builder: (context, _) => ChangeNotifierProvider<SqliteConfigProvider>(
      create: (_) => _GridConfig(),
      child: MaterialApp(
        localizationsDelegates:
            FlutterLocalization.instance.localizationsDelegates,
        supportedLocales: FlutterLocalization.instance.supportedLocales,
        home: Scaffold(
          body: SortDropdownOverlay(
            width: 180,
            includeSorting: false,
            includeCardStyle: includeCardStyle,
          ),
        ),
      ),
    ),
  );

  testWidgets('the collections browser gets a box-art/fanart row', (
    tester,
  ) async {
    await tester.pumpWidget(host(includeCardStyle: true));
    await tester.pump();

    expect(
      find.text(
        AppLocale.cardStyleGroup.getString(
          tester.element(find.byType(Scaffold)),
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        AppLocale.fanartCard.getString(tester.element(find.byType(Scaffold))),
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        AppLocale.boxCard.getString(tester.element(find.byType(Scaffold))),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the systems screen does not', (tester) async {
    await tester.pumpWidget(host(includeCardStyle: false));
    await tester.pump();

    expect(
      find.text(
        AppLocale.fanartCard.getString(tester.element(find.byType(Scaffold))),
      ),
      findsNothing,
    );
  });
}

/// Grid mode, so the card-size row is present too and the card-style row has to
/// coexist with it rather than replacing it.
class _GridConfig extends SqliteConfigProvider {
  @override
  ConfigModel get config => super.config.copyWith(
    systemViewMode: 'grid',
    gameCarouselCardStyle: 'box',
  );
}
