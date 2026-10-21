#!/usr/bin/env python3
# Saca el «runtime» de MeloNX 2.7 (núcleo Ryujinx.Library + MoltenVK, SDL3, FFmpeg y BreakpointJIT)
# de la IPA oficial y lo deja en <salida>/Frameworks con un MeloNXRuntime.json.
#
# MeloNX es AGPL-3.0 (https://melonx.org); Ryujinx, MIT. OmniStation solo lo empaqueta tal cual.
#
# Uso: fetch_melonx_runtime.py <salida> [ipa local]
# Variables:
#   MELONX_API       API de versiones (Forgejo/GitHub, mismo formato).
#   MELONX_TAG       Versión concreta (vacío: la más reciente que traiga IPA).
#   MELONX_REQUIRED  "1": falla si no se consigue; si no, avisa y sigue sin MeloNX.
#   NM, OTOOL        Herramientas (por defecto, las de Xcode).
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request
import zipfile

API = os.environ.get('MELONX_API', 'https://starforgejo.dev/api/v1/repos/projects/MeloNX/releases?limit=20')
TAG = os.environ.get('MELONX_TAG', '').strip()
REQUIRED = os.environ.get('MELONX_REQUIRED', '') == '1'
NM = os.environ.get('NM', 'nm')
OTOOL = os.environ.get('OTOOL', 'otool')

# Lo que OmniStation llama del núcleo de MeloNX 2.7 (ver OSMeloNXEngine.m). Si falta alguno, no se empaqueta.
REQUIRED_EXPORTS = [
    '_initialize', '_main_ryujinx_sdl', '_set_native_window', '_stop_emulation', '_init_dualmapping',
    '_install_firmware', '_installed_firmware_version', '_free_firmware_version',
    '_attach_gamepad', '_detach_gamepad', '_set_gamepad_button_state', '_set_gamepad_stick_axis',
    '_touch_began', '_touch_moved', '_touch_ended', '_set_view_size',
]
OPTIONAL_EXPORTS = ['_toggle_pause_emulation', '_load_keyset', '_set_unbounded_present_target_fps',
                    '_report_memory_pressure', '_set_gamepad_motion_axis', '_get_game_info', '_free_game_info']
# Lo que OmniStation carga antes del núcleo (MeloNX 2.7: SDL3, MoltenVK y BreakpointJIT).
REQUIRED_HELPERS = ['SDL3.framework/SDL3', 'BreakpointJIT.framework/BreakpointJIT', 'libMoltenVK.dylib']
# Nombre del núcleo en MeloNX 2.7 (si cambia, se busca el que exporte main_ryujinx_sdl).
CORE_NAME = 'Ryujinx.Library.dylib'


class Failure(Exception):
    pass


def log(message):
    print(message, flush=True)


def warn(message):
    print(f'::warning::{message}', flush=True)


def http_get(url, binary=False, attempts=4):
    last = None
    for attempt in range(attempts):
        try:
            request = urllib.request.Request(url, headers={'User-Agent': 'OmniStationDock-CI', 'Accept': '*/*'})
            with urllib.request.urlopen(request, timeout=120) as response:
                data = response.read()
                return data if binary else data.decode('utf-8')
        except Exception as error:  # noqa: BLE001 - se reintenta cualquier fallo de red
            last = error
            time.sleep(3 * (attempt + 1))
    raise Failure(f'No se pudo descargar {url}: {last}')


def pick_release():
    releases = json.loads(http_get(API))
    if not isinstance(releases, list):
        raise Failure('La API de MeloNX no devolvió una lista de versiones.')
    candidates = []
    for release in releases:
        if release.get('draft'):
            continue
        ipas = [a for a in release.get('assets', []) if str(a.get('name', '')).lower().endswith('.ipa')]
        if not ipas:
            continue
        if TAG and release.get('tag_name') != TAG:
            continue
        candidates.append((bool(release.get('prerelease')), release, ipas))
    if not candidates:
        raise Failure('No hay ninguna versión de MeloNX con IPA' + (f' con la etiqueta {TAG}.' if TAG else '.'))
    # Preferir versiones estables; dentro de cada grupo, la más reciente (la API las da en orden).
    candidates.sort(key=lambda item: item[0])
    _, release, ipas = candidates[0]
    # Si hay varias IPA, la que se llame MeloNX.ipa (y si no, la primera).
    ipas.sort(key=lambda a: (a.get('name') != 'MeloNX.ipa', a.get('name')))
    asset = ipas[0]
    return release.get('tag_name', ''), asset['browser_download_url'], asset.get('name', '')


def run(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL)


def exports_of(path):
    try:
        return set(run(NM, '-gU', str(path)).split())
    except Exception:  # noqa: BLE001 - no es Mach-O o no se puede leer
        return set()


def is_macho(path):
    try:
        with open(path, 'rb') as handle:
            magic = handle.read(4)
    except OSError:
        return False
    return magic in (b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca')


def dylibs_used(path):
    try:
        lines = run(OTOOL, '-L', str(path)).splitlines()[1:]
    except Exception:  # noqa: BLE001
        return []
    return [line.strip().split(' ', 1)[0] for line in lines if line.strip()]


def extract(ipa, destination):
    with zipfile.ZipFile(ipa) as archive:
        names = archive.namelist()
        apps = sorted({n.split('/')[1] for n in names if n.startswith('Payload/') and n.count('/') >= 2
                       and n.split('/')[1].endswith('.app')})
        if len(apps) != 1:
            raise Failure(f'La IPA de MeloNX no tiene una sola app: {apps}')
        prefix = f'Payload/{apps[0]}/Frameworks/'
        members = [n for n in names if n.startswith(prefix) and not n.endswith('/')]
        if not members:
            raise Failure('La IPA de MeloNX no trae Frameworks.')
        for name in members:
            relative = name[len(prefix):]
            top = relative.split('/', 1)[0]
            # Las librerías de Swift ya están en iOS 17; las .a (estáticas) no sirven en la app.
            if top.startswith('libswift') or relative.endswith('.a'):
                continue
            target = destination / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(name) as source, open(target, 'wb') as output:
                shutil.copyfileobj(source, output)
            info = archive.getinfo(name)
            mode = (info.external_attr >> 16) & 0o777
            os.chmod(target, mode or 0o644)
        return apps[0]


def find_core(frameworks):
    preferred = frameworks / CORE_NAME
    if preferred.is_file() and '_main_ryujinx_sdl' in exports_of(preferred):
        return preferred
    for path in sorted(frameworks.rglob('*')):
        if not path.is_file() or path.is_symlink() or not is_macho(path):
            continue
        if '_main_ryujinx_sdl' in exports_of(path):
            return path
    raise Failure('No se encontró el núcleo de MeloNX (nada exporta main_ryujinx_sdl).')


def main():
    if len(sys.argv) < 2:
        raise SystemExit('Uso: fetch_melonx_runtime.py <salida> [ipa local]')
    output = Path(sys.argv[1]).resolve()
    local_ipa = Path(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[2] else None
    if output.exists():
        shutil.rmtree(output)
    work = Path(tempfile.mkdtemp(prefix='melonx-'))
    try:
        if local_ipa and local_ipa.is_file():
            ipa, tag, url = local_ipa, os.environ.get('MELONX_LOCAL_TAG', 'repo'), 'release melonx-runtime'
            log(f'Usando la IPA de MeloNX de este repositorio ({local_ipa.name}).')
        else:
            tag, url, name = pick_release()
            log(f'MeloNX {tag}: {name}')
            ipa = work / 'MeloNX.ipa'
            ipa.write_bytes(http_get(url, binary=True))
        digest = hashlib.sha256(ipa.read_bytes()).hexdigest()
        log(f'IPA de MeloNX: {ipa.stat().st_size} bytes, SHA-256 {digest}')

        staging = work / 'Frameworks'
        app_name = extract(ipa, staging)
        core = find_core(staging)
        exports = exports_of(core)
        # Lista completa en el log (sirve para adaptar OmniStation a versiones nuevas de MeloNX).
        log('Funciones del núcleo: ' + ' '.join(sorted(s[1:] for s in exports if s.startswith('_') and not s.startswith('_$'))[:400]))
        missing = [symbol for symbol in REQUIRED_EXPORTS if symbol not in exports]
        if missing:
            raise Failure('El núcleo de MeloNX no tiene lo que usa OmniStation: ' + ', '.join(missing))
        for helper in REQUIRED_HELPERS:
            if not (staging / helper).is_file():
                raise Failure(f'Falta {helper} en la IPA de MeloNX.')
        unresolved = []
        for dependency in dylibs_used(core):
            if dependency.startswith('@rpath/'):
                relative = dependency[len('@rpath/'):]
                if relative != core.relative_to(staging).as_posix() and not (staging / relative).exists():
                    unresolved.append(dependency)
        if unresolved:
            raise Failure('El núcleo de MeloNX depende de algo que no viene en la IPA: ' + ', '.join(unresolved))

        output.mkdir(parents=True)
        shutil.move(str(staging), str(output / 'Frameworks'))
        files = sorted(p.relative_to(output / 'Frameworks').as_posix()
                       for p in (output / 'Frameworks').rglob('*') if p.is_file())
        top_level = sorted({f.split('/', 1)[0] for f in files})
        size = sum((output / 'Frameworks' / f).stat().st_size for f in files)
        manifest = {
            'schema': 2,
            'version': tag,
            'app': app_name,
            'source': url,
            'sha256': digest,
            'core': core.relative_to(staging).as_posix(),
            'items': top_level,
            'files': len(files),
            'bytes': size,
            'optionalExports': [s for s in OPTIONAL_EXPORTS if s in exports],
        }
        (output / 'MeloNXRuntime.json').write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + '\n')
        log(json.dumps(manifest, indent=2, ensure_ascii=False))
        log(f'Runtime de MeloNX listo: {len(top_level)} librerías, {size // (1024 * 1024)} MB.')
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == '__main__':
    # --latest-tag: solo dice qué versión se bajaría (para la clave de la caché del workflow).
    if len(sys.argv) > 1 and sys.argv[1] == '--latest-tag':
        try:
            print(pick_release()[0])
        except Exception:  # noqa: BLE001
            print('')
        sys.exit(0)
    try:
        main()
    except Exception as failure:  # noqa: BLE001 - nunca rompe la compilación de la app
        if REQUIRED:
            print(f'::error::{failure}', flush=True)
            sys.exit(1)
        warn(f'{failure} La app se compila sin MeloNX integrado.')
        output_dir = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else None
        if output_dir and output_dir.exists():
            shutil.rmtree(output_dir, ignore_errors=True)
        sys.exit(0)
