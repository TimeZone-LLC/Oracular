# Arcane Jaspr Docs

Static documentation site for a Flutter-first Arcane Jaspr project.

## Development

```bash
dart pub get
jaspr serve
```

## Build

```bash
jaspr build
```

## Documentation Rules

- Teach `package:arcane_jaspr/arcane_jaspr.dart` first
- Keep `package:arcane_jaspr/html.dart` for advanced HTML wrapper examples only
- Keep `package:arcane_jaspr/web.dart` for raw Jaspr escape hatches only
- Prefer Flutter-shaped examples with `Widget build(BuildContext context)` and no explicit type arguments in normal usage
- `arcane_jaspr_shadcn` and `arcane_lexicon` resolve via git, and a `dependency_overrides` entry pins `arcane_jaspr` to the same git monorepo, so `dart pub get` works directly when validating the template locally
