// Install-offer state machine test for the standalone `setup.dart`
// (T3.2b). Validates the six-case decision table from plan §4.4:
//
//   1. `--no-install-oracular` → skipped silently, exit 0.
//   2. `--install-oracular` → runs `dart pub global activate oracular
//      <version>` exactly once.
//   3. `--yes` (no install flags) → same as `--install-oracular`.
//   4. neither flag + piped stdin → skip silently (CI-safe).
//   5. neither flag + simulated TTY + user says "n" → prompt rendered,
//      activation NOT called.
//   6. activation fails (stubbed non-zero exit) → setup exits 0 with
//      retry hint.
//
// The test relies on three test-only env-vars baked into the skeleton
// (`scripts/setup_template_template.dart:982-1006`):
//   - ORACULAR_INSTALL_DETECT_OVERRIDE  — bypasses `which oracular`
//   - ORACULAR_INSTALL_DART_CMD         — overrides `dart` for activate
//   - ORACULAR_INSTALL_SIMULATE_TTY     — fakes stdin.hasTerminal=true
//
// To avoid spawning real `dart pub global activate`, a tiny `fake_dart`
// shell script records its argv into a log file and exits with a
// configurable code. The test asserts on the log file + setup.dart's
// stdout.
//
// The harness reuses `arcane_app` (simplest template, no jaspr/render
// complications). Each test scaffolds a fresh extracted ZIP layout in
// a temp directory and runs setup.dart from inside it.

@TestOn('vm')
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:oracular/version.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

late final Directory _repoRoot;
late final String _packagerPath;
late final String _generatorPath;

/// One-shot per-suite assets. Reused across all six tests.
late final String _generatedSetupPath;
late final String _arcaneAppZipPath;
late final String _fakeDartPath;

/// The oracular release version this run packages. Cross-checked
/// against `oracular/pubspec.yaml:3` by the generator.
const String _version = oracularVersion;
final String _buildId = '$_version+install-offer-test';

void main() {
  setUpAll(() async {
    _repoRoot = Directory.current.path.endsWith('oracular')
        ? Directory.current.parent
        : Directory.current;
    _packagerPath = p.join(_repoRoot.path, 'scripts', 'package_template.dart');
    _generatorPath = p.join(
      _repoRoot.path,
      'scripts',
      'generate_setup_script.dart',
    );

    // 1. Generate setup.dart once.
    final Directory genDir = await Directory.systemTemp.createTemp(
      'oracular_offer_gen_',
    );
    _generatedSetupPath = p.join(genDir.path, 'setup.dart');
    final ProcessResult gen = await Process.run('dart', <String>[
      'run',
      _generatorPath,
      '--version',
      _version,
      '--build-id',
      _buildId,
      '--out',
      _generatedSetupPath,
    ], workingDirectory: _repoRoot.path);
    if (gen.exitCode != 0) {
      fail('generate_setup_script.dart failed: ${gen.stderr}');
    }

    // 2. Package arcane_app once.
    final Directory zipOutDir = await Directory.systemTemp.createTemp(
      'oracular_offer_zip_',
    );
    final ProcessResult pkg = await Process.run('dart', <String>[
      'run',
      _packagerPath,
      '--template',
      'arcane_app',
      '--version',
      _version,
      '--build-id',
      _buildId,
      '--setup-script',
      _generatedSetupPath,
      '--out',
      zipOutDir.path,
    ], workingDirectory: _repoRoot.path);
    if (pkg.exitCode != 0) {
      fail('package_template.dart failed: ${pkg.stderr}');
    }
    _arcaneAppZipPath = p.join(zipOutDir.path, 'arcane_app-v$_version.zip');
    expect(File(_arcaneAppZipPath).existsSync(), isTrue);

    // 3. Build the fake `dart` script. Records its argv into the log
    //    file pointed to by FAKE_DART_LOG, exits with FAKE_DART_EXIT
    //    (default 0). Stays Unix-only — Windows runners aren't in the
    //    plan §7 scope yet.
    final Directory fakeDir = await Directory.systemTemp.createTemp(
      'oracular_offer_fake_',
    );
    if (Platform.isWindows) {
      _fakeDartPath = p.join(fakeDir.path, 'fake_dart.bat');
      await File(_fakeDartPath).writeAsString('''@echo off
echo %* >> %FAKE_DART_LOG%
if defined FAKE_DART_EXIT (exit /b %FAKE_DART_EXIT%)
exit /b 0
''');
    } else {
      _fakeDartPath = p.join(fakeDir.path, 'fake_dart.sh');
      await File(_fakeDartPath).writeAsString('''#!/usr/bin/env bash
set -u
echo "ARGV: \$*" >> "\$FAKE_DART_LOG"
exit "\${FAKE_DART_EXIT:-0}"
''');
      final ProcessResult chmod = await Process.run('chmod', <String>[
        '+x',
        _fakeDartPath,
      ]);
      if (chmod.exitCode != 0) {
        fail('chmod +x on fake_dart.sh failed: ${chmod.stderr}');
      }
    }
  });

  group('install-offer state machine', () {
    test('1. --no-install-oracular skips silently', () async {
      final _Run r = await _runScenario(installFlag: 'no', yes: true);
      expect(r.exitCode, equals(0));
      expect(
        r.activationLog,
        isEmpty,
        reason: 'No activation should have been attempted.',
      );
      expect(r.stdout, contains('Skipped oracular install'));
    });

    test('2. --install-oracular invokes activate once', () async {
      final _Run r = await _runScenario(
        installFlag: 'yes',
        yes: true,
        detectOverride: 'missing',
      );
      expect(r.exitCode, equals(0));
      expect(
        r.activationLog,
        hasLength(1),
        reason: 'Activation should be invoked exactly once.',
      );
      expect(
        r.activationLog.first,
        contains('pub global activate oracular $_version'),
      );
    });

    test('3. --yes (no install flag) activates by default', () async {
      // Per plan §4.1 last row: `--yes` + neither install flag is
      // treated as `--install-oracular`.
      final _Run r = await _runScenario(
        installFlag: null,
        yes: true,
        detectOverride: 'missing',
      );
      expect(r.exitCode, equals(0));
      expect(
        r.activationLog,
        hasLength(1),
        reason: '--yes should be treated as --install-oracular.',
      );
      expect(
        r.activationLog.first,
        contains('pub global activate oracular $_version'),
      );
    });

    test('4. piped stdin without flags skips silently', () async {
      // No install flags, no --yes, no simulated TTY → stdin is piped
      // by Process.run, so the prompt path bails out cleanly.
      final _Run r = await _runScenario(
        installFlag: null,
        yes: false,
        detectOverride: 'missing',
        // No simulateTty.
      );
      expect(r.exitCode, equals(0));
      expect(
        r.activationLog,
        isEmpty,
        reason: 'Piped stdin must not trigger activation.',
      );
      expect(r.stdout, contains('Skipped oracular install'));
      expect(
        r.stdout,
        isNot(contains('Install the oracular CLI')),
        reason: 'Prompt should NOT be rendered for piped stdin.',
      );
    });

    test('5. simulated TTY renders prompt, user says "n"', () async {
      final _Run r = await _runScenario(
        installFlag: null,
        yes: false,
        detectOverride: 'missing',
        simulateTty: true,
        stdinInput: 'n\n',
      );
      expect(r.exitCode, equals(0));
      expect(
        r.stdout,
        contains('Install the oracular CLI'),
        reason: 'Prompt should be rendered when TTY is simulated.',
      );
      expect(
        r.activationLog,
        isEmpty,
        reason: 'User answered "n"; no activation should happen.',
      );
    });

    test('6. activation failure exits 0 with retry hint', () async {
      final _Run r = await _runScenario(
        installFlag: 'yes',
        yes: true,
        detectOverride: 'missing',
        fakeDartExit: 1,
      );
      expect(
        r.exitCode,
        equals(0),
        reason:
            'Project is already scaffolded; failed activation must '
            'not propagate.',
      );
      expect(
        r.activationLog,
        hasLength(1),
        reason: 'Activation should still be attempted exactly once.',
      );
      expect(r.stdout, contains('Retry manually with'));
    });
  });
}

// ─────────────────────────────────────────────────────────────────────
// Harness.
// ─────────────────────────────────────────────────────────────────────

class _Run {
  final int exitCode;
  final String stdout;
  final String stderr;
  final List<String> activationLog;
  _Run(this.exitCode, this.stdout, this.stderr, this.activationLog);
}

/// Run one install-offer scenario.
///
/// [installFlag] : `'yes'` adds `--install-oracular`, `'no'` adds
/// `--no-install-oracular`, null adds neither.
/// [yes]        : adds `--yes` if true.
/// [detectOverride] : value for `ORACULAR_INSTALL_DETECT_OVERRIDE` env.
/// [simulateTty]   : sets `ORACULAR_INSTALL_SIMULATE_TTY=1`.
/// [stdinInput]    : optional stdin to feed setup.dart.
/// [fakeDartExit]  : exit code for the fake dart binary.
Future<_Run> _runScenario({
  required String? installFlag,
  required bool yes,
  String? detectOverride,
  bool simulateTty = false,
  String? stdinInput,
  int fakeDartExit = 0,
}) async {
  // Fresh extract + output dir per scenario so state never leaks.
  final Directory extracted = await Directory.systemTemp.createTemp(
    'oracular_offer_extract_',
  );
  await _extractZip(_arcaneAppZipPath, extracted);

  final Directory outDir = await Directory.systemTemp.createTemp(
    'oracular_offer_out_',
  );
  final File activationLog = File(p.join(extracted.path, '.fake_dart.log'));

  final List<String> setupArgs = <String>[
    'run',
    p.join(extracted.path, 'setup.dart'),
    '--name',
    'smoke_app',
    '--org',
    'com.example',
    '--output-dir',
    outDir.path,
    '--no-pub-get',
    if (yes) '--yes',
    if (installFlag == 'yes') '--install-oracular',
    if (installFlag == 'no') '--no-install-oracular',
  ];

  final Map<String, String> env = <String, String>{
    'PATH': Platform.environment['PATH'] ?? '',
    'HOME': Platform.environment['HOME'] ?? '',
    'NO_COLOR': '1',
    'ORACULAR_INSTALL_DART_CMD': _fakeDartPath,
    'FAKE_DART_LOG': activationLog.path,
    'FAKE_DART_EXIT': '$fakeDartExit',
    'ORACULAR_INSTALL_DETECT_OVERRIDE': ?detectOverride,
    if (simulateTty) 'ORACULAR_INSTALL_SIMULATE_TTY': '1',
  };

  final Process proc = await Process.start(
    'dart',
    setupArgs,
    workingDirectory: extracted.path,
    environment: env,
  );

  // Feed stdin if requested, then close.
  if (stdinInput != null) {
    proc.stdin.write(stdinInput);
  }
  await proc.stdin.close();

  final List<String> stdoutLines = <String>[];
  final List<String> stderrLines = <String>[];
  await Future.wait(<Future<void>>[
    proc.stdout
        .transform<String>(SystemEncoding().decoder)
        .forEach(stdoutLines.add),
    proc.stderr
        .transform<String>(SystemEncoding().decoder)
        .forEach(stderrLines.add),
  ]);
  final int exitCode = await proc.exitCode;

  final List<String> log = activationLog.existsSync()
      ? activationLog
            .readAsLinesSync()
            .where((String l) => l.trim().isNotEmpty)
            .toList()
      : <String>[];

  // Best-effort cleanup; ignore errors during teardown.
  try {
    await extracted.delete(recursive: true);
  } catch (_) {}
  try {
    await outDir.delete(recursive: true);
  } catch (_) {}

  return _Run(exitCode, stdoutLines.join(), stderrLines.join(), log);
}

Future<void> _extractZip(String zipPath, Directory target) async {
  final InputFileStream input = InputFileStream(zipPath);
  try {
    final Archive archive = ZipDecoder().decodeStream(input);
    for (final ArchiveFile f in archive) {
      final String destPath = p.join(target.path, f.name);
      if (f.isFile) {
        final File outFile = File(destPath);
        await outFile.parent.create(recursive: true);
        final OutputFileStream out = OutputFileStream(destPath);
        try {
          f.writeContent(out);
        } finally {
          await out.close();
        }
      } else {
        await Directory(destPath).create(recursive: true);
      }
    }
  } finally {
    await input.close();
  }
}
