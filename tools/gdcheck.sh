#!/usr/bin/env bash
# Compiles every GDScript in the real runtime (autoloads present); warnings are errors.
set -uo pipefail
cd "$(dirname "$0")/.."
timeout 300 bash tools/godot.sh --headless --path client res://tests/compile_all.tscn 2>&1 | grep -E "✗|    |scripts," 
exit "${PIPESTATUS[0]}"
