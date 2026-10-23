#!/bin/bash
# Baja el código de un núcleo en una revisión fija, sin submódulos (git a secas).
# Uso: fetch_source.sh <owner/repo> <revisión> <carpeta>
set -euo pipefail
REPO="$1"
REV="$2"
DEST="$3"
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
