#!/bin/bash

# Run pub get on all template packages.
# Usage: ./pub_get_all.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Running pub get on all templates..."
echo ""

run_flutter_get() {
  local dir="$1"
  if [ -d "$SCRIPT_DIR/$dir" ]; then
    echo "=== $dir (flutter) ==="
    cd "$SCRIPT_DIR/$dir"
    flutter pub get
    echo ""
  fi
}

run_dart_get() {
  local dir="$1"
  local label="$2"
  if [ -d "$SCRIPT_DIR/$dir" ]; then
    echo "=== $dir ($label) ==="
    cd "$SCRIPT_DIR/$dir"
    dart pub get
    echo ""
  fi
}

# Flutter templates
run_flutter_get "arcane_app"
run_flutter_get "arcane_beamer_app"
run_flutter_get "arcane_dock_app"
run_flutter_get "arcane_server"

# Dart-only templates
run_dart_get "arcane_cli_app" "dart"
run_dart_get "arcane_models" "dart"

# Jaspr templates
run_dart_get "arcane_jaspr_app" "jaspr"
run_dart_get "arcane_jaspr_docs" "jaspr"
run_dart_get "arcane_jaspr_flutter_embed/arcane_jaspr_flutter_embed_web" "jaspr"
run_flutter_get "arcane_jaspr_flutter_embed/arcane_jaspr_flutter_embed_app"

echo "Done!"
