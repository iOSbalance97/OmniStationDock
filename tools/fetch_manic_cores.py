#!/usr/bin/env python3
# Saca los núcleos libretro de la IPA de ManicEMU y los deja en <salida>/<nombre>.libretro.framework
# con un cores.json. ManicEMU es AGPL-3.0 (https://github.com/Manic-EMU/ManicEMU); cada núcleo tiene
# su licencia (THIRD_PARTY_NOTICES.md de ManicEMU). OmniStation solo los empaqueta tal cual.
#
# Uso: fetch_manic_cores.py <salida> <carpeta con la IPA (o la IPA)>
# Si no se encuentra nada, borra <salida> y avisa: la app se compila sin esos núcleos.
from __future__ import annotations
import json
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile

# Fase 1: los que van sin JIT ni GPU propia (NES, SNES, Game Boy, GBA y NDS).
WANTED = [
    'nestopia', 'snes9x', 'gambatte', 'mgba', 'gpsp', 'vbam', 'melondsds', 'desmume',
]
MACHO_MAGICS = {b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca'}


def warn(message):
    print(f'::warning::{message}', flush=True)


def pick_ipa(source: Path) -> Path | None:
    if source.is_file():
        return source
    ipas = sorted(source.glob('*.ipa'))
    if not ipas:
        return None
    # La de sideload trae el JIT propio; si no se distingue, la más grande.
    for ipa in ipas:
        if 'side' in ipa.name.lower():
            return ipa
    return max(ipas, key=lambda path: path.stat().st_size)


def rpath_dependencies(binary: Path) -> list[str]:
    """Dependencias @rpath/… de un binario (otool, solo en macOS). Vacío si no hay otool."""
    try:
        text = subprocess.check_output(['otool', '-L', str(binary)], text=True, stderr=subprocess.DEVNULL)
    except Exception:  # noqa: BLE001
        return []
    found = []
    for line in text.splitlines()[1:]:
        path = line.strip().split(' ', 1)[0]
        if path.startswith('@rpath/'):
            found.append(path[len('@rpath/'):])
    return found


def extract_item(archive: zipfile.ZipFile, names: list[str], frameworks: str, item: str, output: Path) -> bool:
    """Copia de Frameworks/ de la IPA un .framework o un .dylib (por su ruta dentro de Frameworks)."""
    top = item.split('/', 1)[0]
    prefix = frameworks + top
    entries = [name for name in names if name == prefix or name.startswith(prefix + '/')]
    if not entries:
        return False
    for name in entries:
        if name.endswith('/'):
            continue
        destination = output / name[len(frameworks):]
        destination.parent.mkdir(parents=True, exist_ok=True)
        with archive.open(name) as src, open(destination, 'wb') as dst:
            shutil.copyfileobj(src, dst)
    return True


def main() -> int:
    output = Path(sys.argv[1])
    source = Path(sys.argv[2])
    ipa = pick_ipa(source)
    if ipa is None:
        warn('No hay IPA de ManicEMU: la app va sin sus núcleos.')
        shutil.rmtree(output, ignore_errors=True)
        return 0
    print(f'IPA de ManicEMU: {ipa.name}', flush=True)
    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)
    found = {}
    with zipfile.ZipFile(ipa) as archive:
        names = archive.namelist()
        for core in WANTED:
            folder = f'{core}.libretro.framework/'
            entries = [name for name in names if name.startswith('Payload/') and f'/{folder}' in name]
            if not entries:
                warn(f'La IPA no trae {core}.libretro.framework')
                continue
            prefix = entries[0][:entries[0].index(f'/{folder}') + 1]
            target = output / folder.rstrip('/')
            for name in entries:
                if not name.startswith(prefix + folder) or name.endswith('/'):
                    continue
                relative = name[len(prefix):]
                destination = output / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                with archive.open(name) as src, open(destination, 'wb') as dst:
                    shutil.copyfileobj(src, dst)
            binary = target / f'{core}.libretro'
            info = target / 'Info.plist'
            if info.exists():
                try:
                    import plistlib
                    executable = plistlib.loads(info.read_bytes()).get('CFBundleExecutable')
                    if executable:
                        binary = target / executable
                except Exception:
                    pass
            if not binary.exists() or binary.read_bytes()[:4] not in MACHO_MAGICS:
                warn(f'{core}: el binario no es válido; se quita')
                shutil.rmtree(target, ignore_errors=True)
                continue
            binary.chmod(0o755)
            found[core] = {'framework': target.name, 'bytes': binary.stat().st_size}
            print(f'  {target.name}: {binary.stat().st_size // 1024} KB', flush=True)
            # Lo que el núcleo necesita de Frameworks/ (si enlaza con otra librería de la IPA).
            pending = rpath_dependencies(binary)
            seen = set()
            while pending:
                dependency = pending.pop()
                top = dependency.split('/', 1)[0]
                if top in seen or top == target.name:
                    continue
                seen.add(top)
                if (output / top).exists():
                    continue
                if extract_item(archive, names, prefix, dependency, output):
                    print(f'    + {top}', flush=True)
                    extra = output / dependency
                    if extra.exists():
                        pending += rpath_dependencies(extra)
                else:
                    warn(f'{core} necesita {dependency} y no está en la IPA')
    if not found:
        warn('No se sacó ningún núcleo de ManicEMU.')
        shutil.rmtree(output, ignore_errors=True)
        return 0
    (output / 'cores.json').write_text(json.dumps({'source': ipa.name, 'cores': found}, indent=2))
    print(f'Núcleos listos: {len(found)} de {len(WANTED)}', flush=True)
    return 0


if __name__ == '__main__':
    sys.exit(main())
