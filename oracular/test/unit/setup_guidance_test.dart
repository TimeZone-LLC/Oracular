import 'dart:async';

import 'package:oracular/models/setup_config.dart';
import 'package:oracular/models/template_info.dart';
import 'package:oracular/services/firebase_setup_orchestrator.dart';
import 'package:oracular/utils/setup_guidance.dart';
import 'package:test/test.dart';

/// Run [body] inside a zone that captures every `print` call into the
/// returned list. Used for asserting on `printPostCreationChecklist`.
List<String> _captureStdout(void Function() body) {
  final List<String> captured = <String>[];
  runZoned<void>(
    body,
    zoneSpecification: ZoneSpecification(
      print: (Zone _, ZoneDelegate _, Zone _, String line) {
        captured.add(line);
      },
    ),
  );
  return captured;
}

void main() {
  group('SetupGuidance', () {
    test('uses web package name for Jaspr templates', () {
      final SetupConfig config = SetupConfig(
        appName: 'my_app',
        orgDomain: 'com.example',
        baseClassName: 'MyApp',
        template: TemplateType.arcaneJaspr,
        outputDir: '/tmp/project',
      );

      expect(SetupGuidance.mainProjectName(config), equals('my_app_web'));
      expect(SetupGuidance.runCommand(config), equals('jaspr serve'));
    });

    test('uses app name for Flutter templates', () {
      final SetupConfig config = SetupConfig(
        appName: 'my_app',
        orgDomain: 'com.example',
        baseClassName: 'MyApp',
        template: TemplateType.arcaneTemplate,
        outputDir: '/tmp/project',
        platforms: const <String>['android', 'web'],
      );

      expect(SetupGuidance.mainProjectName(config), equals('my_app'));
      expect(SetupGuidance.runCommand(config), equals('flutter run'));
      expect(SetupGuidance.supportsWebHosting(config), isTrue);
    });

    test('detects non-web Flutter projects as not hostable', () {
      final SetupConfig config = SetupConfig(
        appName: 'my_app',
        orgDomain: 'com.example',
        baseClassName: 'MyApp',
        template: TemplateType.arcaneDock,
        outputDir: '/tmp/project',
        platforms: const <String>['linux', 'macos', 'windows'],
      );

      expect(SetupGuidance.supportsWebHosting(config), isFalse);
    });

    test('builds hosting URLs from project ID', () {
      expect(
        SetupGuidance.releaseHostingUrl('example-project'),
        equals('https://example-project.web.app'),
      );
      expect(
        SetupGuidance.betaHostingUrl('example-project'),
        equals('https://example-project-beta.web.app'),
      );
    });

    test(
        'includes .oracular_deps item only when shims are vendored '
        '(models on a non-Flutter template)', () {
      final SetupConfig withModels = SetupConfig(
        appName: 'docs_site',
        orgDomain: 'com.example',
        baseClassName: 'DocsSite',
        template: TemplateType.arcaneJasprDocs,
        outputDir: '/tmp/project',
        createModels: true,
      );
      expect(
        SetupGuidance.createdProjectItems(withModels)
            .any((String item) => item.startsWith('.oracular_deps/')),
        isTrue,
      );

      final SetupConfig withoutModels = withModels.copyWith(
        createModels: false,
      );
      expect(
        SetupGuidance.createdProjectItems(withoutModels)
            .any((String item) => item.startsWith('.oracular_deps/')),
        isFalse,
      );
    });

    test('generates click-through Firebase and server guide content', () {
      final SetupConfig config = SetupConfig(
        appName: 'my_app',
        orgDomain: 'com.example',
        baseClassName: 'MyApp',
        template: TemplateType.arcaneTemplate,
        outputDir: '/tmp/project',
        createServer: true,
        useFirebase: true,
        firebaseProjectId: 'example-project',
        setupCloudRun: true,
        platforms: const <String>['web'],
      );

      final String guide = SetupGuidance.projectGuideMarkdown(config);

      expect(guide, contains('oracular open firebase'));
      expect(guide, contains('oracular open auth'));
      expect(guide, contains('oracular open cloud-run'));
      expect(
        guide,
        contains(
          SetupGuidance.firebaseAuthenticationConsoleUrl('example-project'),
        ),
      );
      expect(
        guide,
        contains(SetupGuidance.cloudRunConsoleUrl('example-project')),
      );
      expect(guide, contains('./script_deploy.sh'));
    });

    test('markdown documents firebase-setup-full umbrella + sub-commands', () {
      final SetupConfig config = SetupConfig(
        appName: 'my_app',
        orgDomain: 'com.example',
        baseClassName: 'MyApp',
        template: TemplateType.arcaneTemplate,
        outputDir: '/tmp/project',
        useFirebase: true,
        firebaseProjectId: 'example-project',
        platforms: const <String>['web'],
      );

      final String guide = SetupGuidance.projectGuideMarkdown(config);

      // New umbrella command
      expect(guide, contains('oracular deploy firebase-setup-full'));
      // New sub-commands
      expect(guide, contains('oracular deploy firestore-init'));
      expect(guide, contains('oracular deploy storage-init'));
      expect(guide, contains('oracular deploy auth-providers'));
      expect(guide, contains('oracular check billing'));
      expect(guide, contains('oracular deploy hosting-init'));
      // Old name should be gone
      expect(guide, isNot(contains('oracular deploy firebase-setup ')));
    });

    test('markdown adds Jaspr-specific copy for Jaspr web templates', () {
      final SetupConfig config = SetupConfig(
        appName: 'my_app',
        orgDomain: 'com.example',
        baseClassName: 'MyApp',
        template: TemplateType.arcaneJaspr,
        outputDir: '/tmp/project',
        useFirebase: true,
        firebaseProjectId: 'example-project',
      );

      final String guide = SetupGuidance.projectGuideMarkdown(config);

      expect(guide, contains('# Hosting (Jaspr)'));
      expect(guide, contains('jaspr build'));
      // Default mode for arcaneJaspr is CSR → public dir is build/jaspr/ (no /web).
      expect(guide, contains('${config.webPackageName}/build/jaspr/'));
      expect(
        guide,
        isNot(contains('${config.webPackageName}/build/jaspr/web/')),
        reason: 'CSR mode should publish from build/jaspr/, not build/jaspr/web/',
      );
    });

    test(
      'markdown points SSR Jaspr at build/jaspr/web/ public dir',
      () {
        final SetupConfig config = SetupConfig(
          appName: 'my_app',
          orgDomain: 'com.example',
          baseClassName: 'MyApp',
          template: TemplateType.arcaneJaspr,
          outputDir: '/tmp/project',
          useFirebase: true,
          firebaseProjectId: 'example-project',
          jasprRenderMode: JasprRenderMode.ssr,
        );

        final String guide = SetupGuidance.projectGuideMarkdown(config);

        expect(guide, contains('${config.webPackageName}/build/jaspr/web/'));
      },
    );

    test('markdown lists Flutter-specific copy for Flutter web templates', () {
      final SetupConfig config = SetupConfig(
        appName: 'my_app',
        orgDomain: 'com.example',
        baseClassName: 'MyApp',
        template: TemplateType.arcaneTemplate,
        outputDir: '/tmp/project',
        useFirebase: true,
        firebaseProjectId: 'example-project',
        platforms: const <String>['web'],
      );

      final String guide = SetupGuidance.projectGuideMarkdown(config);

      expect(guide, contains('# Hosting (Flutter web)'));
      expect(guide, isNot(contains('jaspr build')));
    });

    test('markdown server guide documents cleanup tunables + commands', () {
      final SetupConfig config = SetupConfig(
        appName: 'my_app',
        orgDomain: 'com.example',
        baseClassName: 'MyApp',
        template: TemplateType.arcaneTemplate,
        outputDir: '/tmp/project',
        createServer: true,
        useFirebase: true,
        firebaseProjectId: 'example-project',
        setupCloudRun: true,
        platforms: const <String>['web'],
        artifactKeepRecent: 7,
        artifactDeleteOlderDays: 45,
        cloudRunKeepRevisions: 2,
      );

      final String guide = SetupGuidance.projectGuideMarkdown(config);

      expect(
        guide,
        contains('Keep 7 most-recent Artifact Registry image versions'),
      );
      expect(guide, contains('Delete versions older than 45 days'));
      expect(guide, contains('Cap Cloud Run revisions at 2'));
      expect(guide, contains('oracular deploy artifact-cleanup'));
      expect(guide, contains('oracular deploy cloudrun-prune'));
    });
  });

  group('SetupGuidance.printPostCreationChecklist', () {
    SetupConfig flutterWebConfig() => SetupConfig(
          appName: 'my_app',
          orgDomain: 'com.example',
          baseClassName: 'MyApp',
          template: TemplateType.arcaneTemplate,
          outputDir: '/tmp/project',
          useFirebase: true,
          firebaseProjectId: 'example-project',
          platforms: const <String>['web'],
        );

    OrchestratorReport reportWith(Iterable<WizardSubStep> succeeded) {
      return OrchestratorReport(
        results: succeeded
            .map((WizardSubStep s) => SetupStepResult.success(s))
            .toList(),
      );
    }

    test('without report: prints every deploy step + umbrella reminder', () {
      final SetupConfig config = flutterWebConfig();
      final List<String> output = _captureStdout(
        () => SetupGuidance.printPostCreationChecklist(config),
      );
      final String joined = output.join('\n');

      expect(joined, contains('oracular deploy firebase-setup-full'));
      expect(joined, contains('oracular deploy firestore'));
      expect(joined, contains('oracular deploy storage'));
      expect(joined, contains('oracular deploy hosting'));
      expect(joined, contains('oracular deploy hosting-beta'));
    });

    test('with full success report: suppresses completed deploy steps', () {
      final SetupConfig config = flutterWebConfig();
      final OrchestratorReport report = reportWith(<WizardSubStep>{
        WizardSubStep.firebaseLogin,
        WizardSubStep.configureClient,
        WizardSubStep.deployFirestoreRules,
        WizardSubStep.deployStorageRules,
        WizardSubStep.deployHostingRelease,
        WizardSubStep.deployHostingBeta,
      });

      final List<String> output = _captureStdout(
        () => SetupGuidance.printPostCreationChecklist(
          config,
          report: report,
        ),
      );
      final String joined = output.join('\n');

      // Umbrella command is suppressed because login + configureClient are
      // already done.
      expect(joined, isNot(contains('oracular deploy firebase-setup-full')));
      // Per-deploy commands are suppressed.
      expect(joined, isNot(contains('oracular deploy firestore\n')));
      expect(joined, isNot(contains('oracular deploy storage\n')));
      expect(joined, isNot(contains('oracular deploy hosting\n')));
      expect(joined, isNot(contains('oracular deploy hosting-beta\n')));
      // The "all complete" message replaces the empty list.
      expect(
        joined,
        contains('All Firebase deploy steps already complete'),
      );
      // Live-URL phrasing replaces "(after deploy)".
      expect(joined, contains('Live release URL'));
      expect(joined, contains('Live beta URL'));
    });

    test('with partial report: keeps only the still-pending steps', () {
      final SetupConfig config = flutterWebConfig();
      // Only firestore + login + configure done — storage + hosting still pending.
      final OrchestratorReport report = reportWith(<WizardSubStep>{
        WizardSubStep.firebaseLogin,
        WizardSubStep.configureClient,
        WizardSubStep.deployFirestoreRules,
      });

      final List<String> output = _captureStdout(
        () => SetupGuidance.printPostCreationChecklist(
          config,
          report: report,
        ),
      );
      final String joined = output.join('\n');

      // Umbrella command is suppressed (login + configureClient done).
      expect(joined, isNot(contains('oracular deploy firebase-setup-full')));
      // Storage + hosting still listed.
      expect(joined, contains('oracular deploy storage'));
      expect(joined, contains('oracular deploy hosting'));
      expect(joined, contains('oracular deploy hosting-beta'));
      // Firestore is suppressed (no `firestore` substring on its own line).
      final List<String> lines = output.where((String l) =>
          l.contains('oracular deploy firestore') &&
          !l.contains('firestore-init')).toList();
      expect(lines, isEmpty);
    });

    test('Jaspr docs: includes hot-rebuild reminder line', () {
      final SetupConfig config = SetupConfig(
        appName: 'my_app',
        orgDomain: 'com.example',
        baseClassName: 'MyApp',
        template: TemplateType.arcaneJasprDocs,
        outputDir: '/tmp/project',
        useFirebase: true,
        firebaseProjectId: 'example-project',
      );

      final List<String> output = _captureStdout(
        () => SetupGuidance.printPostCreationChecklist(config),
      );
      final String joined = output.join('\n');

      expect(joined, contains('Jaspr Docs'));
      expect(joined, contains('hot-reloads code changes'));
      expect(
        joined,
        contains('restart the server to pick up new docs content'),
      );
    });

    test('server checklist: shows cleanup-installed when applied', () {
      final SetupConfig config = SetupConfig(
        appName: 'my_app',
        orgDomain: 'com.example',
        baseClassName: 'MyApp',
        template: TemplateType.arcaneTemplate,
        outputDir: '/tmp/project',
        createServer: true,
        useFirebase: true,
        firebaseProjectId: 'example-project',
        setupCloudRun: true,
        platforms: const <String>['web'],
      );
      final OrchestratorReport report = reportWith(<WizardSubStep>{
        WizardSubStep.applyArtifactCleanupPolicy,
      });

      final List<String> output = _captureStdout(
        () => SetupGuidance.printPostCreationChecklist(
          config,
          report: report,
        ),
      );
      final String joined = output.join('\n');

      expect(joined, contains('Artifact Registry cleanup policy already'));
    });

    test('server checklist: prompts to install cleanup when not applied', () {
      final SetupConfig config = SetupConfig(
        appName: 'my_app',
        orgDomain: 'com.example',
        baseClassName: 'MyApp',
        template: TemplateType.arcaneTemplate,
        outputDir: '/tmp/project',
        createServer: true,
        useFirebase: true,
        firebaseProjectId: 'example-project',
        setupCloudRun: true,
        platforms: const <String>['web'],
      );

      final List<String> output = _captureStdout(
        () => SetupGuidance.printPostCreationChecklist(config),
      );
      final String joined = output.join('\n');

      expect(joined, contains('oracular deploy artifact-cleanup'));
    });
  });
}
