#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Compila ARMSX2Core.framework (ARMSX2 iOS 2.6.0 + parche y adaptador C de NeoStation iOS).
# Uso: Cores/ARMSX2/build_core.sh <copia de ARMSX2> [ON|OFF para LTO]
# Basado en build-utils/armsx2/build_core.sh de NeoStation iOS (TarbleFR, GPL-3.0-or-later).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SOURCE="$(cd "${1:?Falta la copia de ARMSX2}" && pwd)"
LTO="${2:-ON}"
BUILD="$ROOT/build/armsx2-core"
OUTPUT="$ROOT/dist/armsx2"
REVISION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["revision"])' "$HERE/source.json")"
mkdir -p "$BUILD" "$OUTPUT"

python3 "$HERE/prepare_source.py" "$SOURCE"

# Rutas del runner fuera del binario (como hace NeoStation).
PREFIX_MAP_FLAGS="-ffile-prefix-map=$ROOT=/omnistation -fdebug-prefix-map=$ROOT=/omnistation -fmacro-prefix-map=$ROOT=/omnistation -ffile-prefix-map=$SOURCE=/armsx2 -fdebug-prefix-map=$SOURCE=/armsx2 -fmacro-prefix-map=$SOURCE=/armsx2 -ffile-prefix-map=$BUILD=/build -fdebug-prefix-map=$BUILD=/build -fmacro-prefix-map=$BUILD=/build"
export RUSTFLAGS="${RUSTFLAGS:-} --remap-path-prefix=$ROOT=/omnistation --remap-path-prefix=$SOURCE=/armsx2 --remap-path-prefix=$BUILD=/build --remap-path-prefix=$HOME/.cargo=/cargo --remap-path-prefix=$HOME/.rustup=/rust-toolchain"
export CFLAGS="${CFLAGS:-} $PREFIX_MAP_FLAGS -ffile-prefix-map=$HOME/.cargo=/cargo"
export CXXFLAGS="${CXXFLAGS:-} $PREFIX_MAP_FLAGS -ffile-prefix-map=$HOME/.cargo=/cargo"

echo "Compilando ARMSX2Core (LTO=$LTO)…"
cmake -S "$SOURCE/platforms/ios/app/src/main/cpp" -B "$BUILD" -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_C_FLAGS="$PREFIX_MAP_FLAGS" \
  -DCMAKE_CXX_FLAGS="$PREFIX_MAP_FLAGS" \
  -DCMAKE_OBJC_FLAGS="$PREFIX_MAP_FLAGS" \
  -DCMAKE_OBJCXX_FLAGS="$PREFIX_MAP_FLAGS" \
  -DARMSX2_IOS_DEPLOYMENT_TARGET=18.0 -DARMSX2_REAL_DEVICE=ON -DLTO_PCSX2_CORE="$LTO" \
  -DNEO_ARMSX2_ADAPTER_DIR="$HERE/adapter" \
  -DNEO_ARMSX2_SOURCE_REVISION="$REVISION" \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED=NO \
  2>&1 | tee "$BUILD/configure.log"
cmake --build "$BUILD" --config Release --target ARMSX2Core -- \
  -sdk iphoneos -jobs "$(sysctl -n hw.ncpu)" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  2>&1 | tee "$BUILD/compile.log" | grep -E "error:|warning: .*ARMSX2Core|\*\* BUILD" || true
if ! grep -q "\*\* BUILD SUCCEEDED \*\*" "$BUILD/compile.log"; then
  grep -E "error:" "$BUILD/compile.log" | head -40 || true
  echo "::error::No se pudo compilar ARMSX2Core."
  exit 1
fi
python3 "$HERE/verify_core.py" "$BUILD" "$OUTPUT" "$SOURCE" "$LTO"
