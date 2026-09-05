/// Available template types
enum TemplateType {
  // Flutter templates
  arcaneTemplate,
  arcaneBeamer,
  arcaneDock,
  arcaneCli,
  // Jaspr web templates
  arcaneJaspr,
  arcaneJasprDocs,
  arcaneJasprFlutterEmbed,
}

/// Extension for template metadata
extension TemplateTypeExtension on TemplateType {
  /// Get the display name for the template
  String get displayName {
    switch (this) {
      case TemplateType.arcaneTemplate:
        return 'Arcane Template (Basic)';
      case TemplateType.arcaneBeamer:
        return 'Arcane Beamer (With Navigation)';
      case TemplateType.arcaneDock:
        return 'Arcane Dock (Desktop System Tray)';
      case TemplateType.arcaneCli:
        return 'Arcane CLI (Command-Line App)';
      case TemplateType.arcaneJaspr:
        return 'Arcane Jaspr (Web App)';
      case TemplateType.arcaneJasprDocs:
        return 'Arcane Jaspr Docs (Static Documentation)';
      case TemplateType.arcaneJasprFlutterEmbed:
        return 'Arcane Jaspr + Flutter Embed (Web + Flutter App)';
    }
  }

  /// Get the directory name for the template (in sibling templates/ folder)
  String get directoryName {
    switch (this) {
      case TemplateType.arcaneTemplate:
        return 'arcane_app';
      case TemplateType.arcaneBeamer:
        return 'arcane_beamer_app';
      case TemplateType.arcaneDock:
        return 'arcane_dock_app';
      case TemplateType.arcaneCli:
        return 'arcane_cli_app';
      case TemplateType.arcaneJaspr:
        return 'arcane_jaspr_app';
      case TemplateType.arcaneJasprDocs:
        return 'arcane_jaspr_docs';
      case TemplateType.arcaneJasprFlutterEmbed:
        return 'arcane_jaspr_flutter_embed';
    }
  }

  /// Get the canonical package name used in the template
  String get canonicalPackageName {
    switch (this) {
      case TemplateType.arcaneTemplate:
        return 'arcane_app';
      case TemplateType.arcaneBeamer:
        return 'arcane_beamer_app';
      case TemplateType.arcaneDock:
        return 'arcane_dock_app';
      case TemplateType.arcaneCli:
        return 'arcane_cli_app';
      case TemplateType.arcaneJaspr:
        return 'arcane_jaspr_app';
      case TemplateType.arcaneJasprDocs:
        return 'arcane_jaspr_docs';
      case TemplateType.arcaneJasprFlutterEmbed:
        // The embed template ships two sibling packages — the Jaspr host
        // and the Flutter guest. The "canonical" name is the Jaspr host
        // (`arcane_jaspr_flutter_embed_web`); the guest is handled by
        // [SetupConfig.embeddedFlutterPackageName] separately.
        return 'arcane_jaspr_flutter_embed_web';
    }
  }

  /// Get a short description of the template
  String get description {
    switch (this) {
      case TemplateType.arcaneTemplate:
        return 'Pure Arcane UI with multi-platform support. No navigation framework.';
      case TemplateType.arcaneBeamer:
        return 'Arcane UI with Beamer declarative navigation for multi-screen apps.';
      case TemplateType.arcaneDock:
        return 'Desktop system tray/menu bar application (macOS, Linux, Windows only).';
      case TemplateType.arcaneCli:
        return 'Command-line interface application (Dart-only, not Flutter).';
      case TemplateType.arcaneJaspr:
        return 'Jaspr web application with Arcane design (Web-only, not Flutter).';
      case TemplateType.arcaneJasprDocs:
        return 'Static documentation site with Jaspr and Arcane design (Web-only).';
      case TemplateType.arcaneJasprFlutterEmbed:
        return 'Jaspr static site hosting a Flutter web app at /app (Web + Flutter).';
    }
  }

  /// Broad category shown by `oracular create templates`.
  String get categoryLabel {
    switch (this) {
      case TemplateType.arcaneTemplate:
      case TemplateType.arcaneBeamer:
        return 'Flutter app';
      case TemplateType.arcaneDock:
        return 'Flutter desktop';
      case TemplateType.arcaneCli:
        return 'Dart CLI';
      case TemplateType.arcaneJaspr:
      case TemplateType.arcaneJasprDocs:
      case TemplateType.arcaneJasprFlutterEmbed:
        return 'Jaspr web';
    }
  }

  /// Short operator-facing recommendation for choosing this template.
  String get recommendedUse {
    switch (this) {
      case TemplateType.arcaneTemplate:
        return 'First Arcane app, prototypes, and simple multi-platform tools.';
      case TemplateType.arcaneBeamer:
        return 'Apps with multiple screens, deep links, or URL-aware navigation.';
      case TemplateType.arcaneDock:
        return 'Desktop utilities that live in the system tray or menu bar.';
      case TemplateType.arcaneCli:
        return 'Terminal tools, automation commands, and publishable Dart CLIs.';
      case TemplateType.arcaneJaspr:
        return 'Arcane-styled web apps that do not need Flutter widgets.';
      case TemplateType.arcaneJasprDocs:
        return 'Static documentation sites backed by markdown content.';
      case TemplateType.arcaneJasprFlutterEmbed:
        return 'Static sites that host a Flutter web experience under /app.';
    }
  }

  /// Get supported platforms for this template
  List<String> get supportedPlatforms {
    switch (this) {
      case TemplateType.arcaneTemplate:
      case TemplateType.arcaneBeamer:
        return ['android', 'ios', 'web', 'linux', 'macos', 'windows'];
      case TemplateType.arcaneDock:
        return ['linux', 'macos', 'windows'];
      case TemplateType.arcaneCli:
      case TemplateType.arcaneJaspr:
      case TemplateType.arcaneJasprDocs:
      case TemplateType.arcaneJasprFlutterEmbed:
        return []; // Non-Flutter templates have no Flutter platforms
    }
  }

  /// Whether this template is a Flutter app
  bool get isFlutterApp {
    switch (this) {
      case TemplateType.arcaneTemplate:
      case TemplateType.arcaneBeamer:
      case TemplateType.arcaneDock:
        return true;
      case TemplateType.arcaneCli:
      case TemplateType.arcaneJaspr:
      case TemplateType.arcaneJasprDocs:
      case TemplateType.arcaneJasprFlutterEmbed:
        return false;
    }
  }

  /// Whether this template is a Dart-only CLI
  bool get isDartCli {
    return this == TemplateType.arcaneCli;
  }

  /// Whether this template is a Jaspr web app
  bool get isJasprApp {
    return this == TemplateType.arcaneJaspr ||
        this == TemplateType.arcaneJasprDocs ||
        this == TemplateType.arcaneJasprFlutterEmbed;
  }

  /// Whether this template is a static Jaspr docs site
  bool get isJasprDocs {
    return this == TemplateType.arcaneJasprDocs;
  }

  /// Whether this template is the Jaspr-host + Flutter-guest embed combo.
  bool get isJasprFlutterEmbed {
    return this == TemplateType.arcaneJasprFlutterEmbed;
  }

  /// Whether models package can be created with this template
  bool get supportsModels {
    return true; // All templates support models
  }

  /// Whether server app can be created with this template
  bool get supportsServer {
    return true; // All templates support server
  }

  /// Get the template number (1-based, matches the wizard list order)
  int get number {
    return index + 1;
  }

  /// Parse from string (number or name)
  static TemplateType? parse(String input) {
    final String lower = input.toLowerCase().trim();

    // Try parsing as number
    switch (lower) {
      case '1':
        return TemplateType.arcaneTemplate;
      case '2':
        return TemplateType.arcaneBeamer;
      case '3':
        return TemplateType.arcaneDock;
      case '4':
        return TemplateType.arcaneCli;
      case '5':
        return TemplateType.arcaneJaspr;
      case '6':
        return TemplateType.arcaneJasprDocs;
      case '7':
        return TemplateType.arcaneJasprFlutterEmbed;
    }

    // Try parsing as name
    for (final TemplateType template in TemplateType.values) {
      if (template.directoryName == lower ||
          template.name.toLowerCase() == lower) {
        return template;
      }
    }

    return null;
  }
}

/// Information about a template
class TemplateInfo {
  final TemplateType type;
  final String name;
  final String description;
  final List<String> platforms;
  final bool isFlutter;

  TemplateInfo({
    required this.type,
    required this.name,
    required this.description,
    required this.platforms,
    required this.isFlutter,
  });

  factory TemplateInfo.fromType(TemplateType type) {
    return TemplateInfo(
      type: type,
      name: type.displayName,
      description: type.description,
      platforms: type.supportedPlatforms,
      isFlutter: type.isFlutterApp,
    );
  }

  /// Get all available templates
  static List<TemplateInfo> get all {
    return TemplateType.values
        .map((TemplateType t) => TemplateInfo.fromType(t))
        .toList();
  }
}
