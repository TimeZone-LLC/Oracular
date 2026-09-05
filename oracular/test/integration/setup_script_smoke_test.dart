// Smoke test for the standalone `setup.dart` shipped in every template
// ZIP (T3.2). For each template:
//
//   1. Build the ZIP by calling `scripts/package_template.dart` (the
//      same code the GitHub Action runs in matrix).
//   2. Extract the ZIP to a fresh temp dir using `package:archive`.
//   3. From inside the extracted dir, run
//      `dart setup.dart --name smoke_app --org com.example
//                       --no-pub-get --no-install-oracular -y
//                       --output-dir <sibling>`
//      exactly as a user would.
//   4. Assert structural correctness on the staged output:
//        - primary project directory exists
//        - `pubspec.yaml` has the rewritten `name:`
//        - no canonical template tokens leaked into text files
//        - embed template produces both `_web` + `_app` siblings
//        - jaspr templates honor `--render-mode`
//
// This explicitly does NOT run `pub get` (slow, requires network) or
// `flutter create` (slow, requires Flutter SDK). The contract under
// test is "given an extracted ZIP, can setup.dart produce a valid
// project tree on disk?" — exactly what plan §4.5 promises.
@TestOn('vm')
library;

import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:oracular/version.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Repo root inferred relative to oracular/.
late final Directory _repoRoot;

/// Absolute path to scripts/setup_template_template.dart (the skeleton).
/// We package each ZIP with this skeleton as setup.dart inside.
late final String _skeletonPath;

/// Absolute path to scripts/package_template.dart.
late final String _packagerPath;

/// Absolute path to scripts/generate_setup_script.dart.
late final String _generatorPath;

/// One-shot generated setup.dart, reused across all templates.
late final String _generatedSetupPath;

/// Version + build-id for all packaging in this run. Read from
/// `lib/version.dart` so the generator's pubspec/version.dart cross-check
/// never fails after a release bump.
const String _version = oracularVersion;
final String _buildId =
    '$_version+${DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[^0-9TZ]'), '').substring(0, 16)}Z-smoke';

void main() {
  setUpAll(() async {
    _repoRoot = Directory.current.path.endsWith('oracular')
        ? Directory.current.parent
        : Directory.current;
    _skeletonPath =
        p.join(_repoRoot.path, 'scripts', 'setup_template_template.dart');
    _packagerPath =
        p.join(_repoRoot.path, 'scripts', 'package_template.dart');
    _generatorPath =
        p.join(_repoRoot.path, 'scripts', 'generate_setup_script.dart');

    expect(File(_skeletonPath).existsSync(), isTrue,
        reason: 'Skeleton not found at $_skeletonPath');
    expect(File(_packagerPath).existsSync(), isTrue,
        reason: 'Packager not found at $_packagerPath');
    expect(File(_generatorPath).existsSync(), isTrue,
        reason: 'Generator not found at $_generatorPath');

    // 1. Generate setup.dart once (~200ms) into a fixed temp location;
    //    reused by every packaging call in this test file.
    final Directory genDir =
        await Directory.systemTemp.createTemp('oracular_smoke_setup_');
    _generatedSetupPath = p.join(genDir.path, 'setup.dart');
    final ProcessResult gen = await Process.run(
      'dart',
      <String>[
        'run',
        _generatorPath,
        '--version',
        _version,
        '--build-id',
        _buildId,
        '--out',
        _generatedSetupPath,
      ],
      workingDirectory: _repoRoot.path,
    );
    if (gen.exitCode != 0) {
      fail(
        'generate_setup_script.dart failed (exit ${gen.exitCode}).\n'
        'stdout: ${gen.stdout}\n'
        'stderr: ${gen.stderr}',
      );
    }
    expect(File(_generatedSetupPath).existsSync(), isTrue,
        reason: 'Generator did not produce setup.dart');
  });

  group('setup.dart smoke per template', () {
    // Tests are written in deterministic order; each runs ZIP build +
    // extract + setup in ~5-10s. Total ~45-90s for 9 templates.
    _testTemplate(
      templateName: 'arcane_app',
      primaryProject: 'smoke_app',
      expectPubspecNameLine: 'name: smoke_app',
    );
    _testTemplate(
      templateName: 'arcane_beamer_app',
      primaryProject: 'smoke_app',
      expectPubspecNameLine: 'name: smoke_app',
    );
    _testTemplate(
      templateName: 'arcane_dock_app',
      primaryProject: 'smoke_app',
      expectPubspecNameLine: 'name: smoke_app',
    );
    _testTemplate(
      templateName: 'arcane_cli_app',
      primaryProject: 'smoke_app',
      expectPubspecNameLine: 'name: smoke_app',
    );
    _testTemplate(
      templateName: 'arcane_jaspr_app',
      primaryProject: 'smoke_app_web',
      expectPubspecNameLine: 'name: smoke_app_web',
      renderMode: 'csr',
    );
    _testTemplate(
      templateName: 'arcane_jaspr_app',
      primaryProject: 'smoke_app_web',
      expectPubspecNameLine: 'name: smoke_app_web',
      renderMode: 'ssr',
      testDescriptionSuffix: ' (SSR mode)',
    );
    _testTemplate(
      templateName: 'arcane_jaspr_docs',
      primaryProject: 'smoke_app_web',
      expectPubspecNameLine: 'name: smoke_app_web',
      renderMode: 'ssg',
    );
    _testTemplate(
      templateName: 'arcane_jaspr_flutter_embed',
      primaryProject: 'smoke_app_web',
      expectPubspecNameLine: 'name: smoke_app_web',
      renderMode: 'embed',
      embedGuestProject: 'smoke_app_app',
      embedGuestPubspecNameLine: 'name: smoke_app_app',
    );
    _testTemplate(
      templateName: 'arcane_models',
      primaryProject: 'smoke_app_models',
      expectPubspecNameLine: 'name: smoke_app_models',
    );
    _testTemplate(
      templateName: 'arcane_server',
      primaryProject: 'smoke_app_server',
      expectPubspecNameLine: 'name: smoke_app_server',
    );
  });

  // ─────────────────────────────────────────────────────────────────
  // Regression: `--with-models` on a single-template ZIP (i.e. the
  // models template is NOT bundled) must produce a *commented* hint
  // rather than an active `path:` dep that breaks `pub get`.
  // Reported & fixed during T5 dry-run, 2026-05-11.
  // ─────────────────────────────────────────────────────────────────
  group('setup.dart --with-models without bundled models', () {
    _testCommentedModelsHint(
      templateName: 'arcane_jaspr_app',
      primaryProject: 'smoke_app_web',
      renderMode: 'ssr',
    );
    _testCommentedModelsHint(
      templateName: 'arcane_jaspr_flutter_embed',
      primaryProject: 'smoke_app_web',
      renderMode: 'embed',
      embedGuestProject: 'smoke_app_app',
    );
  });

  // ─────────────────────────────────────────────────────────────────
  // Regression: `--output-dir` overlap with ZIP root must be refused
  // (otherwise stageTemplate / _copyDirectoryRaw infinite-recurses).
  // Reported & fixed during T5.6 dry-run, 2026-05-11.
  // Covers macOS `/tmp -> /private/tmp` symlink edge.
  // ─────────────────────────────────────────────────────────────────
  group('setup.dart --output-dir overlap refusal', () {
    _testOutputDirOverlapRefused(
      description: 'refuses --output-dir == zipRoot',
      relativeOutputDir: '.',
      expectErrorContains: 'Refusing to write into the ZIP root',
    );
    _testOutputDirOverlapRefused(
      description: 'refuses --output-dir INSIDE zipRoot',
      relativeOutputDir: 'nested_out',
      expectErrorContains: 'because it is inside the ZIP root',
    );
  });
}

// ─────────────────────────────────────────────────────────────────────
// Per-template test factory.
// ─────────────────────────────────────────────────────────────────────

void _testTemplate({
  required String templateName,
  required String primaryProject,
  required String expectPubspecNameLine,
  String? renderMode,
  String? embedGuestProject,
  String? embedGuestPubspecNameLine,
  String testDescriptionSuffix = '',
}) {
  final String desc =
      '$templateName → $primaryProject/$testDescriptionSuffix';
  test(desc, () async {
    // 1. Build the ZIP.
    final Directory zipOutDir =
        await Directory.systemTemp.createTemp('oracular_smoke_zip_');
    final ProcessResult pkg = await Process.run(
      'dart',
      <String>[
        'run',
        _packagerPath,
        '--template',
        templateName,
        '--version',
        _version,
        '--build-id',
        _buildId,
        '--setup-script',
        _generatedSetupPath,
        '--out',
        zipOutDir.path,
      ],
      workingDirectory: _repoRoot.path,
    );
    if (pkg.exitCode != 0) {
      await zipOutDir.delete(recursive: true);
      fail(
        'package_template.dart failed for $templateName (exit ${pkg.exitCode}).\n'
        'stdout: ${pkg.stdout}\n'
        'stderr: ${pkg.stderr}',
      );
    }

    final String zipPath =
        p.join(zipOutDir.path, '$templateName-v$_version.zip');
    expect(File(zipPath).existsSync(), isTrue,
        reason: 'Expected packaged ZIP at $zipPath');

    // 2. Extract.
    final Directory extracted =
        await Directory.systemTemp.createTemp('oracular_smoke_extract_');
    await _extractZip(zipPath, extracted);

    // Sanity: the extracted root must hold the setup.dart we generated,
    // a VERSION file, and a README.
    expect(File(p.join(extracted.path, 'setup.dart')).existsSync(), isTrue,
        reason: 'setup.dart missing from extracted ZIP for $templateName');
    expect(File(p.join(extracted.path, 'VERSION')).existsSync(), isTrue,
        reason: 'VERSION missing from extracted ZIP for $templateName');

    // 3. Run setup.dart from inside the extracted dir.
    final Directory outDir =
        await Directory.systemTemp.createTemp('oracular_smoke_out_');
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
      '--no-install-oracular',
      '--yes',
      if (renderMode != null) ...<String>['--render-mode', renderMode],
    ];

    final ProcessResult setup = await Process.run(
      'dart',
      setupArgs,
      workingDirectory: extracted.path,
      environment: <String, String>{'NO_COLOR': '1'},
    );
    if (setup.exitCode != 0) {
      await Future.wait(<Future<void>>[
        zipOutDir.delete(recursive: true),
        extracted.delete(recursive: true),
        outDir.delete(recursive: true),
      ]);
      fail(
        'setup.dart failed for $templateName (exit ${setup.exitCode}).\n'
        'args: ${setupArgs.join(' ')}\n'
        'stdout: ${setup.stdout}\n'
        'stderr: ${setup.stderr}',
      );
    }

    // 4. Structural assertions.
    final Directory primary = Directory(p.join(outDir.path, primaryProject));
    expect(primary.existsSync(), isTrue,
        reason:
            'Primary project dir "$primaryProject" not found in ${outDir.path} '
            'for template "$templateName". '
            'Children: ${outDir.listSync().map((FileSystemEntity e) => p.basename(e.path)).toList()}');

    final File primaryPubspec = File(p.join(primary.path, 'pubspec.yaml'));
    expect(primaryPubspec.existsSync(), isTrue,
        reason: 'pubspec.yaml missing in primary project for $templateName');
    final String primaryPubspecContent = primaryPubspec.readAsStringSync();
    expect(primaryPubspecContent, contains(expectPubspecNameLine),
        reason:
            'Expected "$expectPubspecNameLine" in pubspec.yaml for $templateName.\n'
            'Actual first 200 chars:\n${primaryPubspecContent.substring(0, primaryPubspecContent.length.clamp(0, 200))}');

    // 5. No leftover canonical tokens (covers the placeholder rules).
    _assertNoLeftoverTokens(primary, templateName);

    // 6. Jaspr render-mode patch landed in pubspec/jaspr.yaml.
    if (renderMode != null) {
      _assertRenderModePatched(primary, renderMode, templateName);
    }

    // 7. Embed: guest package was lifted as a sibling, not nested.
    if (embedGuestProject != null) {
      final Directory guest =
          Directory(p.join(outDir.path, embedGuestProject));
      expect(guest.existsSync(), isTrue,
          reason:
              'Embed guest "$embedGuestProject" not found in ${outDir.path} '
              'for template "$templateName". '
              'Children: ${outDir.listSync().map((FileSystemEntity e) => p.basename(e.path)).toList()}');
      final File guestPubspec = File(p.join(guest.path, 'pubspec.yaml'));
      expect(guestPubspec.existsSync(), isTrue,
          reason: 'Embed guest pubspec.yaml missing');
      expect(guestPubspec.readAsStringSync(),
          contains(embedGuestPubspecNameLine!),
          reason:
              'Expected "$embedGuestPubspecNameLine" in embed guest pubspec.');

      // The primary should NOT contain a nested
      // `arcane_jaspr_flutter_embed_app/` dir (it was supposed to be
      // lifted out).
      expect(
          Directory(p.join(primary.path, 'arcane_jaspr_flutter_embed_app'))
              .existsSync(),
          isFalse,
          reason:
              'Embed guest was not lifted out of primary for $templateName');
    }

    // Clean up.
    await Future.wait(<Future<void>>[
      zipOutDir.delete(recursive: true),
      extracted.delete(recursive: true),
      outDir.delete(recursive: true),
    ]);
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/// Regression test factory for the `--with-models` + no-bundled-models
/// case (the per-template ZIP path, not the bundle). Asserts that
/// `setup.dart` writes a *commented* hint instead of an active
/// `path: ../<name>_models` dep that would crash `pub get`.
void _testCommentedModelsHint({
  required String templateName,
  required String primaryProject,
  required String renderMode,
  String? embedGuestProject,
}) {
  test('$templateName --with-models (no models in ZIP) -> commented hint',
      () async {
    // 1. Build the ZIP (no models template will be bundled — this is
    //    intentional; the per-template ZIP path ships only the one
    //    template).
    final Directory zipOutDir =
        await Directory.systemTemp.createTemp('oracular_regr_zip_');
    final ProcessResult pkg = await Process.run(
      'dart',
      <String>[
        'run',
        _packagerPath,
        '--template',
        templateName,
        '--version',
        _version,
        '--build-id',
        _buildId,
        '--setup-script',
        _generatedSetupPath,
        '--out',
        zipOutDir.path,
      ],
      workingDirectory: _repoRoot.path,
    );
    expect(pkg.exitCode, equals(0),
        reason:
            'package_template.dart failed for $templateName:\n${pkg.stderr}');

    final String zipPath =
        p.join(zipOutDir.path, '$templateName-v$_version.zip');
    final Directory extracted =
        await Directory.systemTemp.createTemp('oracular_regr_extract_');
    await _extractZip(zipPath, extracted);

    // Sanity: arcane_models template should NOT be inside this ZIP.
    expect(
      Directory(p.join(extracted.path, 'arcane_models')).existsSync(),
      isFalse,
      reason:
          'Test premise broken: arcane_models was bundled in $templateName ZIP. '
          'The regression case only fires when models is absent.',
    );

    // 2. Run setup.dart with --with-models.
    final Directory outDir =
        await Directory.systemTemp.createTemp('oracular_regr_out_');
    final ProcessResult setup = await Process.run(
      'dart',
      <String>[
        'run',
        p.join(extracted.path, 'setup.dart'),
        '--name',
        'smoke_app',
        '--org',
        'com.example',
        '--render-mode',
        renderMode,
        '--with-models',
        '--output-dir',
        outDir.path,
        '--no-pub-get',
        '--no-install-oracular',
        '--yes',
      ],
      workingDirectory: extracted.path,
      environment: <String, String>{'NO_COLOR': '1'},
    );
    expect(setup.exitCode, equals(0),
        reason:
            'setup.dart with --with-models crashed for $templateName:\n'
            'stdout: ${setup.stdout}\nstderr: ${setup.stderr}');

    // 3. Verify the warning was emitted (so users know to fetch
    //    arcane_models separately).
    final String combinedOutput = '${setup.stdout}${setup.stderr}';
    expect(
      combinedOutput,
      contains('no models template is bundled'),
      reason:
          'Expected a warning that models is not bundled in this ZIP for '
          '$templateName. Output was:\n$combinedOutput',
    );

    // 4. The active `path:` dep must NOT be present (this was the bug).
    final File primaryPubspec =
        File(p.join(outDir.path, primaryProject, 'pubspec.yaml'));
    expect(primaryPubspec.existsSync(), isTrue,
        reason: 'Primary pubspec.yaml missing for $templateName');
    final String primaryContent = primaryPubspec.readAsStringSync();
    final RegExp activeModelsDep =
        RegExp(r'^\s+smoke_app_models:\s*$', multiLine: true);
    final Match? leak = activeModelsDep.firstMatch(primaryContent);
    expect(leak, isNull,
        reason:
            'BUG REGRESSION: Active smoke_app_models: dep injected into '
            '$templateName/pubspec.yaml even though models template was not '
            'bundled. This would crash `pub get`.\n'
            'pubspec.yaml dependencies block:\n'
            '${_dependenciesBlock(primaryContent)}');

    // 5. The *commented* hint MUST be present.
    expect(
      primaryContent,
      contains('# smoke_app_models:'),
      reason:
          'Expected commented hint "# smoke_app_models:" in $templateName '
          'pubspec.yaml.\nActual:\n${_dependenciesBlock(primaryContent)}',
    );

    // 6. Same checks for the embed guest pubspec.yaml.
    if (embedGuestProject != null) {
      final File guestPubspec =
          File(p.join(outDir.path, embedGuestProject, 'pubspec.yaml'));
      expect(guestPubspec.existsSync(), isTrue,
          reason:
              'Embed guest pubspec.yaml missing at ${guestPubspec.path}');
      final String guestContent = guestPubspec.readAsStringSync();
      expect(activeModelsDep.firstMatch(guestContent), isNull,
          reason:
              'BUG REGRESSION: Active smoke_app_models: dep injected into '
              'embed guest pubspec for $templateName.');
      expect(
        guestContent,
        contains('# smoke_app_models:'),
        reason:
            'Expected commented hint in embed guest pubspec for '
            '$templateName.',
      );
    }

    // 7. The .oracular_deps/ shim folder must not contain a stale
    //    models entry (only Jaspr shims like jpatch/artifact_gen).
    final Directory shimDir =
        Directory(p.join(outDir.path, primaryProject, '.oracular_deps'));
    if (shimDir.existsSync()) {
      final bool hasModelsShim = shimDir
          .listSync()
          .whereType<Directory>()
          .any((Directory d) => p.basename(d.path).endsWith('_models'));
      expect(hasModelsShim, isFalse,
          reason: 'Stale models shim leaked into .oracular_deps/');
    }

    // Clean up.
    await Future.wait(<Future<void>>[
      zipOutDir.delete(recursive: true),
      extracted.delete(recursive: true),
      outDir.delete(recursive: true),
    ]);
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/// Snip just the dependencies / dependency_overrides block from a
/// pubspec.yaml for use in error messages.
String _dependenciesBlock(String pubspec) {
  final RegExp r =
      RegExp(r'^(dependencies|dependency_overrides):.*?(?=^\S|\Z)', multiLine: true, dotAll: true);
  return r.allMatches(pubspec).map((Match m) => m.group(0)).join('\n---\n');
}

/// Regression test factory for the `--output-dir` overlap refusal.
/// Verifies that running `setup.dart` with an `--output-dir` that
/// equals or is INSIDE the ZIP extraction directory exits non-zero
/// with a clear error message, instead of infinite-recursing through
/// `_copyDirectoryRaw`. Uses `arcane_app` as the template since the
/// bug is in `stageTemplate`/`_run` and is template-agnostic.
void _testOutputDirOverlapRefused({
  required String description,
  required String relativeOutputDir,
  required String expectErrorContains,
}) {
  test(description, () async {
    // 1. Build the ZIP.
    final Directory zipOutDir =
        await Directory.systemTemp.createTemp('oracular_ovrlap_zip_');
    final ProcessResult pkg = await Process.run(
      'dart',
      <String>[
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
      ],
      workingDirectory: _repoRoot.path,
    );
    expect(pkg.exitCode, equals(0),
        reason: 'package_template.dart failed:\n${pkg.stderr}');

    final String zipPath =
        p.join(zipOutDir.path, 'arcane_app-v$_version.zip');
    final Directory extracted =
        await Directory.systemTemp.createTemp('oracular_ovrlap_extract_');
    await _extractZip(zipPath, extracted);

    // 2. Run setup.dart with --output-dir overlapping zipRoot.
    //    Time-cap to 30s — without the safety guard, this would
    //    infinite-recurse and never return on its own.
    final String outputDirArg = relativeOutputDir == '.'
        ? extracted.path
        : p.join(extracted.path, relativeOutputDir);

    final Process setup = await Process.start(
      'dart',
      <String>[
        'run',
        p.join(extracted.path, 'setup.dart'),
        '--name',
        'overlap_app',
        '--org',
        'com.example',
        '--output-dir',
        outputDirArg,
        '--no-pub-get',
        '--no-install-oracular',
        '--yes',
      ],
      workingDirectory: extracted.path,
      environment: <String, String>{'NO_COLOR': '1'},
    );

    final List<int> stdoutBytes = <int>[];
    final List<int> stderrBytes = <int>[];
    setup.stdout.listen(stdoutBytes.addAll);
    setup.stderr.listen(stderrBytes.addAll);

    final int exitCode = await setup.exitCode
        .timeout(const Duration(seconds: 30), onTimeout: () {
      setup.kill(ProcessSignal.sigkill);
      return -1;
    });

    final String combinedOutput = String.fromCharCodes(stdoutBytes) +
        String.fromCharCodes(stderrBytes);

    expect(exitCode, isNot(equals(-1)),
        reason:
            'setup.dart did not return within 30s — likely the '
            'overlap-refusal guard regressed and we hit the infinite '
            'recursion bug. Partial output:\n$combinedOutput');
    expect(exitCode, isNot(equals(0)),
        reason:
            'setup.dart should have refused but exited 0. Output:\n'
            '$combinedOutput');
    expect(combinedOutput, contains(expectErrorContains),
        reason:
            'Expected error message containing "$expectErrorContains" '
            'in stderr. Actual output:\n$combinedOutput');

    await Future.wait(<Future<void>>[
      zipOutDir.delete(recursive: true),
      extracted.delete(recursive: true),
    ]);
  }, timeout: const Timeout(Duration(minutes: 2)));
}

// ─────────────────────────────────────────────────────────────────────
// Helpers.
// ─────────────────────────────────────────────────────────────────────

/// Extract [zipPath] into [target] using `package:archive`.
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

/// Canonical tokens that the placeholder replacer should have fully
/// erased from the staged project. Each must NOT appear as a bare
/// token (substring is fine — we only catch obvious leaks).
const List<String> _canonicalTokens = <String>[
  'arcane_jaspr_flutter_embed_web',
  'arcane_jaspr_flutter_embed_app',
  'arcane_jaspr_docs',
  'arcane_jaspr_app',
  'arcane_beamer_app',
  'arcane_dock_app',
  'arcane_cli_app',
  // Note: `arcane_app` overlaps with all the *_app templates. Skip the
  // bare check; the replacer's longest-first ordering is exhaustively
  // verified by setup_script_parity_test.dart. Same for arcane_models /
  // arcane_server, which are also bare tokens and appear in some
  // template READMEs and licenses we deliberately don't rewrite.
];

/// Text file extensions worth grepping for leftover tokens. Must match
/// PlaceholderReplacer.textFileExtensions exactly so we never assert
/// against a file the rewriter intentionally skipped.
const List<String> _scanExtensions = <String>[
  '.dart', '.yaml', '.yml', '.json', '.md', '.txt', '.sh',
  '.xml', '.plist', '.xcconfig', '.xcscheme', '.swift', '.kt',
  '.kts', '.gradle', '.properties', '.cc', '.h', '.cmake',
  '.html', '.js', '.css', '.entitlements',
];

void _assertNoLeftoverTokens(Directory dir, String templateName) {
  final List<String> leaks = <String>[];
  for (final FileSystemEntity e in dir.listSync(recursive: true)) {
    if (e is! File) continue;
    final String ext = p.extension(e.path).toLowerCase();
    if (!_scanExtensions.contains(ext)) continue;
    // Skip pubspec.lock and other generated bits.
    if (p.basename(e.path) == 'pubspec.lock') continue;
    final String content;
    try {
      content = e.readAsStringSync();
    } catch (_) {
      continue; // binary or unreadable
    }
    for (final String token in _canonicalTokens) {
      if (content.contains(token)) {
        leaks.add('${p.relative(e.path, from: dir.path)}: contains "$token"');
      }
    }
  }
  expect(leaks, isEmpty,
      reason:
          'Canonical tokens leaked through placeholder replacement '
          'for template "$templateName":\n${leaks.join("\n")}');
}

void _assertRenderModePatched(
    Directory primary, String renderMode, String templateName) {
  // Resolve expected jaspr mode (mirrors JasprRenderMode.jasprYamlMode).
  final String expectedMode;
  switch (renderMode) {
    case 'csr':
      expectedMode = 'client';
    case 'ssg':
    case 'embed':
      expectedMode = 'static';
    case 'ssr':
    case 'hybrid':
      expectedMode = 'server';
    default:
      fail('Unknown renderMode "$renderMode" in test setup.');
  }

  // pubspec.yaml jaspr.mode is authoritative.
  final File pubspec = File(p.join(primary.path, 'pubspec.yaml'));
  final String content = pubspec.readAsStringSync();
  final RegExp jasprMode = RegExp(
    r'^jaspr:\s*$\s*^\s+mode:\s*(\S+)',
    multiLine: true,
  );
  final Match? m = jasprMode.firstMatch(content);
  if (m != null) {
    expect(m.group(1), equals(expectedMode),
        reason:
            'pubspec.yaml jaspr.mode for "$templateName" should be '
            '"$expectedMode" (render-mode=$renderMode).');
    return;
  }
  // Fallback: jaspr.yaml mode line.
  final File jasprYaml = File(p.join(primary.path, 'jaspr.yaml'));
  if (jasprYaml.existsSync()) {
    final RegExp line = RegExp(r'^mode:\s*(\S+)', multiLine: true);
    final Match? jm = line.firstMatch(jasprYaml.readAsStringSync());
    expect(jm?.group(1), equals(expectedMode),
        reason:
            'jaspr.yaml mode for "$templateName" should be "$expectedMode" '
            '(render-mode=$renderMode).');
    return;
  }
  fail(
    'No jaspr mode location found in primary for "$templateName"; '
    'expected pubspec.yaml jaspr.mode OR jaspr.yaml mode.',
  );
}
