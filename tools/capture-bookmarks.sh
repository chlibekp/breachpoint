#!/usr/bin/env bash
# Captures every bookmark camera of a map (spec §9.5 / §18 reporting) into qa/screens/<date>/<map>/.
# Usage: GODOT_BIN=… tools/capture-bookmarks.sh <map> [renderer: forward_plus|gl_compatibility] [WxH]
# Lightmapped scenes take minutes per frame on software Vulkan (lavapipe); each capture has 15 min.
set -uo pipefail
cd "$(dirname "$0")/.."
MAP="${1:?map id}"
RENDERER="${2:-forward_plus}"
SIZE="${3:-1920x1080}"
OUT="qa/screens/$(date +%F)/$MAP"
mkdir -p "$OUT"
if [ -z "${VK_ICD_FILENAMES:-}" ] && [ -f /opt/lavapipe/lvp_icd.json ]; then export VK_ICD_FILENAMES=/opt/lavapipe/lvp_icd.json; fi
N=$(node -e "console.log(require('./shared/maps/$MAP.meta.json').bookmarks.length)")
for ((i = 0; i < N; i++)); do
  NAME=$(node -e "console.log(require('./shared/maps/$MAP.meta.json').bookmarks[$i].name.toLowerCase().replace(/[^a-z0-9]+/g,'_'))")
  FILE="$OUT/$(printf %02d "$i")_${NAME}_${RENDERER}.png"
  [ -f "$FILE" ] && continue
  xvfb-run -a -s "-screen 0 ${SIZE}x24" timeout 900 bash tools/godot.sh --path client \
    --rendering-method "$RENDERER" -- --capture=res://scenes/dev/lookdev.tscn \
    --map="$MAP" --bookmark="$i" --size="$SIZE" --frames=30 --out="$PWD/$FILE" 2>&1 | grep -E "^\[capture\]"
done
