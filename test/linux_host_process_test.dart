import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/services/linux_host_process.dart';

void main() {
  tearDown(LinuxHostProcess.reset);

  group('unsandboxed', () {
    setUp(() => LinuxHostProcess.sandboxOverride = false);

    test('passes the command through untouched', () {
      final (exe, args) = LinuxHostProcess.command('/usr/bin/retroarch', [
        '-f',
        '-L',
        '/usr/lib/libretro/snes9x_libretro.so',
        '/roms/snes/game.sfc',
      ]);

      expect(exe, '/usr/bin/retroarch');
      expect(args, [
        '-f',
        '-L',
        '/usr/lib/libretro/snes9x_libretro.so',
        '/roms/snes/game.sfc',
      ]);
    });

    test('passes an empty argument list through', () {
      final (exe, args) = LinuxHostProcess.command('/usr/bin/dolphin-emu', []);

      expect(exe, '/usr/bin/dolphin-emu');
      expect(args, isEmpty);
    });
  });

  group('sandboxed', () {
    setUp(() => LinuxHostProcess.sandboxOverride = true);

    test('routes the command through flatpak-spawn --host', () {
      final (exe, args) = LinuxHostProcess.command('/usr/bin/retroarch', [
        '-f',
        '/roms/snes/game.sfc',
      ]);

      expect(exe, 'flatpak-spawn');
      expect(args, [
        '--host',
        '/usr/bin/retroarch',
        '-f',
        '/roms/snes/game.sfc',
      ]);
    });

    test('keeps the executable as its own argument', () {
      // The path comes from discovery or from a file the user picked, so it can
      // hold spaces and shell metacharacters. It must reach flatpak-spawn as
      // one argv entry rather than as part of a command string.
      final (_, args) = LinuxHostProcess.command(
        '/home/deck/Emulation/tools/launchers/retro arch;rm -rf.sh',
        ['/roms/game.zip'],
      );

      expect(
        args[1],
        '/home/deck/Emulation/tools/launchers/retro arch;rm -rf.sh',
      );
      expect(args, hasLength(3));
    });

    test('preserves argument order and duplicates', () {
      final (_, args) = LinuxHostProcess.command('emu', [
        '-L',
        'core.so',
        '-L',
        'other.so',
      ]);

      expect(args, ['--host', 'emu', '-L', 'core.so', '-L', 'other.so']);
    });
  });
}
