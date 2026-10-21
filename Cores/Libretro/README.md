# Núcleos libretro de OmniStation

Núcleos compilados por OmniStation desde su código, en vez de sacarlos de la IPA de ManicEMU.
Se compilan con el workflow **Build libretro cores** (a mano, en Actions) y se publican en la
release `libretro-cores`; el workflow de la app los descarga de ahí y los mete en `Frameworks/`.
Si un núcleo propio está, la app lo usa primero; el de ManicEMU queda como alternativa.

## JIT permanente

En iOS 26 (TXM) cada bloque nuevo de memoria de JIT tiene que prepararlo el depurador. Los
núcleos de ManicEMU piden un bloque nuevo en cada partida y sueltan el depurador justo después,
así que cada juego necesita volver a engancharlo (StikDebug o la extensión, y la VPN).

OmniStation prepara **un solo bloque de 512 MB para toda la vida de la app** (como DolphiniOS) en
cuanto tiene el depurador enganchado, y se lo reparte a los núcleos que lo piden con la llamada
estándar de libretro `RETRO_ENVIRONMENT_EXEC_MEM_ALLOC` (83) y `RETRO_ENVIRONMENT_EXEC_MEM_FREE`
(84), en modo `RETRO_EXEC_MEM_MODE_DUAL_MAP` (vista RX para ejecutar y RW para escribir). Desde ese
momento esos núcleos tienen JIT siempre, aunque el depurador se vaya.

- **Dolphin** (libretro/dolphin): ya usa esa llamada en iOS. Se compila tal cual.
- **Los demás** (melonDS DS, PPSSPP, Azahar, Beetle PSX, Mupen64Plus-Next, Flycast…): hay que
  cambiar su forma de reservar la memoria de JIT para que la pida con esa llamada. Esos cambios van
  como parches en `patches/<núcleo>/*.patch` y se añaden a `sources.json` y a `build_core.sh`.

## Añadir un núcleo

1. `sources.json`: repositorio, commit fijo (40 caracteres), nombre del framework y Bundle ID.
2. `build_core.sh`: cómo se compila para iOS arm64 (deja el `.dylib` en `BINARY`).
3. `patches/<núcleo>/`: los parches (se aplican en orden con `git apply`).
4. En la app (`RetroSupport.swift`): el núcleo en su sistema con `execMem: true`.
5. Actions → **Build libretro cores** → el núcleo. Luego, la app como siempre.
