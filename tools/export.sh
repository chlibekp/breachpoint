#!/usr/bin/env bash
# Exports desktop + web builds into client/build/. Usage: tools/export.sh [preset ...]
# Default presets: Linux, Web. Requires Godot 4.7 export templates.
set -euo pipefail
cd "$(dirname "$0")/.."
PRESETS=("$@")
if [ ${#PRESETS[@]} -eq 0 ]; then PRESETS=("Linux" "Web"); fi
for preset in "${PRESETS[@]}"; do
  out=$(awk -v name="$preset" '
    /^\[preset\.[0-9]+\]$/ {inside=0}
    $0 == "name=\"" name "\"" {inside=1}
    inside && /^export_path=/ {gsub(/^export_path="|"$/, ""); print; exit}
  ' client/export_presets.cfg)
  if [ -z "$out" ]; then echo "unknown preset $preset" >&2; exit 1; fi
  mkdir -p "client/$(dirname "$out")"
  echo "▶ exporting $preset → client/$out"
  bash tools/godot.sh --headless --path client --export-release "$preset" "$out"
  case "$preset" in
    Web*) cp client/assets/fonts/ChakraPetch-Bold.ttf "client/$(dirname "$out")/chakrapetch-bold.ttf" ;;
  esac
done
du -sh client/build/* 2>/dev/null || true
