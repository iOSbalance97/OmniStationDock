#!/bin/bash
# Publica la release «libretro-cores» con todos los núcleos: baja los que ya había y añade o cambia
# los de dist/libretro. Necesita GH_TOKEN y GITHUB_REPOSITORY.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT/dist/libretro"
rm -rf previous
mkdir -p previous
gh release download libretro-cores --repo "$GITHUB_REPOSITORY" --dir previous 2>/dev/null || true
if [ -f previous/cores.json ]; then
  python3 - <<'PY'
import json
old = json.load(open('previous/cores.json'))
new = json.load(open('cores.json'))
old.update(new)
json.dump(old, open('cores.json', 'w'), indent=2)
PY
fi
for file in previous/*.zip; do
  [ -f "$file" ] || continue
  name="$(basename "$file")"
  [ -f "$name" ] || cp "$file" "$name"
done
ls -l ./*.zip cores.json
gh release delete libretro-cores --repo "$GITHUB_REPOSITORY" --cleanup-tag --yes 2>/dev/null || true
gh release create libretro-cores --repo "$GITHUB_REPOSITORY" ./*.zip cores.json \
  --title "Núcleos libretro (OmniStation)" \
  --notes "Núcleos libretro compilados por OmniStation Dock desde su código (Cores/Libretro/sources.json). Los usa el workflow de la app." \
  --prerelease
