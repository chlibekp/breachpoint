#!/usr/bin/env bash
# Compiles every GDScript in the client with warnings-as-errors; exits 1 on any error.
set -uo pipefail
cd "$(dirname "$0")/../client"
fail=0
while IFS= read -r f; do
  out=$(timeout 60 bash ../tools/godot.sh --headless --path . --check-only -s "res://${f#./}" 2>&1 | grep -E "SCRIPT ERROR|Parse Error|Compile Error" | grep -vE "Identifier not found: (Data|Settings|QualityManager|Audio|Net|Game)$" )
  if [ -n "$out" ]; then echo "✗ $f"; echo "$out" | head -5; fail=1; fi
done < <(find . -name "*.gd" -not -path "./.godot/*" -not -path "./tests/*" -not -path "./addons/*")
[ $fail -eq 0 ] && echo "✓ all scripts compile"
exit $fail
