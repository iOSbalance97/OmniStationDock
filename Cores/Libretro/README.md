# Núcleos libretro de OmniStation

Todos los núcleos integrados de la app los compila OmniStation desde su código (desde la 0.9.0 ya
no se usa nada de la IPA de ManicEMU). Se compilan con el workflow **Build libretro cores** (a mano,
en Actions) y se publican en la release `libretro-cores`; el workflow de la app los descarga de ahí
y los mete en `Frameworks/`. MoltenVK (Vulkan para 3DS y GameCube/Wii) sale de su release oficial.

| Sistema | JIT permanente | Sin JIT |
|---|---|---|
| NES | — | Nestopia |
| SNES | — | Snes9x |
| Game Boy / Color | — | Gambatte, mGBA |
| GBA | — | mGBA, gpSP, VBA-M |
| NDS | melonDS DS | DeSmuME |
| PS1 | PCSX ReARMed | Beetle PSX HW |
| N64 | Mupen64Plus-Next | — |
| PSP | PPSSPP | — |
| Dreamcast | Flycast | Flycast sin JIT (cuando no hay JIT) |
| 3DS | Azahar | — |
| GameCube / Wii | Dolphin | — |

Los sin JIT se compilan todos a la vez con la opción `sin_jit_todos` del workflow. gpSP y Beetle
PSX tienen recompilador, pero en iOS su Makefile lo deja fuera (escriben y ejecutan en la misma
dirección): van como intérprete hasta que tengan un parche como el de los demás.

## JIT permanente

En iOS 26 (TXM) cada bloque nuevo de memoria de JIT tiene que prepararlo el depurador. Un núcleo
normal pide un bloque nuevo en cada partida y suelta el depurador justo después, así que cada juego
necesitaría volver a engancharlo (StikDebug o la extensión, y la VPN).

OmniStation prepara **un solo bloque de 512 MB para toda la vida de la app** (como DolphiniOS) en
cuanto tiene el depurador enganchado, y se lo reparte a los núcleos que lo piden con la llamada
estándar de libretro `RETRO_ENVIRONMENT_EXEC_MEM_ALLOC` (83) y `RETRO_ENVIRONMENT_EXEC_MEM_FREE`
(84), en modo `RETRO_EXEC_MEM_MODE_DUAL_MAP` (vista RX para ejecutar y RW para escribir). Desde ese
momento esos núcleos tienen JIT siempre, aunque el depurador se vaya.

- **Dolphin** (libretro/dolphin): ya usa esa llamada en iOS. Se compila tal cual.
- **Azahar** (3DS): `patches/azahar` hace que oaknut (la memoria de código de dynarmic y del JIT de
  sombreadores) la pida con esa llamada y escriba por la vista RW. Sin ella, intérprete.
  `0002` le devuelve las ROMs cifradas (como Citra): descifra al vuelo con las claves del usuario
  (`aes_keys.txt` o `keys.txt`, y `seeddb.bin`), que la app copia de 3DS/BIOS a
  `Partidas/Azahar/sysdata`. Sin claves, la app avisa de lo que falta.
- **melonDS DS** (NDS): `patches/melondsds` (frontend) y `patches/melondsds/melonDS` (el JIT de
  melonDS escribe por la vista RW y ejecuta por la RX, como ya hacía en Switch).
- **PCSX ReARMed** (PS1): `patches/pcsx_rearmed` activa en iOS su dynarec con la memoria en doble
  vista (`TC_WRITE_OFFSET`, el modo de Switch). Beetle PSX no: su dynarec (Lightrec con GNU
  Lightning) escribe y ejecuta en la misma dirección.
- **PPSSPP, Mupen64Plus-Next y Flycast**: sus parches en `patches/<núcleo>/` hacen que pidan la
  memoria con esa llamada y escriban por la vista RW (como en Switch).

## Añadir un núcleo

1. `sources.json`: repositorio, commit fijo (40 caracteres), nombre del framework y Bundle ID.
2. `build_core.sh`: cómo se compila para iOS arm64 (deja el `.dylib` en `BINARY`).
3. `patches/<núcleo>/`: los parches (se aplican en orden con `patch -p1`).
4. `.github/workflows/libretro-cores.yml`: el núcleo en la lista (y en `sin_jit_todos` si no usa JIT).
5. En la app (`RetroSupport.swift`): el núcleo en su sistema (con `execMem: true` si usa el JIT
   permanente).
5. Actions → **Build libretro cores** → el núcleo. Luego, la app como siempre.
