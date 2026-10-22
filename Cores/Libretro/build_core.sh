#!/bin/bash
# Compila un núcleo libretro desde su código (Cores/Libretro/sources.json) para iOS arm64 y lo
# deja como <framework>.libretro.framework en dist/libretro/, listo para la app.
# Uso: build_core.sh <núcleo> <carpeta del código>
set -euo pipefail

CORE="$1"
SRC="$(cd "$2" && pwd)"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/dist/libretro"
LOGS="$ROOT/build/libretro-$CORE"
mkdir -p "$OUT" "$LOGS"

read -r FRAMEWORK BUNDLE_ID < <(python3 - "$ROOT/Cores/Libretro/sources.json" "$CORE" <<'PY'
import json, sys
info = json.load(open(sys.argv[1]))[sys.argv[2]]
print(info["framework"], info["bundleID"])
PY
)

# Parches propios (si hay): Cores/Libretro/patches/<núcleo>/*.patch, en orden. Con «patch» (no
# «git apply») para que valgan también dentro de los submódulos del núcleo.
shopt -s nullglob
for patch in "$ROOT/Cores/Libretro/patches/$CORE/"*.patch; do
  echo "Parche: $(basename "$patch")"
  patch -p1 -N -d "$SRC" -i "$patch"
done
shopt -u nullglob

case "$CORE" in
  dolphin)
    # Igual que el workflow de iOS del propio Dolphin de libretro, con iOS 17 como mínimo.
    cmake -S "$SRC" -B "$SRC/build/ios-arm64" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
      -DIOS=ON \
      -DCMAKE_SYSTEM_NAME=iOS \
      -DCMAKE_SYSTEM_PROCESSOR=arm64 \
      -DCMAKE_OSX_ARCHITECTURES=arm64 \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
      -DLIBRETRO=ON 2>&1 | tee "$LOGS/configure.log"
    cmake --build "$SRC/build/ios-arm64" --target dolphin_libretro -j "$(sysctl -n hw.ncpu)" 2>&1 | tee "$LOGS/build.log"
    BINARY="$(find "$SRC/build/ios-arm64" -maxdepth 3 -name 'dolphin_libretro*.dylib' -print -quit)"
    ;;
  azahar)
    # dynarmic trae su propia copia de oaknut: que use la misma memoria de JIT que la de Azahar.
    if [ -f "$SRC/externals/dynarmic/externals/oaknut/include/oaknut/code_block.hpp" ]; then
      cp "$SRC/externals/oaknut/include/oaknut/code_block.hpp" "$SRC/externals/dynarmic/externals/oaknut/include/oaknut/code_block.hpp"
    fi
    grep -q dual_map_hooks "$SRC/externals/oaknut/include/oaknut/code_block.hpp"
    # Igual que el workflow libretro-ios del propio Azahar, con iOS 17 como mínimo.
    cmake -S "$SRC" -B "$SRC/build/ios-arm64" \
      -DCMAKE_BUILD_TYPE=Release \
      -DENABLE_LIBRETRO=ON \
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
      -DCMAKE_C_FLAGS=-DIOS \
      -DCMAKE_CXX_FLAGS=-DIOS \
      -DIOS=ON \
      -DCMAKE_SYSTEM_NAME=iOS \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
      -DCITRA_USE_PRECOMPILED_HEADERS=OFF \
      -DCMAKE_OSX_ARCHITECTURES=arm64 \
      -DENABLE_OPT=OFF 2>&1 | tee "$LOGS/configure.log"
    cmake --build "$SRC/build/ios-arm64" --target citra_libretro --config Release -j "$(sysctl -n hw.ncpu)" 2>&1 | tee "$LOGS/build.log"
    BINARY="$(find "$SRC/build/ios-arm64" -maxdepth 4 -name 'azahar_libretro*.dylib' -print -quit)"
    if [ -n "$BINARY" ]; then
      # Que lleve el parche del JIT permanente (antes de quitar los símbolos).
      nm "$BINARY" | grep -c SetupJITMemory >/dev/null || { echo "::error::Azahar sin el parche del JIT permanente." >&2; exit 1; }
      strip -x "$BINARY"
    fi
    ;;
  *)
    echo "Núcleo desconocido: $CORE" >&2
    exit 1
    ;;
esac

if [ -z "${BINARY:-}" ] || [ ! -f "$BINARY" ]; then
  echo "::error::No se encontró el núcleo compilado de $CORE." >&2
  exit 1
fi

# Como framework (lo que firma SideStore y carga OmniStation con dlopen).
FW="$OUT/$FRAMEWORK.libretro.framework"
rm -rf "$FW"
mkdir -p "$FW"
cp "$BINARY" "$FW/$FRAMEWORK.libretro"
install_name_tool -id "@rpath/$FRAMEWORK.libretro.framework/$FRAMEWORK.libretro" "$FW/$FRAMEWORK.libretro"
python3 - "$FW/Info.plist" "$FRAMEWORK" "$BUNDLE_ID" <<'PY'
import plistlib, sys
path, name, bundle = sys.argv[1:4]
plistlib.dump({
    "CFBundleDevelopmentRegion": "en",
    "CFBundleExecutable": name + ".libretro",
    "CFBundleIdentifier": bundle,
    "CFBundleInfoDictionaryVersion": "6.0",
    "CFBundleName": name,
    "CFBundlePackageType": "FMWK",
    "CFBundleShortVersionString": "1.0",
    "CFBundleVersion": "1",
    "CFBundleSupportedPlatforms": ["iPhoneOS"],
    "MinimumOSVersion": "17.0",
}, open(path, "wb"))
PY

# Comprobaciones: es libretro, es arm64 de iOS y no depende de nada que no vaya en el iPhone.
nm -gU "$FW/$FRAMEWORK.libretro" | grep ' _retro_run$' >/dev/null
lipo -info "$FW/$FRAMEWORK.libretro"
otool -l "$FW/$FRAMEWORK.libretro" | grep -A4 LC_BUILD_VERSION | grep 'platform 2' >/dev/null
if otool -L "$FW/$FRAMEWORK.libretro" | tail -n +2 | grep -v -E '^[[:space:]]+(/System/Library/|/usr/lib/|@rpath/)'; then
  echo "::error::El núcleo depende de bibliotecas que no van en el iPhone (arriba)." >&2
  exit 1
fi
otool -L "$FW/$FRAMEWORK.libretro"

# Archivos de sistema del núcleo (Dolphin: Sys, de su mismo código).
if [ "$CORE" = "dolphin" ] && [ -d "$SRC/Data/Sys" ]; then
  rm -rf "$OUT/dolphin-sys"
  mkdir -p "$OUT/dolphin-sys"
  cp -R "$SRC/Data/Sys" "$OUT/dolphin-sys/Sys"
fi

du -sh "$FW"
echo "Listo: $FW"
