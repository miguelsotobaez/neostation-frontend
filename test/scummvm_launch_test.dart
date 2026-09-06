import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/models/game_model.dart';
import 'package:neostation/repositories/game_repository.dart';
import 'package:neostation/services/launcher_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late File descriptor;
  final launcher = LauncherService.instance;

  GameModel game(String location) => GameModel(
    romname: 'Day Of The Tentacle.scummvm',
    realname: 'Day of the Tentacle',
    name: 'Day of the Tentacle',
    year: '',
    developer: '',
    publisher: '',
    genre: '',
    players: '1',
    rating: 0,
    romPath: location,
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('scummvm-launch-');
    descriptor = File('${directory.path}/Day Of The Tentacle.scummvm');
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'launches the descriptor target rather than its display filename',
    () async {
      await descriptor.writeAsString('\uFEFFtentacle\r\n');
      final command = <String, dynamic>{'data': '{tags.scummvm_id}'};
      await launcher.resolveAndroidLaunchFiles(command, game(descriptor.path));
      expect(command['data'], 'tentacle');
    },
  );

  test('reads file URIs and replaces targets in extras', () async {
    await descriptor.writeAsString('tentacle-win');
    final command = <String, dynamic>{
      'extras': [
        {'key': 'target', 'value': '{tags.scummvm_id}'},
        {'key': 'enabled', 'value': true},
      ],
    };
    await launcher.resolveAndroidLaunchFiles(
      command,
      game(descriptor.uri.toString()),
    );
    expect(command['extras'][0]['value'], 'tentacle-win');
    expect(command['extras'][1]['value'], isTrue);
  });

  test(
    'does not read ROMs for emulators without the target placeholder',
    () async {
      final command = <String, dynamic>{
        'data': 'neostation-realpath:missing.zip',
      };
      await launcher.resolveAndroidLaunchFiles(command, game('missing.zip'));
      expect(command['data'], 'neostation-realpath:missing.zip');
    },
  );

  for (final invalid in [
    '',
    '  ',
    'tentacle\nmonkey',
    '--help',
    'scumm:tentacle',
  ]) {
    test('rejects invalid target ${invalid.replaceAll('\n', r'\n')}', () async {
      await descriptor.writeAsString(invalid);
      final command = <String, dynamic>{'data': '{tags.scummvm_id}'};
      await expectLater(
        launcher.resolveAndroidLaunchFiles(command, game(descriptor.path)),
        throwsFormatException,
      );
      expect(command['data'], '{tags.scummvm_id}');
    });
  }

  test('reports unreadable descriptors before launching', () async {
    await expectLater(
      launcher.resolveAndroidLaunchFiles({
        'data': '{tags.scummvm_id}',
      }, game(descriptor.path)),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('bounds descriptor reads', () async {
    await descriptor.writeAsString('a' * 4097);
    await expectLater(
      GameRepository.readLaunchDescriptor(descriptor.path),
      throwsFormatException,
    );
  });
}
