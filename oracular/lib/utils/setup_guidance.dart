import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/setup_config.dart';
import '../models/template_info.dart';
import '../services/firebase_setup_orchestrator.dart'
    show OrchestratorReport, SetupStepResult, WizardSubStep;
import 'user_prompt.dart';

/// Shared setup guidance for post-create and deployment flows.
class SetupGuidance {
  static const String _firebaseConsoleBase =
      'https://console.firebase.google.com';
  static const String _firebaseHostingDocs =
      'https://firebase.google.com/docs/hosting';
  static const String _flutterFireSetupDocs =
      'https://firebase.google.com/docs/flutter/setup';
  static const String _flutterWebDeployDocs =
      'https://docs.flutter.dev/deployment/web';
  static const String _jasprDocs = 'https://docs.jaspr.site';
  static const String _cloudConsoleBase = 'https://console.cloud.google.com';

  static String projectGuidePath(SetupConfig config) {
    return p.join(config.outputDir, 'GET_STARTED.md');
  }

  static String mainProjectName(SetupConfig config) {
    return config.template.isJasprApp ? config.webPackageName : config.appName;
  }

  static String mainProjectPath(SetupConfig config) {
    return p.join(config.outputDir, mainProjectName(config));
  }

  static String mainProjectLabel(SetupConfig config) {
    return config.template.isJasprApp ? 'Web app' : 'Main application';
  }

  static bool supportsWebHosting(SetupConfig config) {
    return config.template.isJasprApp ||
        (config.template.isFlutterApp && config.platforms.contains('web'));
  }

  static String runCommand(SetupConfig config) {
    if (config.template.isFlutterApp) {
      return 'flutter run';
    }
    if (config.template.isJasprApp) {
      return 'jaspr serve';
    }
    return 'dart run bin/main.dart --help';
  }

  static List<String> createdProjectItems(SetupConfig config) {
    return <String>[
      '${mainProjectName(config)}/ - ${mainProjectLabel(config)}',
      if (config.createModels && !config.template.isFlutterApp)
        '.oracular_deps/ - Vendored pure-Dart shim packages',
      if (config.createModels)
        '${config.modelsPackageName}/ - Shared models package',
      if (config.createServer)
        '${config.serverPackageName}/ - Server application',
      config.useFirebase
          ? 'config/ - Generated setup and Firebase configuration'
          : 'config/ - Generated setup configuration',
      'references/ - Arcane and project reference docs',
      'docs/ - Commands, how-to guides, troubleshooting',
      'GET_STARTED.md - Step-by-step setup guide',
    ];
  }

  static void printPostCreationChecklist(
    SetupConfig config, {
    OrchestratorReport? report,
  }) {
    UserPrompt.printDivider(title: 'Project Setup Checklist');

    final List<String> steps = <String>[
      'cd ${mainProjectPath(config)}',
      runCommand(config),
    ];

    // Only show "run firebase-setup-full" if the orchestrator hasn't
    // already done it successfully (i.e. report is null or the FlutterFire/
    // FirebaseLogin/Configure step was not successful).
    if (config.useFirebase && _firebaseSetupNeeded(report)) {
      steps.add('cd ${config.outputDir}');
      steps.add('oracular deploy firebase-setup-full');
    }

    UserPrompt.printNumberedList(steps);

    if (config.useFirebase) {
      _printFirebaseChecklist(config, report: report);
    } else {
      _printEnableFirebaseLater(config);
    }

    if (config.template.isJasprDocs) {
      _printJasprDocsChecklist();
    }

    if (config.createModels && !config.template.isFlutterApp) {
      _printVendoredShimChecklist(config);
    }

    if (config.template.isJasprApp) {
      _printJasprRenderModeChecklist(config);
    }

    if (config.template == TemplateType.arcaneJasprFlutterEmbed) {
      _printFlutterEmbedChecklist(config);
    }

    if (config.createServer) {
      _printServerChecklist(config, report: report);
    }

    print('');
    UserPrompt.printList(<String>[
      'Full setup guide: ${projectGuidePath(config)}',
      'Docs folder: ${p.join(config.outputDir, 'docs')}/',
      'Reopen the guide later with: oracular guide',
      'Open the docs folder with: oracular open docs',
    ]);
  }

  /// Build a set of [WizardSubStep] values the orchestrator finished
  /// successfully on the most recent run. Used by the post-create
  /// checklist to suppress steps that no longer need user attention.
  static Set<WizardSubStep> _completedSteps(OrchestratorReport? report) {
    if (report == null) return <WizardSubStep>{};
    return report.results
        .where((SetupStepResult r) => r.success)
        .map((SetupStepResult r) => r.step)
        .toSet();
  }

  /// True when the user still needs to run `firebase-setup-full`. Returns
  /// false when login + configure-client + at least one rules deploy
  /// succeeded (in which case running the umbrella command would be a
  /// no-op).
  static bool _firebaseSetupNeeded(OrchestratorReport? report) {
    if (report == null) return true;
    final Set<WizardSubStep> done = _completedSteps(report);
    return !(done.contains(WizardSubStep.firebaseLogin) &&
        done.contains(WizardSubStep.configureClient));
  }

  static void printHostingSuccess(SetupConfig config, {required bool beta}) {
    final String? projectId = config.firebaseProjectId;
    if (projectId == null) {
      return;
    }

    final String url = beta
        ? betaHostingUrl(projectId)
        : releaseHostingUrl(projectId);
    final String channel = beta ? 'beta' : 'release';

    print('');
    UserPrompt.printList(<String>[
      'Hosting channel: $channel',
      'Live URL: $url',
      linkLine('Hosting console', firebaseHostingConsoleUrl(projectId)),
    ]);
  }

  static void printBetaSiteHint(String projectId) {
    print('');
    UserPrompt.printList(<String>[
      'If this is your first beta deploy, create the beta site once:',
      '  firebase hosting:sites:create $projectId-beta --project $projectId',
      'Then retry: oracular deploy hosting-beta',
    ]);
  }

  static String linkLine(String label, String url) {
    return '$label: $url';
  }

  static String firebaseOverviewUrl(String projectId) {
    return '$_firebaseConsoleBase/project/$projectId/overview';
  }

  static String firebaseHostingConsoleUrl(String projectId) {
    return '$_firebaseConsoleBase/project/$projectId/hosting';
  }

  static String firebaseAuthenticationConsoleUrl(String projectId) {
    return '$_firebaseConsoleBase/project/$projectId/authentication';
  }

  static String firebaseFirestoreConsoleUrl(String projectId) {
    return '$_firebaseConsoleBase/project/$projectId/firestore';
  }

  static String firebaseStorageConsoleUrl(String projectId) {
    return '$_firebaseConsoleBase/project/$projectId/storage';
  }

  static String firebaseServiceAccountUrl(String projectId) {
    return '$_firebaseConsoleBase/project/$projectId/settings/serviceaccounts/adminsdk';
  }

  static String cloudRunConsoleUrl(String projectId) {
    return '$_cloudConsoleBase/run?project=$projectId';
  }

  static String releaseHostingUrl(String projectId) {
    return 'https://$projectId.web.app';
  }

  static String betaHostingUrl(String projectId) {
    return 'https://$projectId-beta.web.app';
  }

  static void _printFirebaseChecklist(
    SetupConfig config, {
    OrchestratorReport? report,
  }) {
    final String? projectId = config.firebaseProjectId;
    if (projectId == null) {
      return;
    }

    UserPrompt.printDivider(title: 'Firebase & Hosting');

    final Set<WizardSubStep> done = _completedSteps(report);
    final List<String> deploySteps = <String>[
      if (!done.contains(WizardSubStep.deployFirestoreRules))
        'oracular deploy firestore',
      if (!done.contains(WizardSubStep.deployStorageRules))
        'oracular deploy storage',
      if (supportsWebHosting(config) &&
          !done.contains(WizardSubStep.deployHostingRelease))
        'oracular deploy hosting',
      if (supportsWebHosting(config) &&
          !done.contains(WizardSubStep.deployHostingBeta))
        'oracular deploy hosting-beta',
    ];

    if (deploySteps.isEmpty) {
      print('');
      UserPrompt.printList(<String>[
        '✓ All Firebase deploy steps already complete on the last run.',
        'Re-deploy at any time with `oracular deploy <command>`.',
      ]);
    } else {
      UserPrompt.printNumberedList(deploySteps);
    }

    if (!supportsWebHosting(config)) {
      print('');
      UserPrompt.printList(<String>[
        'Web hosting is currently unavailable because web is not enabled.',
        'To add web support later:',
        '  cd ${mainProjectPath(config)}',
        '  flutter create --platforms=web .',
      ]);
    } else if (!done.contains(WizardSubStep.deployHostingBeta)) {
      printBetaSiteHint(projectId);
    }

    print('');
    print('Helpful links:');
    UserPrompt.printList(<String>[
      linkLine('Firebase project overview', firebaseOverviewUrl(projectId)),
      linkLine('Hosting console', firebaseHostingConsoleUrl(projectId)),
      linkLine('Firebase Hosting docs', _firebaseHostingDocs),
      if (!done.contains(WizardSubStep.deployHostingRelease))
        linkLine('Release URL (after deploy)', releaseHostingUrl(projectId)),
      if (done.contains(WizardSubStep.deployHostingRelease))
        linkLine('Live release URL', releaseHostingUrl(projectId)),
      if (!done.contains(WizardSubStep.deployHostingBeta))
        linkLine('Beta URL (after deploy)', betaHostingUrl(projectId)),
      if (done.contains(WizardSubStep.deployHostingBeta))
        linkLine('Live beta URL', betaHostingUrl(projectId)),
      if (config.template.isFlutterApp)
        linkLine('Flutter web deployment docs', _flutterWebDeployDocs),
      if (config.template.isJasprApp) linkLine('Jaspr docs', _jasprDocs),
    ]);
  }

  static void _printEnableFirebaseLater(SetupConfig config) {
    final String configPath = p.join(
      config.outputDir,
      'config',
      'setup_config.env',
    );

    UserPrompt.printDivider(title: 'Enable Firebase Later');
    UserPrompt.printList(<String>[
      'Edit $configPath and set:',
      '  USE_FIREBASE=yes',
      '  FIREBASE_PROJECT_ID=<your-project-id>',
      'Then run: oracular deploy firebase-setup-full',
    ]);

    print('');
    print('Helpful links:');
    UserPrompt.printList(<String>[
      linkLine('Firebase console', _firebaseConsoleBase),
      linkLine('FlutterFire setup docs', _flutterFireSetupDocs),
    ]);
  }

  static void _printServerChecklist(
    SetupConfig config, {
    OrchestratorReport? report,
  }) {
    UserPrompt.printDivider(title: 'Server Deployment');
    final String serverServiceAccountPath = p.join(
      config.outputDir,
      config.serverPackageName,
      'service-account.json',
    );

    final Set<WizardSubStep> done = _completedSteps(report);
    final bool cleanupApplied =
        done.contains(WizardSubStep.applyArtifactCleanupPolicy);

    UserPrompt.printNumberedList(<String>[
      'cd ${p.join(config.outputDir, config.serverPackageName)}',
      './script_deploy.sh',
    ]);

    print('');
    UserPrompt.printList(<String>[
      'Use service account key file name: service-account.json',
      'Server key path: $serverServiceAccountPath',
      'When replacing keys, keep only the 2 latest backups (.bak.1 and .bak.2).',
      cleanupApplied
          ? '✓ Artifact Registry cleanup policy already installed '
              '(${config.artifactKeepRecent} recent + delete >'
              '${config.artifactDeleteOlderDays}d).'
          : 'After your first deploy, install cleanup with: '
              'oracular deploy artifact-cleanup',
    ]);

    if (config.firebaseProjectId != null) {
      print('');
      UserPrompt.printList(<String>[
        linkLine(
          'Service account keys',
          firebaseServiceAccountUrl(config.firebaseProjectId!),
        ),
      ]);
    }
  }

  static void _printJasprDocsChecklist() {
    UserPrompt.printDivider(title: 'Jaspr Docs');
    UserPrompt.printList(<String>[
      '`jaspr serve` hot-reloads code changes; restart the server to '
          'pick up new docs content (markdown additions, new pages).',
    ]);
  }

  static void _printVendoredShimChecklist(SetupConfig config) {
    final String depsPath = p.join(config.outputDir, '.oracular_deps');
    final String mainPubspec = p.join(
      config.outputDir,
      mainProjectName(config),
      'pubspec.yaml',
    );

    UserPrompt.printDivider(title: 'Vendored Dependency Shims');
    UserPrompt.printList(<String>[
      'Pure-Dart shim packages are vendored to $depsPath so '
          '${config.modelsPackageName} resolves without the Flutter SDK.',
      'Keep .oracular_deps/ next to ${mainProjectName(config)}/.',
      'If you move folders, update the dependency_overrides paths in '
          '$mainPubspec.',
    ]);
  }

  /// Print the per-render-mode build + deploy checklist appended for any
  /// Jaspr template. Added by T8.2 of the 2026-05-10 build/deploy/
  /// rendering-modes plan so the user knows exactly which commands
  /// correspond to the mode they picked in the wizard.
  static void _printJasprRenderModeChecklist(SetupConfig config) {
    final JasprRenderMode mode = config.jasprRenderMode;
    UserPrompt.printDivider(
      title: 'Jaspr Render Mode — ${mode.displayName}',
    );

    final List<String> lines = <String>[
      'Configured mode: ${mode.displayName} (${mode.name})',
      'jaspr.yaml is pre-wired with mode = ${_jasprYamlModeFor(mode)}.',
    ];

    switch (mode) {
      case JasprRenderMode.csr:
        lines.add(
          'Build:  oracular build jaspr-site   (output: '
          '${config.webPackageName}/build/jaspr/)',
        );
        lines.add('Deploy: oracular deploy hosting');
        lines.add(
          'No Cloud Run required — Firebase Hosting serves the static '
          'CSR bundle.',
        );
        break;
      case JasprRenderMode.ssg:
        lines.add(
          'Build:  oracular build jaspr-site   (prerendered HTML for SEO)',
        );
        lines.add('Deploy: oracular deploy hosting');
        lines.add(
          'Pre-render routes via lib/routes/static_routes.dart.',
        );
        break;
      case JasprRenderMode.ssr:
        lines.add(
          'Build:  oracular build jaspr-site   (Dart server in '
          '${config.webPackageName}/build/jaspr/app)',
        );
        lines.add('Deploy: oracular deploy jaspr-server  (Cloud Run)');
        lines.add(
          'Then:   oracular deploy hosting       '
          '(Hosting rewrites all paths to the Cloud Run service)',
        );
        if (config.firebaseProjectId != null) {
          lines.add(
            'Cloud Run console: ${cloudRunConsoleUrl(config.firebaseProjectId!)}',
          );
        }
        break;
      case JasprRenderMode.hybrid:
        lines.add(
          'Build:  oracular build jaspr-site   (Dart server + static islands)',
        );
        lines.add('Deploy: oracular deploy jaspr-server  (Cloud Run)');
        lines.add(
          'Then:   oracular deploy hosting       '
          '(SSG islands + hybrid rewrites)',
        );
        final List<String> prefixes = config.hybridDynamicPrefixes.isEmpty
            ? const <String>['/api', '/auth', '/admin']
            : config.hybridDynamicPrefixes;
        lines.add('SSR prefixes: ${prefixes.join(', ')}');
        lines.add(
          'Adjust at any time: '
          'oracular deploy generate-configs --hybrid-dynamic-prefix '
          '"/api,/auth,/admin"',
        );
        break;
      case JasprRenderMode.embed:
        lines.add(
          'Build:  oracular build flutter-embed   '
          '(Flutter web → Jaspr host → unified bundle)',
        );
        lines.add('Deploy: oracular deploy hosting');
        lines.add(
          'See "Jaspr + Flutter Embed" section below for the dual-package '
          'orientation.',
        );
        break;
    }

    UserPrompt.printList(lines);
  }

  /// Print the Flutter-embed-in-Jaspr orientation block.
  ///
  /// Added by T8.2 to call out that the embed template is two packages
  /// (the Jaspr host + the Flutter guest) and shows exactly which
  /// `oracular build` command produces the unified bundle.
  static void _printFlutterEmbedChecklist(SetupConfig config) {
    final String hostDir = p.join(config.outputDir, config.webPackageName);
    final String guestDir = p.join(
      config.outputDir,
      config.embeddedFlutterPackageName,
    );

    UserPrompt.printDivider(title: 'Jaspr + Flutter Embed');
    UserPrompt.printList(<String>[
      'Jaspr host package:    $hostDir',
      'Flutter guest package: $guestDir',
      'Mount path: ${config.embeddedFlutterMount} '
          '(Flutter web is copied into '
          '${config.webPackageName}/web${config.embeddedFlutterMount})',
      '',
      'Build (recommended one-shot):',
      '  oracular build flutter-embed',
      '',
      'Build pieces independently:',
      '  oracular build flutter-app   (Flutter web bundle only)',
      '  oracular build jaspr-site    (Jaspr static host only — uses the '
          'staged Flutter copy)',
      '',
      'Deploy: oracular deploy hosting   '
          '(serves the combined bundle from Firebase Hosting)',
    ]);
  }

  /// Map the [JasprRenderMode] to the literal string the Jaspr CLI
  /// expects in `jaspr.yaml`'s `mode` field. Used by both
  /// `_printJasprRenderModeChecklist` and the project guide markdown
  /// generator so the documentation stays in lock-step with the
  /// template_copier post-step.
  static String _jasprYamlModeFor(JasprRenderMode mode) {
    switch (mode) {
      case JasprRenderMode.csr:
        return 'client';
      case JasprRenderMode.ssg:
      case JasprRenderMode.embed:
        return 'static';
      case JasprRenderMode.ssr:
      case JasprRenderMode.hybrid:
        return 'server';
    }
  }

  static Future<File> writeProjectGuide(SetupConfig config) async {
    final File guide = File(projectGuidePath(config));
    await guide.parent.create(recursive: true);
    await guide.writeAsString(projectGuideMarkdown(config));
    return guide;
  }

  static String projectGuideMarkdown(SetupConfig config) {
    final StringBuffer buffer = StringBuffer();
    final String mainPath = mainProjectPath(config);
    final String configPath = p.join(
      config.outputDir,
      'config',
      'setup_config.env',
    );

    buffer.writeln('# ${config.baseClassName} Setup Guide');
    buffer.writeln();
    buffer.writeln('Generated by Oracular for `${config.appName}`.');
    buffer.writeln();

    buffer.writeln('## 1. Open And Run');
    buffer.writeln();
    buffer.writeln('- Main project: `$mainPath`');
    buffer.writeln('- Run:');
    buffer.writeln();
    buffer.writeln('```bash');
    buffer.writeln('cd $mainPath');
    buffer.writeln(runCommand(config));
    buffer.writeln('```');
    buffer.writeln();

    buffer.writeln('## 2. Created Folders');
    buffer.writeln();
    for (final String item in createdProjectItems(config)) {
      buffer.writeln('- $item');
    }
    buffer.writeln();

    buffer.writeln('## 3. Oracular Commands');
    buffer.writeln();
    buffer.writeln('```bash');
    buffer.writeln('oracular guide');
    buffer.writeln('oracular open guide');
    buffer.writeln('oracular open app');
    buffer.writeln('oracular open root');
    if (config.useFirebase) {
      buffer.writeln('oracular open firebase');
      buffer.writeln('oracular open auth');
      buffer.writeln('oracular open firestore');
      buffer.writeln('oracular open storage');
      if (supportsWebHosting(config)) {
        buffer.writeln('oracular open hosting');
      }
    }
    if (config.createServer) {
      buffer.writeln('oracular open server');
      if (config.firebaseProjectId != null) {
        buffer.writeln('oracular open service-account');
        buffer.writeln('oracular open cloud-run');
      }
    }
    buffer.writeln('```');
    buffer.writeln();

    if (config.useFirebase && config.firebaseProjectId != null) {
      _writeFirebaseGuide(buffer, config);
    } else {
      buffer.writeln('## 4. Enable Firebase Later');
      buffer.writeln();
      buffer.writeln('- Edit `$configPath`.');
      buffer.writeln('- Set `USE_FIREBASE=yes`.');
      buffer.writeln('- Set `FIREBASE_PROJECT_ID=<your-project-id>`.');
      buffer.writeln('- Run `oracular deploy firebase-setup-full`.');
      buffer.writeln('- Open Firebase: <$_firebaseConsoleBase>');
      buffer.writeln();
    }

    if (config.createServer) {
      _writeServerGuide(buffer, config);
    }

    if (config.createModels && !config.template.isFlutterApp) {
      buffer.writeln('## Vendored Dependency Shims');
      buffer.writeln();
      buffer.writeln(
        '- Shims: `${p.join(config.outputDir, '.oracular_deps')}`',
      );
      buffer.writeln(
        '- Keep `.oracular_deps/` next to `${mainProjectName(config)}/`.',
      );
      buffer.writeln();
    }

    buffer.writeln('## Troubleshooting');
    buffer.writeln();
    buffer.writeln('- Check tools: `oracular check tools`');
    buffer.writeln('- Check Firebase tools: `oracular check firebase`');
    buffer.writeln(
      '- Regenerate Firebase config: `oracular deploy generate-configs`',
    );

    return buffer.toString();
  }

  static void _writeFirebaseGuide(StringBuffer buffer, SetupConfig config) {
    final String projectId = config.firebaseProjectId!;
    final bool isJaspr = config.template.isJasprApp;

    buffer.writeln('## 4. Firebase Setup');
    buffer.writeln();
    buffer.writeln(
      'Run the umbrella command to log in, configure the client, '
      'bootstrap Firestore + Storage, deploy rules, and (when web is '
      'supported) deploy the release + beta hosting sites:',
    );
    buffer.writeln();
    buffer.writeln('```bash');
    buffer.writeln('cd ${config.outputDir}');
    buffer.writeln('oracular deploy firebase-setup-full');
    buffer.writeln('```');
    buffer.writeln();
    buffer.writeln('### Manual console steps');
    buffer.writeln();
    buffer.writeln('1. Open Firebase project overview:');
    buffer.writeln('   <${firebaseOverviewUrl(projectId)}>');
    buffer.writeln('2. Click **Build > Authentication > Get started**.');
    buffer.writeln('   <${firebaseAuthenticationConsoleUrl(projectId)}>');
    buffer.writeln(
      '3. Click **Build > Firestore Database > Create database** '
      'if your app needs Firestore.',
    );
    buffer.writeln('   <${firebaseFirestoreConsoleUrl(projectId)}>');
    buffer.writeln(
      '4. Click **Build > Storage > Get started** if your app uploads files.',
    );
    buffer.writeln('   <${firebaseStorageConsoleUrl(projectId)}>');
    if (supportsWebHosting(config)) {
      buffer.writeln('5. Click **Build > Hosting** to inspect deploys.');
      buffer.writeln('   <${firebaseHostingConsoleUrl(projectId)}>');
    }
    buffer.writeln();
    buffer.writeln('### Independent re-runnable commands');
    buffer.writeln();
    buffer.writeln('```bash');
    buffer.writeln('# Auth + bootstrap');
    buffer.writeln('oracular deploy firestore-init      # default DB');
    buffer.writeln('oracular deploy storage-init        # default bucket');
    buffer.writeln('oracular deploy auth-providers      # email + Google');
    buffer.writeln('oracular check billing              # Spark vs Blaze');
    buffer.writeln();
    buffer.writeln('# Rules + content');
    buffer.writeln('oracular deploy firestore           # rules + indexes');
    buffer.writeln('oracular deploy storage             # rules');
    if (supportsWebHosting(config)) {
      buffer.writeln();
      buffer.writeln(
        '# Hosting (${isJaspr ? "Jaspr" : "Flutter web"})',
      );
      buffer.writeln(
        'oracular deploy hosting-init        # creates `<project>-beta` site',
      );
      buffer.writeln('oracular deploy hosting             # release channel');
      buffer.writeln('oracular deploy hosting-beta        # beta channel');
    }
    buffer.writeln('```');
    buffer.writeln();
    if (isJaspr) {
      final bool serverMode = config.jasprRenderMode.requiresCloudRun;
      final String publicDir = serverMode
          ? '${config.webPackageName}/build/jaspr/web/'
          : '${config.webPackageName}/build/jaspr/';
      buffer.writeln(
        '> Jaspr hosting builds use `jaspr build` — the orchestrator '
        'invokes it automatically. For mode `${config.jasprRenderMode.name}` '
        'the public dir is `$publicDir`.',
      );
      buffer.writeln();
    }
  }

  static void _writeServerGuide(StringBuffer buffer, SetupConfig config) {
    final String serverPath = p.join(
      config.outputDir,
      config.serverPackageName,
    );
    final String keyPath = p.join(serverPath, 'service-account.json');

    buffer.writeln('## Server Deployment');
    buffer.writeln();
    buffer.writeln('- Server project: `$serverPath`');
    buffer.writeln('- Service account key path: `$keyPath`');
    if (config.firebaseProjectId != null) {
      buffer.writeln('- Generate a service account key here:');
      buffer.writeln(
        '  <${firebaseServiceAccountUrl(config.firebaseProjectId!)}>',
      );
      buffer.writeln('- Cloud Run console:');
      buffer.writeln('  <${cloudRunConsoleUrl(config.firebaseProjectId!)}>');
    }
    buffer.writeln();
    buffer.writeln('### Deploy');
    buffer.writeln();
    buffer.writeln(
      'The generated `script_deploy.sh` is idempotent — every gcloud step '
      'gracefully handles already-existing resources, and every run '
      'applies the cleanup policy + caps Cloud Run revisions:',
    );
    buffer.writeln();
    buffer.writeln('```bash');
    buffer.writeln('cd $serverPath');
    buffer.writeln('./script_deploy.sh');
    buffer.writeln('```');
    buffer.writeln();
    buffer.writeln('### Cleanup tunables');
    buffer.writeln();
    buffer.writeln(
      '- Keep ${config.artifactKeepRecent} most-recent Artifact Registry '
      'image versions',
    );
    buffer.writeln(
      '- Delete versions older than ${config.artifactDeleteOlderDays} days',
    );
    buffer.writeln(
      '- Cap Cloud Run revisions at ${config.cloudRunKeepRevisions} (only '
      'non-traffic-serving older revisions are pruned)',
    );
    buffer.writeln();
    buffer.writeln('Re-apply just the cleanup pieces independently:');
    buffer.writeln();
    buffer.writeln('```bash');
    buffer.writeln('oracular deploy artifact-cleanup    # AR repo + policy');
    buffer.writeln(
      'oracular deploy cloudrun-prune      # delete old Cloud Run revisions',
    );
    buffer.writeln('```');
    buffer.writeln();
  }
}
