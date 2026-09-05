import 'dart:io';

import 'package:oracular/utils/process_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('ProcessRunner tool probes', () {
    late Directory tempDir;
    late String hangScriptPath;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('oracular_proc_runner_');
      // A cross-platform command that hangs far longer than the probe
      // timeout: a Dart script sleeping for 60 seconds.
      hangScriptPath = p.join(tempDir.path, 'hang.dart');
      await File(hangScriptPath).writeAsString(
        'void main() async {\n'
        '  await Future<void>.delayed(const Duration(seconds: 60));\n'
        '}\n',
      );
    });

    tearDownAll(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
        'getCommandVersion returns null instead of hanging when the '
        'probed tool never exits', () async {
      final ProcessRunner runner = ProcessRunner();
      final Stopwatch watch = Stopwatch()..start();

      final String? version = await runner.getCommandVersion(
        Platform.resolvedExecutable,
        versionArgs: <String>[hangScriptPath],
        timeout: const Duration(seconds: 3),
      );
      watch.stop();

      expect(version, isNull);
      expect(
        watch.elapsed,
        lessThan(const Duration(seconds: 20)),
        reason: 'a hung tool must not block the probe indefinitely',
      );
    });

    test('getCommandVersion still returns output from a healthy tool',
        () async {
      final ProcessRunner runner = ProcessRunner();
      final String? version = await runner.getCommandVersion(
        Platform.resolvedExecutable,
        versionArgs: <String>['--version'],
      );
      expect(version, isNotNull);
      expect(version, isNotEmpty);
    });

    test('commandExists is true for dart and false for a missing tool',
        () async {
      final ProcessRunner runner = ProcessRunner();
      expect(await runner.commandExists('dart'), isTrue);
      expect(
        await runner.commandExists('definitely_not_a_real_tool_xyz'),
        isFalse,
      );
    });
  });
}
