#!/bin/bash
# Empaqueta un núcleo ya compilado (dist/libretro/<framework>.libretro.framework) en un zip y lo
# apunta en dist/libretro/cores.json. Uso: package_core.sh <núcleo> <repo owner/name> <revisión>
set -euo pipefail
CORE="$1"
REPO="$2"
REV="$3"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FRAMEWORK="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]]["framework"])' "$ROOT/Cores/Libretro/sources.json" "$CORE")"
cd "$ROOT/dist/libretro"
FW="$FRAMEWORK.libretro.framework"
test -d "$FW"
rm -f "$FW.zip"
ditto -c -k --keepParent "$FW" "$FW.zip"
if [ "$CORE" = "dolphin" ] && [ -d dolphin-sys ]; then
  rm -f dolphin-sys.zip
  ditto -c -k dolphin-sys dolphin-sys.zip
fi
python3 - "$CORE" "$REPO" "$REV" "$FW" <<'PY'
import json, sys
core, repo, revision, framework = sys.argv[1:5]
try:
    data = json.load(open('cores.json'))
except Exception:
    data = {}
data[core] = {"repository": repo, "revision": revision, "framework": framework}
json.dump(data, open('cores.json', 'w'), indent=2)
PY
ls -l "$FW.zip"
