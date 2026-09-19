#!/usr/bin/env bash
# Build from the complete repository. Runtime files are prepared by Gradle.
# The original upstream embedding script is preserved in docs/upstream/build_apk.sh.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VARIANT="${1:-release}"
case "$VARIANT" in
  release) TASK_VARIANT=Release ;;
  debug) TASK_VARIANT=Debug ;;
  *) echo 'Usage: tools/build_apk.sh [release|debug]. All runtime materials are already in this repository.' >&2; exit 2 ;;
esac
"$ROOT_DIR/gradlew" -p "$ROOT_DIR" --console=plain ":app:assemble${TASK_VARIANT}"
APK="$ROOT_DIR/app/build/outputs/apk/$VARIANT/app-$VARIANT.apk"
[ -s "$APK" ] || { echo "APK missing: $APK" >&2; exit 1; }
echo "Built complete APK: $APK"
