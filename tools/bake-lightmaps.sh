#!/usr/bin/env bash
# Bakes LightmapGI for the given scenes (default: every scene listed in tools/bake-scenes.txt).
# Needs a display: runs under xvfb-run when DISPLAY is unset. Uses lavapipe if VK_ICD_FILENAMES is set.
set -euo pipefail
cd "$(dirname "$0")/.."
SCENES="${*:-$(grep -v '^#' tools/bake-scenes.txt | paste -sd, -)}"
RUN=()
if [ -z "${DISPLAY:-}" ]; then RUN=(xvfb-run -a -s "-screen 0 1920x1080x24"); fi
BP_BAKE_SCENES="$SCENES" "${RUN[@]}" bash tools/godot.sh --editor --path client --rendering-method forward_plus
