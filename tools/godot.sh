#!/usr/bin/env bash
# Runs the pinned Godot binary. Set GODOT_BIN to override; otherwise uses `godot` on PATH.
# The pinned version lives in .godot-version and must match `$GODOT_BIN --version`.
set -euo pipefail
BIN="${GODOT_BIN:-godot}"
exec "$BIN" "$@"
