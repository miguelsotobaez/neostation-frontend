import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/models/game_model.dart';
import 'package:neostation/services/launcher_service.dart';

void main() {
  group('LauncherService.splitArgs', () {
    test('splits simple space-separated arguments', () {
      final args = LauncherService.splitArgs(
        '-L /cores/snes9x_libretro.so /roms/mario.sfc',
      );
      expect(
        args,
        equals(['-L', '/cores/snes9x_libretro.so', '/roms/mario.sfc']),
      );
    });

    test('preserves whitespace within double-quoted arguments', () {
      final args = LauncherService.splitArgs(
        '-L "/cores/core path/snes.so" "/games/Super Mario World.sfc"',
      );
      expect(
        args,
        equals([
          '-L',
          '/cores/core path/snes.so',
          '/games/Super Mario World.sfc',
        ]),
      );
    });

    test('handles mixed flags and empty strings gracefully', () {
      final args = LauncherService.splitArgs('--fullscreen -v');
      expect(args, equals(['--fullscreen', '-v']));
    });
  });

  group('LauncherService placeholder resolution', () {
    const sampleGame = GameModel(
      romname: 'Chrono Trigger.sfc',
      realname: 'Chrono Trigger',
      name: 'Chrono Trigger',
      year: '1995',
      developer: 'Square',
      publisher: 'Square',
      genre: 'RPG',
      players: '1',
      rating: 5.0,
      romPath: '/roms/snes/Chrono Trigger.sfc',
      titleId: 'PCSB00001',
    );

    test('resolvePlaceholdersDesktop quotes paths with spaces', () {
      final template = '-L core.so {file.path}';
      final resolved = LauncherService.instance.resolvePlaceholdersDesktop(
        template,
        sampleGame,
      );
      expect(resolved, equals('-L core.so "/roms/snes/Chrono Trigger.sfc"'));
    });

    test(
      'resolvePlaceholdersDesktop does not double-quote already quoted template paths',
      () {
        final template = '-L core.so "{file.path}"';
        final resolved = LauncherService.instance.resolvePlaceholdersDesktop(
          template,
          sampleGame,
        );
        expect(resolved, equals('-L core.so "/roms/snes/Chrono Trigger.sfc"'));
      },
    );

    test('resolvePlaceholdersDesktop substitutes tag and URI placeholders', () {
      final template = '--title-id={tags.steamappid} --uri={file.uri}';
      final resolved = LauncherService.instance.resolvePlaceholdersDesktop(
        template,
        sampleGame,
      );
      expect(resolved, contains('--title-id=PCSB00001'));
      expect(
        resolved,
        contains('--uri=file:///roms/snes/Chrono%20Trigger.sfc'),
      );
    });

    test(
      'resolvePlaceholdersAndroid resolves marker prefixes for SAF and path',
      () {
        final template =
            '-a android.intent.action.VIEW -d {file.path} -e uri {file.uri}';
        final resolved = LauncherService.instance.resolvePlaceholdersAndroid(
          template,
          sampleGame,
        );
        expect(
          resolved,
          contains('-d neostation-realpath:/roms/snes/Chrono Trigger.sfc'),
        );
        expect(
          resolved,
          contains('-e uri file:///roms/snes/Chrono%20Trigger.sfc'),
        );
      },
    );
  });
}
