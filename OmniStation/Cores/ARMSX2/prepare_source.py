#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Prepara la copia fijada de ARMSX2: comprueba la revisión y los archivos que toca el parche,
# y aplica el parche de NeoStation iOS (TarbleFR, GPL-3.0-or-later). Basado en
# build-utils/armsx2/prepare_source.py de NeoStation iOS.
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent


def validate_files(source: Path) -> None:
    for relative, expected in json.loads((HERE / 'upstream-files.json').read_text()).items():
        path = source / relative
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise SystemExit(f'ARMSX2 ha cambiado en {relative}: el parche no corresponde a esta revisión.')


def prepare(source: Path) -> None:
    pin = json.loads((HERE / 'source.json').read_text())
    actual = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
    if actual != pin['revision']:
        raise SystemExit(f'Se esperaba ARMSX2 {pin["revision"]} y hay {actual}')
    subprocess.run(['git', '-C', str(source), 'diff', '--exit-code'], check=True)
    validate_files(source)
    patch = str(HERE / 'neostation-core.patch')
    subprocess.run(['git', 'apply', '--check', patch], cwd=source, check=True)
    subprocess.run(['git', 'apply', patch], cwd=source, check=True)
    print(f'ARMSX2 {pin["release"]} ({pin["revision"]}) preparado con el parche de NeoStation.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path)
    prepare(parser.parse_args().source.resolve())
