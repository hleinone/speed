#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter is required. Run 'mise install' from the project root first." >&2
  exit 1
fi

echo "Rendering store-ready screenshots..."
flutter test --no-pub --update-goldens tool/store_screenshots/generate_test.dart

echo "Store screenshots are ready in build/store-screenshots/."
echo "Open build/store-screenshots/index.html to review the contact sheet."
