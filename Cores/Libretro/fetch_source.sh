#!/bin/bash
# Baja el código de un núcleo en una revisión fija (git a secas). Con «recursive» como cuarto
# argumento, también sus submódulos (Flycast los necesita: core/deps).
# Uso: fetch_source.sh <owner/repo> <revisión> <carpeta> [recursive]
set -euo pipefail
REPO="$1"
REV="$2"
DEST="$3"
SUBMODULES="${4:-}"
rm -rf "$DEST"
mkdir -p "$DEST"
git -C "$DEST" init -q
git -C "$DEST" remote add origin "https://github.com/$REPO.git"
for attempt in 1 2 3; do
  if git -C "$DEST" fetch -q --depth 1 origin "$REV"; then break; fi
  [ "$attempt" = 3 ] && { echo "::error::No se pudo bajar $REPO@$REV" >&2; exit 1; }
  sleep 5
done
git -C "$DEST" checkout -q FETCH_HEAD
test "$(git -C "$DEST" rev-parse HEAD)" = "$REV"
if [ "$SUBMODULES" = "recursive" ]; then
  git -C "$DEST" submodule update --init --recursive --depth 1 --jobs 4 \
    || git -C "$DEST" submodule update --init --recursive --jobs 4
fi
