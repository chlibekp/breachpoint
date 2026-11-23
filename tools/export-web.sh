#!/usr/bin/env bash
# Web export with half-resolution 3D textures (spec §9.3 browser tier). Godot has no per-platform texture
# size, so this exports from a staging copy of client/ whose 3D texture imports get
# process/size_limit=512. Most source textures are 1024², so these are 4× smaller. UI, fonts and VFX
# textures are left alone. Usage: GODOT_BIN=… tools/export-web.sh [Web|"Web (threaded)"]
set -euo pipefail
cd "$(dirname "$0")/.."
PRESET="${1:-Web}"
ROOT="$PWD"
STAGE="$ROOT/client/build/.web-stage"
OUT="$ROOT/client/build/web"
[ "$PRESET" = "Web (threaded)" ] && OUT="$ROOT/client/build/web-threaded"
rm -rf "${STAGE:?}" "${OUT:?}"
mkdir -p "$STAGE" "$OUT"
# Copy the project (with its import cache, so only the halved textures re-import), minus builds.
tar -C client --exclude=./build -cf - . | tar -C "$STAGE" -xf -
python3 - "$STAGE" <<'PY'
import pathlib, re, sys
stage = pathlib.Path(sys.argv[1])
n = 0
for imp in stage.joinpath("assets").rglob("*.png.import"):
    rel = imp.relative_to(stage).as_posix()
    if any(rel.startswith(p) for p in ("assets/ui/", "assets/fonts/", "assets/vfx/")):
        continue
    text = imp.read_text()
    if "process/size_limit=" in text:
        imp.write_text(re.sub(r"process/size_limit=\d+", "process/size_limit=512", text))
        n += 1
print(f"half-res web textures: {n} imports set to size_limit=512")
PY
GODOT_BIN="${GODOT_BIN:?set GODOT_BIN}"
"$GODOT_BIN" --headless --path "$STAGE" --import >/dev/null 2>&1 || true
"$GODOT_BIN" --headless --path "$STAGE" --export-release "$PRESET" "$OUT/index.html"
cp client/assets/fonts/ChakraPetch-Bold.ttf "$OUT/chakrapetch-bold.ttf"
# Long-cache hashed filenames (spec §14.5): nginx serves everything but index.html as immutable, so
# the engine files and pack get a content hash in their name and index.html points at them.
python3 - "$OUT" <<'PY'
import hashlib, json, pathlib, re, sys
out = pathlib.Path(sys.argv[1])
h = hashlib.sha256()
for name in ("index.js", "index.wasm", "index.pck"):
    h.update(out.joinpath(name).read_bytes())
tag = "index." + h.hexdigest()[:12]
for old in out.glob("index.*"):
    if old.name in ("index.html",) or old.suffix in (".png", ".import", ".svg"):
        continue
    old.rename(out / (tag + old.name[len("index"):]))
html = out.joinpath("index.html").read_text()
m = re.search(r"const GODOT_CONFIG = (\{.*?\});", html)
cfg = json.loads(m.group(1))
cfg["executable"] = tag
cfg["mainPack"] = tag + ".pck"
cfg["fileSizes"] = {k.replace("index", tag, 1): v for k, v in cfg["fileSizes"].items()}
html = html.replace(m.group(0), "const GODOT_CONFIG = " + json.dumps(cfg, separators=(",", ":")) + ";")
html = html.replace('src="index.js"', f'src="{tag}.js"')
out.joinpath("index.html").write_text(html)
print("hashed web files:", tag)
PY
rm -rf "${STAGE:?}"
PCK=$(ls "$OUT"/index.*.pck)
WASM=$(ls "$OUT"/index.*.wasm)
du -sh "$PCK" "$WASM"
echo "gzip: pck $(gzip -c "$PCK" | wc -c | awk '{printf "%.1f MB", $1/1e6}'), wasm $(gzip -c "$WASM" | wc -c | awk '{printf "%.1f MB", $1/1e6}')"
