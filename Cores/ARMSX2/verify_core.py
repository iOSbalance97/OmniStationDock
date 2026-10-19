#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Comprueba el ARMSX2Core.framework recién compilado y lo copia a dist/ con su identity.json.
# Basado en build-utils/armsx2/verify_core.py de NeoStation iOS (TarbleFR, GPL-3.0-or-later).
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

here = Path(__file__).resolve().parent
build, output, source = map(Path, sys.argv[1:4])
lto = len(sys.argv) > 4 and sys.argv[4] == 'ON'


def run(*args):
    return subprocess.check_output(args, text=True)


def has_defined_symbol(symbols, symbol):
    return any(line.split()[-1:] == [symbol] and ' U ' not in line for line in symbols.splitlines())


candidates = [p for p in build.rglob('ARMSX2Core.framework')
              if (p / 'ARMSX2Core').is_file() and 'Release-iphoneos' in str(p)]
if len(candidates) != 1:
    raise SystemExit(f'Se esperaba un único framework de dispositivo y hay: {candidates}')
framework = candidates[0]
binary = framework / 'ARMSX2Core'

leaks = sorted({s.decode('utf-8', errors='replace') for s in binary.read_bytes().split(b'\0') if b'/Users/runner/' in s})
if leaks:
    print(f'::warning::El núcleo contiene {len(leaks)} rutas del runner (solo informativo).')

if run('lipo', '-archs', str(binary)).strip() != 'arm64':
    raise SystemExit('El núcleo no es exactamente arm64')
if 'DYLIB' not in run('otool', '-hv', str(binary)):
    raise SystemExit('El núcleo no es una librería dinámica')
exports = set(run('nm', '-gUj', str(binary)).splitlines())
if exports != {'_NeoARMSX2_GetAPI'}:
    raise SystemExit(f'Exporta símbolos inesperados: {sorted(exports)}')
for line in run('otool', '-L', str(binary)).splitlines()[1:]:
    library = line.strip().split(' ', 1)[0]
    if library == '@rpath/ARMSX2Core.framework/ARMSX2Core':
        continue
    if not library.startswith(('/usr/lib/', '/System/Library/')):
        raise SystemExit(f'Depende de algo que no es del sistema: {library}')
for required in ('default.metallib', 'GameIndex.yaml', 'game_controller_db.txt', 'Info.plist'):
    if not (framework / required).is_file():
        raise SystemExit(f'Falta en el framework: {required}')
symbols = run('nm', str(binary))
for symbol in ('_libra_mtl_filter_chain_create', '_libra_mtl_filter_chain_frame'):
    if not has_defined_symbol(symbols, symbol):
        raise SystemExit('Falta el motor de shaders (librashader): ' + symbol)
if len(list(framework.glob('shaders/presets/**/*.slangp'))) < 10:
    raise SystemExit('No se empaquetaron los presets de shaders de iOS')

abi_header = (here / 'adapter/ios/Classes/ARMSX2CoreABI.h').read_text()
match = re.search(r'#define\s+NEO_ARMSX2_ABI_VERSION\s+(\d+)u', abi_header)
identity = json.loads((here / 'source.json').read_text())
if not match or int(match.group(1)) != identity.get('abi_version'):
    raise SystemExit('La versión de la interfaz C no coincide con source.json')

subprocess.run(['codesign', '--force', '--sign', '-', str(framework)], check=True)
subprocess.run(['codesign', '--verify', '--strict', str(framework)], check=True)
output.mkdir(parents=True, exist_ok=True)
destination = output / framework.name
if destination.exists():
    shutil.rmtree(destination)
subprocess.run(['ditto', str(framework), str(destination)], check=True)

identity.update(
    builder='OmniStation Dock',
    lto=lto,
    commit=os.environ.get('GITHUB_SHA', ''),
    sha256=hashlib.sha256((destination / 'ARMSX2Core').read_bytes()).hexdigest(),
    files=sum(1 for p in destination.rglob('*') if p.is_file()),
)
(output / 'identity.json').write_text(json.dumps(identity, indent=2) + '\n')
print(json.dumps(identity, indent=2))
