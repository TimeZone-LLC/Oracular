## x.x.x

### Fixed

- Jaspr templates (`arcane_jaspr_app`, `arcane_jaspr_docs`,
  `arcane_jaspr_flutter_embed_web`) now pin `arcane_jaspr` to the same git
  snapshot as the git-referenced `arcane_jaspr_shadcn` renderer via a
  `dependency_overrides` entry. Mixing the pub.dev `arcane_jaspr` release
  with monorepo-HEAD renderers broke `jaspr build` in fresh scaffolds with
  "Unable to find modules" errors whenever the monorepo was ahead of the
  published release. Remove the override once the renderer packages are
  published to pub.dev.
- `setup_install_offer_test` and `setup_script_smoke_test` read the release
  version from `lib/version.dart` instead of a hardcoded constant, so
  version bumps no longer break the generator's version cross-check.
- Tool probes (`commandExists` / `getCommandVersion`) now run with a 15s
  timeout and kill the probed process on expiry, so a wedged external CLI
  (e.g. a hanging `flutterfire --version`) can no longer hang
  `oracular check tools` or the wizard forever; the tool is reported with
  an unknown version instead.
- Setup guidance for `.oracular_deps/` now describes the vendored pure-Dart
  shim packages and only appears when shims are actually vendored (models
  enabled on a non-Flutter template) instead of on every Jaspr docs project.
- `templates/pub_get_all.sh` no longer skips `arcane_jaspr_docs` behind the
  removed legacy `.oracular_deps` vendoring check and now covers both
  `arcane_jaspr_flutter_embed` packages.

### Changed

- Jaspr templates raise the `arcane_jaspr` constraint floor to `^3.4.0`,
  matching the release published to pub.dev on 2026-08-18.

## 3.5.2 - 2026-05-15

- Updated the runtime version banner to match the published package version.

## 3.5.1 - 2026-05-15

- Fixed generated Jaspr starter route wrappers for the current Jaspr component
  API.
- Fixed the Jaspr Flutter embed template export surface so generated projects
  no longer reference missing screen files.
- Replaced placeholder starter TODO actions with harmless starter behavior.
- Moved live Firebase deployment tests behind the documented
  `live-deployment` opt-in profile.
- Added reusable live deployment test helpers and Firebase app cleanup so
  disposable test apps are removed after creation checks.
- Split low-risk template-copy and setup-config helper logic into smaller
  internal services.

## 3.5.0

### Added — Jaspr render modes (CSR / SSG / SSR / Hybrid / Embed)

Jaspr templates can now be scaffolded in five distinct render modes,
each producing a different build pipeline, hosting layout, and deploy
target. Mode is picked in the wizard or via `oracular create
--render-mode <mode>`, persisted to `config/setup_config.env`, and
threaded through every downstream service so `jaspr.yaml`, the
generated `firebase.json` rewrites, the docs page, and the Cloud Run
deploy all stay in sync.

| Mode | Build output | Hosting | Cloud Run | Use case |
|---|---|---|---|---|
| `csr` | `build/jaspr/` (client SPA) | Static | — | Fastest dev loop, no SEO. |
| `ssg` | `build/jaspr/` (prerendered HTML) | Static | — | SEO-friendly, no runtime cost. |
| `ssr` | `build/jaspr/` (Dart binary + client) | `/** -> run:<svc>` | yes | Server-rendered at request time. |
| `hybrid` | `build/jaspr/web/` (static + Dart binary) | per-prefix `run:<svc>` rewrites | yes | Mix of static + SSR routes. |
| `embed` | Jaspr host + Flutter web guest at `/app/` | Static | — | Jaspr docs/marketing site that hosts a Flutter app. |

New `JasprRenderMode` enum (`oracular/lib/models/setup_config.dart`)
with `displayName`, `description`, `jasprYamlMode`, `requiresCloudRun`,
`needsServerEntrypoint`, and a permissive `parse()` that accepts CLI
aliases (`client` → CSR, `static` → SSG, `server` → SSR, …).

### Added — `arcane_jaspr_flutter_embed` template

Brand-new dual-package template
(`templates/arcane_jaspr_flutter_embed/`) that scaffolds two sibling
packages in a single `oracular create` run:

- `<appName>_web/` — Jaspr static host (the public-facing site,
  marketing pages, docs, etc.)
- `<appName>_app/` — Flutter web guest, mounted at
  `/app/` inside the Jaspr host's `web/` output.

Wired by `TemplateCopier._copyJasprFlutterEmbedTemplate`
(`oracular/lib/services/template_copier.dart:159-260`) which copies
both sub-packages, processes placeholders independently, and emits the
IntelliJ run configs for the host. Defaults to
`JasprRenderMode.embed`.

The embed build (`oracular build flutter-embed` or `oracular build
jaspr-site` in embed mode) runs `flutter build web --release
--base-href=/app/` in the guest, copies the bundle into the host's
`web/app/`, and uncomments the `ORACULAR_FLUTTER_BOOTSTRAP_BEGIN/END`
script block in `web/index.html` so the bundle loads at runtime.

### Added — `oracular build` command tree

New top-level command for producing artifacts without touching deploy
state. Distinct from `oracular deploy`: `build` never runs
`firebase deploy`, never pushes images, and never talks to gcloud.
Always safe to run from CI.

```bash
oracular build everything                    # every artifact for this project
oracular build flutter-app                   # every Flutter platform
oracular build flutter-app --platform web    # one platform only
oracular build jaspr-site                    # render-mode aware jaspr build
oracular build jaspr-image                   # docker build (SSR/hybrid)
oracular build flutter-embed                 # Flutter web guest + Jaspr host
oracular build cli-binary                    # dart compile exe (arcane_cli_app)
```

Backed by a new `BuildOrchestrator` service
(`oracular/lib/services/build_orchestrator.dart`) that is the single
source of truth for "what does building this project mean?". Every
build entry point (`oracular build …`, `oracular deploy jaspr-server`,
`oracular deploy arcane-server`, integration tests) routes through
this service, so `flutter build`/`jaspr build`/`docker build`
invocations are identical regardless of which command triggered them.

`BuildOrchestrator.buildJasprServerImage()` auto-tags the image with
both `:latest` and (when git is available) `:<short-sha>` so AR
cleanup policies have a traceable revision history.

### Added — `oracular deploy jaspr-server` (SSR / hybrid Jaspr binary)

Ships the Jaspr `main.server.dart` entrypoint to Cloud Run as a
sibling Dart binary to `arcane_server`. The two can coexist in the
same project: `arcane_server` lives at `<appName>-server`, Jaspr's
binary at `<appName>-web` (configurable via
`SetupConfig.effectiveJasprServerServiceName`).

```bash
oracular deploy jaspr-server     # build + push + Cloud Run deploy
```

Implemented by the new `JasprServerDeployer`
(`oracular/lib/services/jaspr_server_deployer.dart`). End-to-end
flow: `CloudRunPreflight` (active gcloud account / APIs / AR repo)
→ `BuildOrchestrator.buildJasprServerImage()` → `docker push :latest`
+ optional `:<sha>` → `gcloud run deploy` → `gcloud run services
describe` for the live URL.

`oracular deploy all` now runs the Jaspr server deploy **before** the
`arcane_server` step so the firebase.json rewrites
(`/** → run:<jaspr-service>` in SSR; per-prefix rewrites in hybrid)
point at a live URL by the time hosting publishes. Both steps are
independent — a partial run still tells the user which half shipped.

### Added — `CloudRunPreflight` shared preflight service

Pulled the three Cloud Run prerequisites that were previously private
to `ServerSetup` into a standalone service
(`oracular/lib/services/cloud_run_preflight.dart`) so the Jaspr
deployer can reuse them without copy-paste:

1. **Active gcloud account sanity** — detects the "wrong service
   account active" foot-gun (active SA belongs to a different project
   than `firebaseProjectId`) and prints the exact
   `gcloud config set account …` command to copy, picking the best
   candidate from `gcloud auth list`.
2. **Required GCP APIs enabled** — `artifactregistry.googleapis.com`
   and `run.googleapis.com`.
3. **Artifact Registry repository exists** — describes first, creates
   on `NOT_FOUND`, treats 409 / `already exists` as success.

### Added — render-mode-aware `firebase.json` rewrites

`ConfigGenerator.generateFirebaseJson`
(`oracular/lib/services/config_generator.dart`) now emits rewrites
matched to the chosen render mode:

- **CSR** — `{ source: "**", destination: "/index.html" }` (classic SPA).
- **SSG** — `{ source: "**", destination: "/index.html" }`, with
  prerendered HTML files served before the SPA fallback fires.
- **SSR** — `{ source: "**", run: { serviceId: "<svc>", region:
  "us-central1" } }`. Every request goes through Cloud Run.
- **Hybrid** — one rewrite per dynamic prefix
  (`--hybrid-dynamic-prefix /api,/blog/**`), plus SPA fallback for the
  static routes. Configurable via `oracular deploy generate-configs
  --hybrid-dynamic-prefix …`.
- **Embed** — SPA fallback like CSR, with the Flutter bundle served
  from `/app/` as static assets.

Hosting `public:` directory also auto-flips between
`build/jaspr/` (CSR/SSG/Embed) and `build/jaspr/web/` (SSR/Hybrid) to
match the Jaspr CLI's per-mode output layout.

### Added — service-account auto-discovery in the wizard

`FirebaseSetupPrompts.findExistingServiceAccountKey`
(`oracular/lib/utils/firebase_setup_prompts.dart`) walks the user's
workspace looking for any pre-existing `*service-account*.json`,
parses its `project_id` and `client_email`, and surfaces the result as
a `DiscoveredServiceAccount`.

The interactive wizard (and `oracular create`) consume this to:

- Pre-fill the "Firebase project ID" prompt with the discovered
  `project_id` (one keystroke to accept).
- Offer to reuse the discovered key file instead of asking the user to
  drag a fresh one into `config/keys/`.
- Surface the discovered identity (`Found service account at <path>
  (project: <id>)`) up front so the user knows which credentials the
  wizard is about to use.

Service-account key is now requested whenever Firebase is enabled —
not only when a server package is created. The key file drops into
`<outputDir>/config/keys/` when no server package exists, where
`FirebaseService.authEnvironment` finds it automatically.

### Added — `Deploy All` project-level IntelliJ run config

The 3.4.0 IntelliJ run-config generator only emitted Serve / Build /
Killall in each Jaspr package. 3.5.0 adds a project-level
**Deploy All** run config (`oracular deploy all`) at the project root
(where `config/setup_config.env` lives), wired by
`IntellijRunConfigGenerator.generateDeploy`
(`oracular/lib/services/intellij_run_config_generator.dart:157-191`).

Both the scaffold path (`TemplateCopier`) and `oracular update runs`
now emit it unconditionally — it's template-agnostic, so even
Flutter-only or server-only projects benefit. The `update runs`
handler renders the count as `(<N> project-level Deploy + <M> Jaspr
across <P> packages)` so the user can tell what was added.

### Added — render-mode build/deploy docs page (`docs/07b-build-and-deploy.md`)

`DocsGenerator` (`oracular/lib/services/docs_generator.dart`) emits a
dedicated build-and-deploy page for every Jaspr project that documents:

- The mode in use (CSR/SSG/SSR/Hybrid/Embed) and what it means.
- Exact `oracular build …` and `oracular deploy …` commands for that
  mode.
- Cloud Run service name(s), region, and how to override.
- Flutter-embed mount point (when applicable).

Standalone page (not buried inside `06-deployment.md`) so render-mode
operators have a single bookmarkable URL.

### Added — Templates release pipeline (downloadable ZIPs)

Every push to `master` whose head-commit message contains the literal
substring `[Build]` (case-sensitive, brackets included) now triggers a
new `.github/workflows/templates-release.yml` workflow that packages
each template into a self-contained ZIP and publishes them as a single
GitHub Release. Commits without `[Build]` cost zero CI minutes — the
gate short-circuits before any setup work.

Each ZIP is **structurally identical** to what `oracular create -y -t
<template>` produces today, but extractable on a machine that has only
the Dart SDK — no `oracular` install required. The ZIP filenames are
version-aligned with `oracular/pubspec.yaml:3` (e.g.
`arcane_app-v3.5.0.zip`), so the templates and the CLI that scaffolds
them are versioned in lockstep.

| Asset | Contents |
|---|---|
| `arcane_app-vX.Y.Z.zip` | Template source + `setup.dart` + `README.md` + `SETUP_USAGE.md` + `LICENSE` + `VERSION` |
| `arcane_beamer_app-vX.Y.Z.zip` | Same shape for Beamer template |
| `arcane_dock_app-vX.Y.Z.zip` | Same shape for desktop tray template |
| `arcane_cli_app-vX.Y.Z.zip` | Same shape for Dart CLI template |
| `arcane_jaspr_app-vX.Y.Z.zip` | Same shape, includes vendored `_vendor/` shims |
| `arcane_jaspr_docs-vX.Y.Z.zip` | Same shape, includes vendored `_vendor/` shims |
| `arcane_jaspr_flutter_embed-vX.Y.Z.zip` | Dual-package layout (`_web/` + `_app/`) in one ZIP |
| `arcane_models-vX.Y.Z.zip` | Same shape for models package |
| `arcane_server-vX.Y.Z.zip` | Same shape for server package |
| `all-templates-vX.Y.Z.zip` | Bundle of all 9 above |

Per-ZIP `setup.dart` replicates the wizard non-interactively:

```bash
unzip arcane_jaspr_app-v3.5.0.zip
cd arcane_jaspr_app-v3.5.0
dart run setup.dart \
  --name my_site --org com.example \
  --render-mode ssr --with-server --with-firebase
```

After scaffolding, the script offers to
`dart pub global activate oracular <matching-version>` so the user can
opt into the full CLI flow going forward. The offer is suppressed in
non-TTY environments (CI) and can be forced or skipped via
`--install-oracular` / `--no-install-oracular`. Project scaffolding is
always atomic — the optional install never failure-cascades.

The packager/generator/setup tooling lives in a new top-level
`scripts/` directory (`scripts/generate_setup_script.dart`,
`scripts/package_template.dart`,
`scripts/setup_template_template.dart`). The setup script is
mechanically derived from the same `PlaceholderReplacer` /
`TemplateCopier` services the CLI uses, with a parity unit test
(`oracular/test/unit/setup_script_parity_test.dart` — 17 cases) that
fails CI if the two ever diverge, plus an end-to-end smoke test
(`oracular/test/integration/setup_script_smoke_test.dart` — 14
cases: 10 per-template smoke + 2 regression cases for the
`--with-models` no-bundled-models edge + 2 regression cases for the
`--output-dir` overlap refusal) that extracts every published
ZIP and runs `setup.dart` against it, and a state-machine test
(`oracular/test/integration/setup_install_offer_test.dart` — 6 cases)
covering the `--install-oracular` / `--no-install-oracular` / TTY
prompt / non-TTY skip permutations. All 37 tests run on every
workflow execution before any ZIP is published.

The workflow is opt-in by design: commit message must contain `[Build]`
to fire it, ZIPs are deterministic (running the packager twice with
identical inputs yields byte-identical archives), packaging runs in a
9-way matrix to minimize wall time, and the Release tag uses a
`templates-v<X.Y.Z>+<UTC-stamp>Z` format so every build is uniquely
addressable while the per-asset filename remains stable for
`releases/latest/download/...` consumers.

### Fixed — `setup.dart --output-dir` overlap no longer infinite-recurses

When `setup.dart` was invoked with an `--output-dir` that overlapped
the ZIP extraction directory (equal to it, or nested inside it),
`stageTemplate` would list the ZIP root, see the newly-created output
directory as one of its children, and `_copyDirectoryRaw` would
infinite-recurse copying the partially-staged output back into itself
until the OS aborted with a path-too-long error. Critically, the
previous safety guard at `_run` only checked the `==` case using
`pNormalize(absolute.path)`, which silently passed on macOS because
`Directory.current` returns the symlink-resolved `/private/tmp/...`
form while user-supplied paths stay as `/tmp/...`.

Now both `_run` (`scripts/setup_template_template.dart:1435-1497`) and
`stageTemplate` (`scripts/setup_template_template.dart:962-1001`)
canonicalise paths via `resolveSymbolicLinksSync()` before comparing,
and refuse three cases up-front:

1. `outputDir == zipRoot` (e.g. `--output-dir .` from inside the ZIP)
2. `outputDir` is **inside** `zipRoot` (e.g. `--output-dir ./myapp`)
3. `zipRoot` inside `outputDir` (warned but not refused — non-destructive)

For defense-in-depth, `stageTemplate` also re-checks each source entry
against the target's canonical path and skips any entry that IS the
target or lives below it.

Regression tests in
`oracular/test/integration/setup_script_smoke_test.dart:191-202`
(via the new `_testOutputDirOverlapRefused()` factory at lines
539-640) cover both refusal cases with a 30-second timeout that
would catch any future regression that reintroduces the recursion.

### Fixed — `setup.dart --with-models` no longer breaks `pub get` on per-template ZIPs

When `setup.dart` is invoked with `--with-models` against a
per-template ZIP (e.g. `arcane_jaspr_app-v3.5.0.zip`, which by design
does **not** carry the `arcane_models/` template), the script
previously wrote an *active* `path: ../<name>_models` line into
`pubspec.yaml` even though no such sibling package would exist on
disk. `dart pub get` would then fail with "Couldn't find
`<name>_models` at `../<name>_models`."

Now the script tracks whether the models template was actually staged
(`scripts/setup_template_template.dart:1502-1530`). If it was, the
active dep is written as before; if not, a brand-new
`addCommentedModelsDependency` helper writes a *commented* hint plus
a `logWarn` pointing the user at `arcane_models-vX.Y.Z.zip` from the
same Release. Same treatment is applied to the embed-guest pubspec.
Net effect: `pub get` is green out of the box on the produced
project, and the user has a copy-paste hint to enable models later
without editing the pubspec from scratch.

Regression tests in
`oracular/test/integration/setup_script_smoke_test.dart:171-184`
(via the new `_testCommentedModelsHint()` factory at lines 349-518)
cover both the `arcane_jaspr_app --render-mode ssr --with-models` and
`arcane_jaspr_flutter_embed --render-mode embed --with-models` paths.

### Fixed — `arcane_server` Dockerfile missing Linux desktop toolchain

`ServerSetup.generateDockerfile`
(`oracular/lib/services/server_setup.dart`) now installs `clang`,
`cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`, `liblzma-dev`,
and `libstdc++-12-dev` in the build stage. Without these,
`flutter build linux --release` fails with `CMake is required for
Linux development.` deep inside the docker build with no actionable
log. The generated Dockerfile also documents the runtime stage's
display-less invocation, adds `git config --global --add safe.directory
/flutter` so Flutter's bootstrap doesn't error inside the container,
and lays out the build context so `path: ../<models>` resolves cleanly
inside `/app`.

### Fixed — `build_runner` runs only in packages that depend on it

`DependencyManager.runAllBuildRunners`
(`oracular/lib/services/dependency_manager.dart:163-215`) now probes
each candidate package's `pubspec.yaml` for a `build_runner:` entry
before invoking `dart run build_runner build`. Previously the CLI
template (which ships without `build_runner`) would error with
`Could not find package 'build_runner' or file 'build_runner'` and
stall the non-interactive wizard waiting for retry/skip/abort input.

### Changed — `arcane_server` forces `arcane_models` on

`arcane_server`'s pubspec has a hard `path: ../<name>_models`
dependency, so picking server without models always failed
`flutter pub get`. Both the CLI (`handleCreate`) and the wizard now
auto-enable `createModels = true` whenever `createServer` is true,
with a one-line `warn(…)` so the user sees what changed.

### Implementation

| File | Change |
|---|---|
| `oracular/lib/models/setup_config.dart` | New `JasprRenderMode` enum + extension; `SetupConfig.jasprRenderMode`, `hasJasprServer`, `effectiveJasprServerServiceName`, `embeddedFlutterPackageName`, `embeddedFlutterMount` fields with env-file round-trip. |
| `oracular/lib/models/template_info.dart` | New `arcaneJasprFlutterEmbed` template value; `isJasprFlutterEmbed` predicate; canonical name routes to `<appName>_web`. |
| `oracular/lib/services/build_orchestrator.dart` | New service. Per-mode `jaspr build` dispatch, embed flow (`flutter build web` → host copy → bootstrap uncomment), docker build with git-SHA tagging, dart-CLI compile. |
| `oracular/lib/services/jaspr_server_deployer.dart` | New service. End-to-end build/push/deploy for Jaspr SSR/hybrid binary. |
| `oracular/lib/services/cloud_run_preflight.dart` | New service. Shared preflight extracted from `ServerSetup`. |
| `oracular/lib/services/config_generator.dart` | Render-mode-aware hosting rewrites and `public:` path; `--hybrid-dynamic-prefix` CLI hook. |
| `oracular/lib/services/template_copier.dart` | Dual-package embed copier; per-mode `jaspr.yaml` patching; deploy-all run-config emission. |
| `oracular/lib/services/docs_generator.dart` | New `07b-build-and-deploy.md` page; per-mode sections inside `06-deployment.md`. |
| `oracular/lib/services/server_setup.dart` | Dockerfile linux-desktop toolchain; build-context fix; routes Cloud Run deploys through `CloudRunPreflight`. |
| `oracular/lib/services/interactive_wizard.dart` | Render-mode prompt (`_chooseJasprRenderMode`); SA discovery → project-ID default; server→models auto-enable. |
| `oracular/lib/services/intellij_run_config_generator.dart` | Project-level `Deploy_All.run.xml` generator. |
| `oracular/lib/services/dependency_manager.dart` | `_pubspecDependsOnBuildRunner` gate before running build_runner. |
| `oracular/lib/cli/commands.dart` | New `build` command tree (everything / flutter-app / jaspr-site / jaspr-image / flutter-embed / cli-binary); `deploy jaspr-server` subcommand; `--render-mode` on `create`. |
| `oracular/lib/cli/handlers/build_handlers.dart` | New. Per-subcommand wrappers around `BuildOrchestrator`. |
| `oracular/lib/cli/handlers/update_handlers.dart` | Emit project-level Deploy All; auto-discovery of Jaspr packages by `pubspec.yaml`. |
| `oracular/lib/cli/handlers/deploy_handlers.dart` | `handleDeployJasprServer`; updated `handleDeployAll` to chain Jaspr+arcane server deploys. |
| `oracular/lib/cli/handlers/create_handlers.dart` | `--render-mode` flag; server→models auto-enable; pre-discovery of SA. |
| `oracular/lib/utils/firebase_setup_prompts.dart` | New `DiscoveredServiceAccount` + `findExistingServiceAccountKey` walker. |
| `templates/arcane_jaspr_flutter_embed/` | New template (host `_web` + guest `_app`). |
| `templates/arcane_jaspr_app/` | Added `Dockerfile.jaspr`, `main.server.dart`, `routes/dynamic_routes.dart`, `routes/static_routes.dart`, `.dockerignore`. |
| `scripts/setup_template_template.dart` | New. Canonical source of the standalone `setup.dart` shipped inside every template ZIP. Mirrors `PlaceholderReplacer` + `TemplateCopier` semantics so the ZIP flow stays in lockstep with the CLI flow. Includes the optional oracular install/upgrade offer. |
| `scripts/generate_setup_script.dart` | New. Substitutes `__GENERATED:*__` markers in the skeleton with build-time metadata (version, build-id, default template) and emits `dist/setup.dart`. Fails fast on `oracular/pubspec.yaml` ↔ `oracular/lib/version.dart` mismatch. |
| `scripts/package_template.dart` | New. Stages a template directory, drops in the generated `setup.dart`, `README.md`, `SETUP_USAGE.md`, `LICENSE`, and `VERSION`, then emits a deterministic `<template>-v<X.Y.Z>.zip`. Handles the dual-package layout for `arcane_jaspr_flutter_embed` and the vendored `_vendor/` shims for Jaspr templates. |
| `scripts/pubspec.yaml` | New. Isolates the packaging toolchain's deps (`archive`, `path`) from the CLI's `pubspec.yaml`. |
| `.github/workflows/templates-release.yml` | New. `[Build]`-gated workflow: `detect` → `validate-setup-script` (runs the 33 parity/smoke/install-offer tests) → `generate-setup-script` → `package-templates` (9-way matrix) → `bundle` → `release`. Includes a `workflow_dispatch` self-test path that can run the entire pipeline without a real commit. |
| `templates/RELEASE_README_TEMPLATE.md` | New. README emitted into the root of every per-template ZIP. Explains the ZIP layout, the `setup.dart` flags, and how the ZIP flow relates to the `oracular create` flow. |
| `templates/SETUP_USAGE.md` | New. Detailed `setup.dart --help` companion: every flag, every permutation, every CI snippet. Shipped inside every ZIP. |
| `oracular/test/unit/setup_script_parity_test.dart` | New. 17 cases asserting every `PlaceholderReplacer` rule produces the same output when invoked from the standalone `setup.dart` as it does from `oracular create`. |
| `oracular/test/integration/setup_script_smoke_test.dart` | New. 14 cases: 10 build a ZIP for each template type, extract it to a tmpdir, run `setup.dart` against it, and assert the resulting project matches what `oracular create` would have produced; 2 regression cases assert that `setup.dart --with-models` on a per-template ZIP (no models bundled) injects a *commented* hint instead of an active `path:` dep that would crash `pub get`; 2 regression cases assert that `--output-dir` overlapping the ZIP root is refused with a clear error (instead of infinite-recursing through `_copyDirectoryRaw`). Caught four real bugs during development: `PlaceholderReplacer` getter exposure, empty `.oracular_deps/` leak, the `--with-models` no-models regression, and the symlink-aware `--output-dir` overlap refusal. |
| `oracular/test/integration/setup_install_offer_test.dart` | New. 6 cases covering the install/upgrade offer state machine: `--install-oracular` forces install, `--no-install-oracular` skips, `--yes` implies install, no flag + TTY prompts, no flag + non-TTY skips, already-installed at matching version short-circuits. |
| `README.md` | New "Releases & Templates" section between Installation and Quick Start. |
| `oracular/README.md` | New "Without installing the CLI" subsection. |
| `oracular/CHANGELOG.md` | This entry. |

### Tests

- New `oracular/test/unit/jaspr_server_deployer_test.dart` covering
  the full deploy success path, every short-circuit (no project ID,
  preflight failure, build failure, push failure, deploy failure), and
  URL fallback when `gcloud run services describe` fails.
- New `oracular/test/integration/per_mode_smoke_test.dart` asserting
  that `BuildOrchestrator` runs the **exact** set of `BuildStepKind`s
  expected for each render mode — CSR / SSG run jaspr-site only, SSR /
  hybrid add the Cloud Run image step, embed runs the Flutter guest
  build first.
- Expanded `config_generator_test.dart`, `setup_config_test.dart`,
  `setup_guidance_test.dart`, `template_info_test.dart`, and
  `server_setup_test.dart` to cover the new render-mode permutations
  and the env-file round-trip.
- 37 new tests for the templates release pipeline across three
  files — `setup_script_parity_test.dart` (17 cases),
  `setup_script_smoke_test.dart` (14 cases: 10 per-template smoke + 2
  regression cases for `--with-models` on a single-template ZIP + 2
  regression cases for `--output-dir` overlap refusal),
  and `setup_install_offer_test.dart` (6 cases). All gated through
  the workflow's `validate-setup-script` job so a regression in the
  standalone setup script fails CI before any ZIP gets published.

### Migration

For projects scaffolded by Oracular < 3.5.0:

- **Render mode defaults to CSR** for existing Jaspr projects (matches
  the previous behavior). To opt into another mode, edit
  `JASPR_RENDER_MODE=` in `config/setup_config.env` and re-run
  `oracular rebuild` or just `oracular deploy generate-configs` to
  regenerate `firebase.json` + `jaspr.yaml`.
- **`oracular update runs`** picks up the new project-level
  `Deploy_All.run.xml` automatically — no flag required.
- **`arcane_server` projects:** if you scaffolded a server without
  models on an older version, `flutter pub get` was likely failing.
  Add `arcane_models` to the project (or re-run the wizard) and the
  hard dependency resolves.

---

## 3.4.0

### Added — IntelliJ run configurations for Jaspr packages (Serve, Build, Killall)

Every newly-scaffolded Jaspr package
(`arcane_jaspr_app`, `arcane_jaspr_docs`, and the per-app `*_web/`
target) now ships with three IntelliJ / Android Studio run
configurations under `.idea/runConfigurations/`:

| File | What it runs | Notes |
|---|---|---|
| `Serve.run.xml` | `jaspr serve --port <port>` | Default `8080`. Editing the run config's "Script Text" is the easiest way to change the dev port — no env-var dance. |
| `Build.run.xml` | `jaspr build` | Port-agnostic. Builds the release web bundle into `build/jaspr/`. |
| `Killall_<port>.run.xml` | `lsof -ti:$PORT \| xargs kill -9` | Kills anything listening on the chosen port. Filename encodes the port so the IDE dropdown reads "Killall :8080". A power-user can pass an override port in the run config's "Script Options" without regenerating. |

All three are emitted as **Shell Script** configurations
(`ShConfigurationType`), which is a built-in plugin in every modern
JetBrains IDE — no extra plugin installs required. The XML matches the
on-disk format IntelliJ writes itself when you create a shell run
config via the UI, so a round-trip through the IDE doesn't produce a
phantom git diff.

### Added — `oracular update runs` for retroactive install

Existing projects scaffolded by older Oracular versions can pull the
run configs in without any other changes via the new top-level
command:

```bash
oracular update runs                # default port 8080, all Jaspr packages
oracular update runs --port 3000    # custom port baked into Killall + Serve
oracular update runs --no-overwrite # keep user-edited run configs
oracular update runs --dir ./my_jaspr_app   # operate on a specific dir
```

`oracular update runs --port` also auto-prunes stale `Killall_NNNN.run.xml`
files from previous ports so the IDE dropdown stays clean.

> **Note:** The `--dir` flag is intentionally hyphen-free. `darted_cli` (our
> CLI parser) drops args whose names contain hyphens, so the canonical
> name for the project-root override is `--dir` (or the `-d` shortcut).
> The handler also accepts `--output-dir`/`--outputdir` aliases for
> compatibility, but those rely on `darted_cli` accepting them — which
> may or may not work depending on the parser version.

### Implementation

| File | Change |
|---|---|
| `oracular/lib/services/intellij_run_config_generator.dart:1-215` | New service with `generate({packageDir, port, overwrite})` and `pruneStaleKillallConfigs({packageDir, currentPort})`. Pure-string XML (no extra deps), proper attribute escaping (`&`/`<`/`>`/`"`/`'`), `&#10;` for embedded newlines so multi-line shell scripts survive IntelliJ's attribute-value handling. |
| `oracular/lib/services/template_copier.dart:128-135` | Wires `IntellijRunConfigGenerator.generate()` into the scaffolding pipeline whenever the template's `isJasprApp` is true. Idempotent — re-running the wizard always emits fresh configs. |
| `oracular/lib/cli/handlers/update_handlers.dart:1-160` | New `handleUpdateRuns` handler. Auto-discovers Jaspr packages by walking the project root for `pubspec.yaml` files that depend on `jaspr` or have a sibling `web/` directory. |
| `oracular/lib/cli/commands.dart:11,67-104,160-195` | Registers `oracular update` as a top-level command with `runs` subcommand, `--port`, `--target`, `--no-overwrite` flags, and full `--help` integration. |
| `oracular/test/unit/intellij_run_config_generator_test.dart:1-385` | **13 new tests** covering: filename + content of all three configs, port baking in Serve/Killall, port-agnostic Build, XML well-formedness via state-machine parser (handles attribute quotes + self-closing `<envs />`), `overwrite=false` preserves user edits, `pruneStaleKillallConfigs` removes only matching stale files. |

### Validation

- `dart analyze lib/` — clean (no new issues)
- `dart test test/unit/intellij_run_config_generator_test.dart` — **13/13 passed**
- `dart test test/unit/` — **326/326 passed** (313 → 326, zero regressions)

### Migration

For existing Oracular-scaffolded projects (e.g. `rhe-budget`):

```bash
cd /path/to/your/project
oracular update runs
```

For new projects scaffolded with `oracular` v3.4.0+, the run configs
are emitted automatically — no extra step.

---

## 3.3.9

### Added — `oracular deploy all` now ships the SSR / hydration server too

Previously `oracular deploy all` only invoked
`FirebaseService.deployAll()` (Firestore rules + Storage rules + web
build + hosting release deploy). Anyone using the arcane_jaspr SSR
template or the standalone arcane_server companion service had to
remember to run `script_deploy.sh` by hand afterwards — easy to miss,
and the resulting site had a stale backend serving the new frontend.

**Fix:** `handleDeployAll()`
(`oracular/lib/cli/handlers/deploy_handlers.dart:181-258`) now also
runs the new `ServerSetup.deployToCloudRun()` whenever
`config.createServer` is true. The order is:

1. **Firebase**: Firestore rules + Storage rules + web build + hosting.
2. **Server**: optional models snapshot → `gcloud auth configure-docker`
   → `docker build --platform linux/amd64` → `docker push` →
   `gcloud run deploy` → `gcloud run services describe` for the live URL.

Each phase is independent — a partial run still tells the user which
half shipped and which failed, and Cloud Run failures don't roll back
already-deployed Firebase rules. The deploy summary now lists the
service URL alongside the hosting URL.

### Added — `ServerSetup.deployToCloudRun()`

The Dart-side equivalent of the auto-generated `script_deploy.sh`,
exposed at `oracular/lib/services/server_setup.dart:444-606`. Returns
`String?` — the live Cloud Run URL on success (queried via
`gcloud run services describe`, since URLs embed a per-project hash
that's not predictable from project-id alone), `null` on any failure.

Each step uses `ProcessRunner.runWithRetry` so transient network /
docker errors get the same retry semantics as everything else in
Oracular. Early-exits cleanly when:
- `createServer` is false (no work to do).
- `firebaseProjectId` is missing (can't form the AR repository path).
- `<outputDir>/<server-package>/` doesn't exist (server was never
  scaffolded — directs the user to `oracular deploy server-setup`).

### Tests

- `test/unit/server_setup_test.dart:237-509` — **11 new tests** covering
  the success path (orders auth → build → push → deploy → describe),
  early-exits (no project ID, no server dir, server disabled), every
  short-circuit (auth/build/push/deploy fail), URL fallback when
  `describe` fails, and models snapshot copy success/failure.
- Total: **313/313 unit tests passed** (302 → 313, +11 new).

## 3.3.8

### Fixed — Step 5.12 hosting site creation auth ("Failed to authenticate")

`HostingSiteManager` was invoking `firebase hosting:sites:list` /
`hosting:sites:create` / `target:apply` **without passing
`GOOGLE_APPLICATION_CREDENTIALS`**, so firebase-tools fell through to
its stored login token at
`~/.config/configstore/firebase-tools.json`. The moment a user ran
`firebase logout` (or had never run `firebase login` to begin with),
step 5.12 failed with:

```
release: Error: Failed to authenticate, have you run firebase login?;
beta:    Error: Failed to authenticate, have you run firebase login?
```

**Two-part fix:**

1. **`HostingSiteManager` now accepts an `environment` constructor
   parameter** that is propagated to every `_runner.run('firebase', …)`
   call (`hosting_site_manager.dart:105-126`, `:131-153`,
   `:175-217`). The orchestrator wires it from the new public
   `FirebaseService.authEnvironment` getter
   (`firebase_service.dart:69-81`,
   `firebase_setup_orchestrator.dart:300-315`). Without an `environment`,
   `firebase` calls inherit only the parent shell env — exactly the
   broken path. With it, every hosting CLI call authenticates as the
   same SA the rest of Oracular uses.

2. **Self-heal for "Failed to authenticate" / "Command requires
   authentication" responses** (`hosting_site_manager.dart:268-303`).
   When `environment` is configured AND the create call still hits an
   auth error, Oracular now runs `firebase logout --force` (with the
   shell env, NOT the SA env, so firebase-tools can find and clear its
   own configstore) and retries the create. Logout failure is logged
   but doesn't block the retry. The pattern matches the same
   stale-login auto-recovery shipped for `apps:list` in 3.3.4.

The self-heal is intentionally gated on `environment != null`: without
that signal we cannot tell whether the user wants SA-based auth or
relies on a real `firebase login`, so wiping the login could lock them
out.

#### Tests

- `test/unit/hosting_site_manager_test.dart:271-385` — 4 new env-propagation
  tests verifying `listSites`, `ensureBetaSite`, `applyTargets` all forward
  the env, and that omitting it means `null` is forwarded (so child
  inherits parent shell env).
- `test/unit/hosting_site_manager_test.dart:388-560` — 4 new self-heal tests
  covering auth-failure → force-logout → retry, no-env-bypass,
  retry-also-fails, alternate "Command requires authentication" wording.

Validation: `dart analyze lib/` clean, `dart test test/unit/` 302/302 passed
(8 new + 294 prior).

---

## 3.3.7

### Added — Wizard rebuild flow + go-back navigation + storage prompt fix

Two new features and one polish item:

#### 1. `oracular rebuild` (and `oracular refresh` alias)

Re-scaffolds an existing project from its saved `config/setup_config.env`
**without touching Firebase / IAM / Cloud Run setup**. Use it after pulling
template updates, after a fresh `git clone`, or any time you need a clean
project skeleton without bouncing through the 12-step Firebase orchestrator
again.

```bash
# Run from inside the project root (auto-detects config/setup_config.env)
oracular rebuild

# Run from anywhere with explicit paths
oracular rebuild --output-dir ~/code/myapp --config ~/code/myapp/config/setup_config.env

# See exactly what will be deleted without doing it
oracular rebuild --dry-run

# Skip the confirmation prompt (e.g. for CI)
oracular rebuild --yes
```

The flow:

1. Loads `SetupConfig` from `setup_config.env`.
2. Shows a dry-run preview of which folders will be deleted.
3. Confirms (skip with `--yes`).
4. Deletes only `<appName>` (or `<webPackageName>` for Jaspr),
   `<appName>_models` (if enabled), `<appName>_server` (if enabled),
   `.oracular_deps/`, and `references/`. **Never** touches `.firebaserc`,
   `firebase.json`, `firestore.rules`, service-account JSON files, the
   saved config, `docs/`, or `GET_STARTED.md`.
5. Re-runs the scaffolding pipeline: `ProjectCreator` → `TemplateCopier` →
   models linking → `pub get` → `build_runner` → `ConfigGenerator` →
   `ServerSetup` → re-write `setup_config.env` + guides.

The interactive wizard now offers Rebuild as a top-level menu choice
alongside Start / Quit, so users don't need to remember the named
subcommand.

#### 2. Wizard "go back" navigation

Every prompt in the wizard now accepts `back`, `b`, `<`, or `:back` to
step backwards, and `quit` / `q` / `:q` / `exit` / `cancel` to abort
entirely. The keywords work in both `interact`-styled prompts and the
simple-prompt fallback (CI / non-TTY environments).

Yes/No prompts that want a back option get a third `↵ Back to previous
step` choice. Menu/theme prompts (showMenu, askTheme) get a `↵ Back`
appended to their option list.

The welcome screen now advertises both the action menu and the back/quit
keywords so the navigation hint is the first thing users see.

New API:
- `oracular/lib/utils/wizard_navigation.dart`:
  - `BackNavigation`, `CancelNavigation` exceptions
  - `WizardNav.askString()`, `WizardNav.askYesNo()`, `WizardNav.askTheme()`,
    `WizardNav.showMenu()` — drop-in replacements that throw
    `BackNavigation` when the user asks to retreat.

#### 3. Storage bucket prompt now uses modern naming

The wizard's "Initialize the default Storage bucket" question now references
the `<projectId>.firebasestorage.app` bucket name (the default for projects
created Sept 2024+) instead of the legacy `<projectId>.appspot.com` form.
The orchestrator already probes both names since v3.3.5, so this is purely
a copy fix to align the user-facing question with what oracular actually
provisions.

### New files

| Path | Purpose |
|------|---------|
| `oracular/lib/cli/handlers/rebuild_handlers.dart` | `handleRebuild` CLI entry point. |
| `oracular/lib/services/project_purger.dart` | `ProjectPurger` + `PurgeReport` — knows exactly which folders Oracular created and refuses to delete anything else (firebase config, service-account keys, saved `setup_config.env`, etc). |
| `oracular/lib/utils/wizard_navigation.dart` | `BackNavigation` / `CancelNavigation` exceptions and `WizardNav` prompt wrappers. |
| `oracular/test/unit/project_purger_test.dart` | 9 tests covering Flutter / Jaspr / models / server / idempotency / outputDir guard. |
| `oracular/test/unit/wizard_navigation_test.dart` | 7 tests covering keyword sets, exception messages, label content. |

### Modified

| File | Change |
|------|--------|
| `oracular/lib/cli/commands.dart` | Added `rebuild` and `refresh` (alias) commands with `--config`, `--output-dir`, `--yes`, `--dry-run` flags. |
| `oracular/lib/services/interactive_wizard.dart` | New `_chooseStartAction` action menu (Start / Rebuild / Quit). New `_runRebuildFlow` delegates to the shared CLI handler. Updated welcome banner with back/quit keyword hints. Storage bucket prompt now mentions `firebasestorage.app`. |

### Validation

- `dart analyze lib/` — clean (no new issues; only 2 pre-existing
  `dangling_library_doc_comments` warnings remain in `string_utils.dart`
  and `validators.dart`).
- `dart test test/unit/` — **294/294 passed** (278 prev + 16 new).

---

## 3.3.6

### Fixed — Step 5.11 `jaspr build` no longer fails on analyzer version conflict

When step 5.11 (Build web app) ran for a Jaspr project that also depends on
`arcane_models`, the build would fail with:

```
[CLI] [CRITICAL] Failed to connect to the build daemon. See the error above for more details.
```

That cryptic error masks a `pub get` resolution conflict:

- `jaspr_builder ^0.23.x` requires `analyzer ^10.0.0`.
- The published `artifact_gen ^1.x` and `fire_crud_gen ^1.x` pin
  `analyzer ^8.0.0`. They are pulled into the web app's build graph by
  `auto_apply: dependents` in the upstream `artifact` and `fire_crud`
  packages' `build.yaml`, even though the web app itself never defines
  any model classes.

These constraints are disjoint — `pub get` cannot resolve them in the same
project. Real model generation already happens inside the dedicated models
package (which does NOT depend on `jaspr_builder`), so the web app only
needs to consume the already-generated `.g.dart` files. It does not need
to re-run those builders.

This release vendors **pure no-op shim packages** for `artifact_gen` and
`fire_crud_gen` and wires them in via `dependency_overrides`:

- **New `templates/_vendor/artifact_gen/`** and
  **`templates/_vendor/fire_crud_gen/`** — minimal pubspecs that depend
  only on `build: ^4.0.0` (which allows analyzer 8 through 12), plus a
  single `Builder` factory each that returns a no-op `Builder`. Same
  package names, same library entrypoints, same factory function
  signatures as upstream — `build_runner` resolves the imports cleanly,
  produces no output, and `pub get` is happy.
- **`TemplateCopier._vendorJasprBuilderShims`** copies both shims to
  `<project>/.oracular_deps/` and injects `dependency_overrides` entries
  whenever a Jaspr template (`arcane_jaspr_app` or `arcane_jaspr_docs`)
  is scaffolded with models enabled.
- **`PlaceholderReplacer.addVendoredOverride`** is a generic helper used
  by both the new shim wiring and the existing `addJpatchOverride`.
  Handles header-or-no-header, idempotency, comment-aware duplicate
  detection.
- **`FirebaseService._ensureJasprBuilderShims`** runs as a self-healing
  pre-flight before every `jaspr build` step. It detects projects
  scaffolded by older Oracular versions, copies the shims, injects the
  overrides, and re-runs `dart pub get` automatically. Existing projects
  fix themselves on the next wizard run — no manual intervention.
- New `_findTemplatesBasePath` resolves `templates/_vendor/` for both
  `dart pub global activate . --source=path` (repo-relative) and
  installed `pub.dev` deployments (`Platform.script` traversal).

Test coverage:
- 6 new tests in `placeholder_replacer_test.dart` cover the new
  `addVendoredOverride`: empty pubspec, existing block, idempotency,
  jpatch wrapper compatibility, missing-file no-op, comment-only
  override line.
- All 278 unit tests pass.

End-user impact: any Jaspr web/docs project that links arcane_models —
new or existing — now builds cleanly on the first try. Step 5.11 no
longer fails with build-daemon errors that have no actionable
debugging path.

## 3.3.5

### Fixed — Step 5.7 default Storage bucket no longer fails on reserved-domain 403

When step 5.7 (Initialize Storage default bucket) ran, Oracular would call
`gcloud storage buckets create gs://<projectId>.appspot.com`. That fails
with HTTP 403 "verify domain ownership at search.google.com/search-console"
because `.appspot.com` and `.firebasestorage.app` are reserved Google
domains — only the Firebase Console (running with implicit ownership)
can provision default Firebase Storage buckets, and modern Firebase
projects (post-Sept 2024) get `<projectId>.firebasestorage.app` instead
of the legacy `<projectId>.appspot.com` anyway.

This release replaces the doomed `buckets create` path with a probe-
both-candidates + interactive console hand-off:

- **`ensureStorageBucket`** now probes BOTH `.firebasestorage.app` AND
  `.appspot.com` via `gcloud storage buckets describe`. Whichever exists
  is the default bucket. No more hard-coded `<projectId>.appspot.com`.
- If neither exists, returns `needsFirebaseInit=true` with the direct
  Firebase Console URL — never attempts a `buckets create` against
  reserved domains.
- **New `_handoffStorageBucketInit` orchestrator method** auto-opens
  `https://console.firebase.google.com/project/<projectId>/storage`
  in the user's browser, prints the exact button-by-button sequence
  ("Get started" → "Start in production mode" → location → "Done"),
  then re-probes `gcloud storage buckets describe` after the user
  confirms. Up to 4 retry rounds with 5-second waits cover the
  ~30s Firebase backend provisioning window.
- New `LinkOpener` import wires the orchestrator into the existing
  cross-platform URL opener (`open` / `xdg-open` / `cmd /c start`).
- Updated stub-runner tests cover all three new probe paths
  (modern bucket exists, legacy fallback, both missing → hand-off).

End-user impact: step 5.7 either succeeds silently (bucket already
exists) or prints a clear "click these 5 buttons" workflow with the
URL auto-opened — instead of failing hard with a confusing
search-console domain-verification error that the user has no way
to resolve.

## 3.3.4

### Fixed — Step 5.5 PERMISSION_DENIED root-causing + auto-recovery

When step 5.5 hit `firebase apps:list WEB` PERMISSION_DENIED the wizard
would burn 56 seconds on backoff retries (8s + 16s + 32s) and then bail
out with a generic "grant `roles/firebase.viewer`" hint that didn't
explain *why* the SA — which the IAM gate had just verified — couldn't
list apps.

The actual cause is almost always one of two things, neither of which
the previous error message identified:

1. **Stale `firebase login` token.** `firebase-tools` prefers the login
   token at `~/.config/configstore/firebase-tools.json` over
   `GOOGLE_APPLICATION_CREDENTIALS`. So a developer who ran
   `firebase login` once as their personal account hits PERMISSION_DENIED
   on every Oracular run, even though `gcloud …` calls (which DO honor
   `GOOGLE_APPLICATION_CREDENTIALS`) succeed. The IAM gate verifies the
   service-account, then step 5.5 silently runs as the wrong user.
2. **Wrong service account.** Multiple SAs in the project, the gate
   verified one, but the JSON file Oracular found is for another.

This release self-heals (1) and exposes (2):

- **`getActiveFirebaseAccount()`** parses `firebase login:list --json`
  to identify which account the Firebase CLI is actually using.
- **First-defense auto-recovery in `_runFirebaseWithRecovery`:** on
  the first PERMISSION_DENIED, if the firebase login email differs
  from the SA email, automatically run `firebase logout <stale-account>`
  and retry. firebase-tools then falls back to ADC and uses
  Oracular's SA. Zero user intervention.
- **Reduced wasted retries:** PERMISSION_DENIED now retries at most
  once (10s wait) instead of 3 times (8s+16s+32s = 56s). The IAM gate
  already polls up to 60s for IAM propagation, so by the time
  `_runFirebaseWithRecovery` sees PERMISSION_DENIED, propagation is
  done — more retries can't fix what's wrong.
- **`_logCredentialDiagnostics()`** dumps the four identities Oracular
  can see (SA file, SA email, active gcloud account, firebase CLI
  login) AND the last 50 lines of `firebase-debug.log` verbatim
  *before* surfacing the failure. The user no longer has to
  `cat firebase-debug.log` themselves to find the actual API
  response — Oracular prints it inline.
- **Multi-line `underlying error:` output:** the verbose log now
  prints every line of `_collectFirebaseFailureContext` instead of
  truncating to the first line ("See firebase-debug.log for more
  info."), so the actual structured error from the Firebase
  Management API response is visible without digging into the log
  file.

After this fix, the failure mode you saw goes away because:
- If the cause is a stale firebase login → auto-logout + retry → success.
- If the cause is genuine missing IAM → diagnostics show the SA email,
  the firebase CLI login email, and the actual `PERMISSION_DENIED`
  message from `firebase-debug.log` so you can tell at a glance which
  identity needs the role.

## 3.3.3

### Fixed — Step 5.4 IAM gate now verifies Firebase-specific permissions

The IAM gate in step 5.4 only probed `serviceusage.services.enable` —
which a service account with `roles/serviceUsageAdmin` happily passes
even though it lacks `firebase.apps.list`/`firebase.apps.create`. The
gate would then green-light step 5.4, the propagation poll would never
succeed (because the API *was* enabled, the *caller* just couldn't see
it), step 5.5 would run, and the user would land on a Retry/Skip/Abort
prompt with no usable next step.

This release closes the gap:

- **New `FirebaseService.canListFirebaseApps`** runs
  `firebase apps:list WEB --json` against the project as the active
  credential and classifies the result with the existing failure
  classifier — so `permissionDenied` is detected the same way
  step 5.5 would detect it.
- **The IAM gate now probes both** `serviceusage.services.enable`
  *and* `firebase.apps.list`. If either is missing, the gate fails
  fast and the auto-grant flow is triggered (instead of waiting
  until step 5.5 to discover the missing role).
- **Auto-grant + post-grant verification** now polls *both*
  permissions with exponential backoff up to ~60s, so the orchestrator
  waits for IAM propagation rather than racing it.
- **`_waitForFirebaseManagementApi`** now exits early on
  `permissionDenied` instead of burning the whole 47s budget — a
  missing role will not be fixed by waiting.
- **`_runFirebaseWithRecovery`** retries `permissionDenied` once with
  a 15s wait. This catches the narrow window where step 5.4 just
  granted the role and the binding hasn't propagated to the IAM
  edge for the calling project yet.
- **The required-roles list** now explicitly includes
  `roles/firebase.admin` so the auto-grant flow grants what
  `firebase apps:list` actually needs (not just `serviceUsageAdmin`).

After this fix, the "stuck at step 5.4 propagation poll → step 5.5
fails with `permissionDenied`" path is replaced by:
1. Step 5.4 detects the missing `firebase.apps.list` permission
   *before* enabling APIs.
2. Auto-grants `roles/firebase.admin` (and the rest of the bundle).
3. Polls until both permissions are visible to the caller.
4. Step 5.5 then runs cleanly without bouncing the user out.

## 3.3.2

### Fixed — Step 5.5 (Configure Firebase client wiring) auto-recovery

Step 5.5 used to abort the wizard with a "Run `oracular deploy
firebase-setup-full`" hint whenever `firebase apps:list WEB` failed —
the most common cause being that the Firebase Management API was just
enabled in step 5.4 but had not yet propagated. The wizard would dump
the user out, even though the only fix was "wait 30 seconds and re-run".

This release makes step 5.5 self-healing:

- **`_runFirebaseWithRecovery`** wraps every `firebase --json` call
  (`apps:list`, `apps:create`, `apps:sdkconfig`) in an auto-retry loop
  that:
  - reads `firebase-debug.log` to extract the structured error envelope
    from the Firebase Management API (the CLI hides this behind the
    generic "see firebase-debug.log for more info" banner);
  - **classifies** the error into `serviceDisabled`,
    `permissionDenied`, `transient`, or `unknown`;
  - **auto-runs `gcloud services enable firebase.googleapis.com`** and
    waits for propagation when it sees `SERVICE_DISABLED` (no
    user intervention required);
  - **retries with exponential backoff** (1s, 2s, 4s, 8s) on transient
    errors (5xx, `DEADLINE_EXCEEDED`, `ECONNRESET`, `socket hang up`);
  - surfaces a concrete IAM hint for `PERMISSION_DENIED`.
- **`enableFirebaseCoreApis`** now polls `firebase apps:list` until the
  Firebase Management API actually answers (capped exponential backoff,
  up to ~30s), closing the propagation gap between step 5.4 and 5.5.
- The step 5.5 failure message now explains the *actual* cause from
  `firebase-debug.log` instead of a one-size-fits-all "run
  firebase-setup-full" suggestion. The hint includes "wait 30-60s and
  retry" as the most common fix because the auto-recovery has already
  handled the API-not-enabled case.

### Added
- 14 new unit tests pinning down the failure classifier
  (`FirebaseFailureKind`) and structured-error parser
  (`firebaseErrorForTest`) so future regressions are caught in CI:
  matches `SERVICE_DISABLED`, `PERMISSION_DENIED`, `503`,
  `DEADLINE_EXCEEDED`, `ECONNRESET`, `socket hang up`, ANSI-prefixed
  spinner JSON.

## 3.3.0

### Added — End-to-End Firebase Setup
- **`FirebaseSetupOrchestrator`** drives a full 12-sub-step Firebase setup so
  `oracular` no longer stops after just `firebase login` + `flutterfire
  configure`. Sub-steps: firebase login, gcloud auth (server only), billing
  check, **enable required Firebase APIs**, client wiring (FlutterFire or
  Jaspr JS SDK injection), Firestore default DB, Storage default bucket,
  auth providers (email/password + Google), deploy Firestore + Storage
  rules, build web bundle, ensure `<project>-beta` site, deploy hosting
  (release + beta).
- **Fail-fast with Retry / Skip / Abort prompt.** When any sub-step fails,
  the wizard now stops, prints the reason + suggested fix, and asks
  whether to retry the same step, skip it, or abort the whole run. You
  can fix something in another terminal and hit `r` to re-run just the
  failed step.
- **Auto-enable Firebase APIs upfront** (`enableFirebaseCoreApis`):
  `firebase.googleapis.com`, `firestore.googleapis.com`,
  `firebasestorage.googleapis.com`, `firebasehosting.googleapis.com`,
  `identitytoolkit.googleapis.com`, `serviceusage.googleapis.com`. This
  prevents downstream `SERVICE_DISABLED` errors and the `firebase
  apps:list` failures that broke Jaspr JS SDK injection.
- **Billing-absent detection.** Firestore + Storage steps now detect the
  "billing account is disabled in state absent" error and surface a
  clean message pointing at the Blaze upgrade URL instead of a raw
  gcloud stack trace.
- **8 new CLI subcommands** so any failed step is independently
  re-runnable:
  - `oracular check billing`
  - `oracular deploy firebase-setup-full` (alias: `firebase-setup`)
  - `oracular deploy hosting-init`
  - `oracular deploy firestore-init`
  - `oracular deploy storage-init`
  - `oracular deploy auth-providers`
  - `oracular deploy artifact-cleanup`
  - `oracular deploy cloudrun-prune`
- **Hosting beta site auto-creation** via `HostingSiteManager` —
  `<project>-beta` site is created and `firebase target:apply hosting
  beta` is wired automatically.
- **Artifact Registry / Cloud Run cleanup** baked into both the wizard
  and the generated `script_deploy.sh`. Ships
  `templates/arcane_server/cleanup-policy.json` (keep 5 most recent +
  delete >30 days) and prunes Cloud Run revisions to the last 3.
- **"What was deployed" summary** at the end of the wizard with live
  release/beta URLs, Firebase + GCP console links, and the Cloud Run
  URL when applicable. Jaspr-aware copy ("Jaspr docs site" / "Jaspr
  web app" / "Flutter web app").
- **Post-creation checklist now filters out completed steps** instead
  of always printing the same boilerplate. Only skipped or partial
  steps remain.

### Fixed
- Wizard previously did `firebase login` + `flutterfire configure` and
  declared victory — leaving you with no deployed site, no beta site,
  no Firestore database, no Storage bucket, no rules deployed, and no
  cleanup policies on the server. Now every one of those is a real
  step you can run, retry, or skip.
- `flutterfire configure` for Jaspr templates failed with "Failed to
  list Firebase WEB apps" when the Firebase Management API was not
  enabled. Fixed by always enabling that API in step 5.4 *before*
  calling `firebase apps:list`.
- `gcloud firestore databases describe` failed with `SERVICE_DISABLED`
  on first-run projects. Fixed by enabling `firestore.googleapis.com`
  upfront and by detecting the API-not-enabled error with a precise
  fix-hint.
- `gcloud storage buckets create` failed with billing-absent on Spark
  projects. Fixed: the wizard now detects this early and instructs you
  to upgrade to Blaze with the exact console URL.
- `oracular version` reported a hard-coded `2.0.0` instead of reading
  from `lib/version.dart`. Fixed both in `bin/main.dart` and the
  `commands.dart` version handler.

### Changed
- `firebase-setup` is now an alias for `firebase-setup-full` so the
  shorter command runs the new end-to-end flow.
- `_offerFirebaseSetup` in the wizard is now a thin driver around the
  orchestrator; per-substep counters render `5.1` / `5.2` / `6.1`
  inline labels.
- Default `runAll` behavior is **fail-fast** (abort on first failure
  unless an `onFailure` handler returns `skip` or `retry`). Pass
  `onFailure: (_, {required attempt}) async => FailureAction.skip` to
  opt into the legacy "always continue" semantics.

### Tests
- 239 unit tests passing (up from 135 baseline).
- New test suites: `firebase_setup_orchestrator_test.dart` (17 tests),
  `firebase_billing_service_test.dart`,
  `firebase_initializer_test.dart`, `hosting_site_manager_test.dart`,
  `artifact_cleanup_service_test.dart`, plus expanded coverage on
  `setup_config_test.dart`, `setup_guidance_test.dart`,
  `server_setup_test.dart`, and `firebase_service_test.dart`.

## 3.1.2

### Added
- **Welcome banner** now shows the running Oracular version (e.g. `Arcane
  Template System  ·  v3.1.2`). Section headers in the wizard's reset-viewport
  also show `v$version  ·  Step N of 5`.
- **`docs/` folder** is generated at the root of every created project with a
  full set of how-to guides tailored to your config:
  - `README.md` (table of contents + project-at-a-glance summary)
  - `01-getting-started.md` - run the project, install deps, wire Firebase
  - `02-commands.md` - every Oracular subcommand and pubspec script available
  - `03-project-structure.md` - folder layout for the chosen template
  - `04-development.md` - hot reload, code-gen, adding routes/screens
  - `05-firebase.md` (or `Firebase Later` when not enabled)
  - `06-deployment.md` - hosting, firestore, storage rules
  - `07-server.md` - service account flow + Cloud Run
  - `08-models.md` - artifact patterns + path dependencies
  - `09-troubleshooting.md` - jaspr / arcane_auth_jaspr / FlutterFire fixes
  - `10-resources.md` - upstream docs links
- New `oracular open docs` target opens the docs folder in the OS file
  browser. `oracular guide` regenerates both `GET_STARTED.md` and `docs/`.

### Fixed
- **`arcane_auth_jaspr` no longer auto-uncommented** when Firebase is enabled.
  The published `arcane_auth_jaspr` is pinned to `jaspr ^0.22.0` while the
  Jaspr template uses `jaspr ^0.23.0`, so auto-enabling it produced
  `version solving failed` errors during `dart pub get`. The base Jaspr
  template is now a clean husk with **no auth dependency** by default.
- Jaspr template README updated to reflect the correct Firebase wiring path
  for `jaspr 0.23.x` (use the JS SDK directly or call `arcane_server`
  endpoints; do not add `arcane_auth_jaspr` until a `0.23.x`-compatible
  release ships).

## 3.1.1

### Changed
- **Service account key prompt**: instead of asking the user to type a long
  absolute path (which the terminal input clips), Oracular now opens the
  destination folder in Finder/Explorer/file manager, instructs the user to
  drop their `*.json` key file into that folder, and auto-detects/renames it
  to `service-account.json`. Press Enter when done, or type `skip` to add it
  later. Multiple JSON files are disambiguated with a numbered picker.
- **Multi-select / picker viewport**: each major section in the wizard
  (Template Selection, Target Platforms, Additional Packages, Cloud Services)
  now starts with a clean screen and a compact context strip showing the
  choices made so far. Fixes the issue where pressing arrow keys inside the
  Target Platforms multi-select made the console "go up" and look awful as
  the prompt redrew over previously printed help text.

## 3.1.0

### Added
- Wizard intro now asks for the **target location** up front. Press Enter to use
  the current directory, type an absolute or relative path, or use `~` as a
  shortcut for your home directory. Missing directories can be auto-created.
- Pure-Dart `jpatch` shim vendored under `templates/_vendor/jpatch/` and
  auto-injected into Jaspr/Dart-CLI projects that depend on `arcane_models`,
  so pure-Dart targets resolve **without** dragging in the Flutter SDK.
- Spinner prompts now accept a `failedMessage` so failed steps render an `✗`
  with stderr output instead of a misleading `✓`.

### Changed
- Templates upgraded to `arcane_jaspr ^3.3.0` with `arcane_jaspr_shadcn` pulled
  via git from the monorepo. `app.dart` switched from `child:` to the new
  `home:` API.
- `arcane_jaspr_docs` template now references `arcane_jaspr_shadcn` and
  `arcane_lexicon` via git deps instead of brittle `.oracular_deps/...` paths.
- `arcane_models` template no longer pulls in `arcane_admin` (which dragged
  Flutter into pure-Dart consumers).
- `arcane_server` template uses `listenPortFromEnvironment()` from current
  `google_cloud`.
- Pinned `package_info_plus` / `launch_at_startup` / etc. across templates to
  versions that actually resolve, removed unused `interact` dep from
  `arcane_cli_app`.
- Spinner-wrapped CLI processes now run in non-interactive mode so they can't
  deadlock waiting for TTY input behind the spinner.

### Fixed
- **Firebase web app provisioning**: switched all `firebase apps:*` calls to
  `--json` mode with explicit success/failure detection, fixing the
  `Failed to create Firebase web app` / `Failed to list Firebase web apps`
  cascade when configuring FlutterFire for Jaspr projects.
- **Wizard reporting failures as success**: the wizard now tracks failed steps
  and prints a `✗ Project Created With Issues` banner with the list of failed
  steps when anything went wrong, instead of always printing the success box.
- **Spinner showing `✓ Done` on failure**: the spinner now renders `✗` with
  the actual error message on failure.
- **Jaspr + server + models permutation**: end-to-end resolution and
  compilation now works (no Flutter SDK leakage) and is covered by integration
  tests.
- `addModelsDependency` no longer skips the dependency when the package name
  appears in a comment, and no longer crashes on regex matches that span
  newlines.

## 3.0.0

### Added
- New `oracular gitignore` command to add the standard `.gitignore` to any project
  - Use `--force` or `-f` to overwrite an existing `.gitignore`
- Comprehensive `.gitignore` added to all templates with Jaspr support
- Jaspr-specific ignores: `.jaspr/`, `web/main.dart.js`, `web/main.dart.js.deps`, `web/main.dart.js.map`, `web/main.dart.mjs`

### Fixed
- Jaspr and models package creation now deletes the auto-generated `example/` folder

## 2.2.2

### Fixed
- Template download failing due to case sensitivity in GitHub archive prefix (`oracular-master` vs `Oracular-master`)

## 2.2.0

- **Template Updates - arcane_jaspr_docs**:
  - Full theme switching system with 18 theme presets (colors, neutrals, OLED)
  - CSS variable-based theming using `ArcaneThemeProvider`
  - Theme persistence via localStorage
  - Search functionality with keyboard navigation
  - Code block copy buttons
  - Stateful theme toggle (sun/moon icons)
  - Updated sidebar with `ArcaneSideContent` and modern styling
  - Removed index.html for static mode compatibility

- **Template Updates - arcane_jaspr_app**:
  - Added shared `AppHeader` component with theme toggle
  - Stateful `App` component with dark/light mode switching
  - CSS variable-based theming using `ArcaneThemeProvider`
  - Theme persistence via localStorage
  - Updated screens to use shared header (DRY)
  - Added `AppConstants` class for centralized configuration
  - Theme initialization script in index.html (prevents flash)
  - Modern scrollbar and focus state styling

## 2.1.0

- **CLI Improvements**:
  - Interactive prompts for project configuration
  - Template-specific next steps in success message

## 2.0.0

- **Template Distribution**: Templates are now downloaded from GitHub at runtime
  - No longer bundled in the package - keeps install size small
  - Cached locally at `~/.oracular/templates/`
  - Automatic version checking and updates
- **New `templates` command**: Manage template cache
  - `oracular templates status` - Show cache status
  - `oracular templates update` - Download/update templates
  - `oracular templates clear` - Clear the cache
  - `oracular templates path` - Show cache location
- **CLI Framework**: Migrated to darted_cli
- **Script Runner**: Fuzzy matching with abbreviation support
- **Complete rewrite** of project scaffolding system

## 1.0.0

- Initial version.
