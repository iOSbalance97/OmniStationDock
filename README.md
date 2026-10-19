# OmniStation Dock — versión 0.4.0

Lanzador de juegos y emuladores para iPhone con interfaz espacial/Liquid Glass, control completo con mando y **Modo Dock** (carrusel en horizontal, también al conectar HDMI).

## Funciones
- Inicio, Favoritos, Búsqueda y Ajustes, con filtros por plataforma (incluidas Juegos iOS, Ports y las tuyas).
- Biblioteca: carpeta externa con ROMs de todas las plataformas, accesos directos (URL, app iOS por Bundle ID con StikDebug, o LiveContainer) y carátulas.
- **Pantalla del juego**: al elegir un juego (✕ o toque) se abre su ficha con los botones **Jugar** y **Opciones**; arriba, volver (también ○) y favorito. En vertical: carátula, nombre, plataforma y descripción (de Wikipedia, en tu idioma). En horizontal (con y sin Dock): una imagen del juego de fondo a pantalla completa (banner de la eShop en Switch; captura del juego de libretro-thumbnails en el resto; se guarda en el iPhone), el nombre centrado y los botones debajo; la descripción se abre con su botón, al lado del de favorito.
- Por juego: cambiar nombre, carátula (Descargar, Importar foto o Importar archivo) y plataforma, favoritos, logros de RetroAchievements, mapa de botones y **abrir con JIT**.
- Mando (DualSense, Xbox…): cruceta (mantener = repetir), ✕ elegir, △ opciones, ○ atrás, □ borrar letra en los teclados, L1/R1 plataforma, L2/R2 pestaña.
- Reorganizar plataformas: orden y un interruptor por plataforma. Encendida sale siempre en la barra (también las de la carpeta externa sin juegos) y apagada nunca; sin tocarla, las de la carpeta externa salen solo cuando tienen juegos.
- Fondo: animado predeterminado, original estático, imagen propia o vídeo propio. Sonidos con volumen propio.

## JIT
La app **detecta sola** cómo se instaló (dentro de LiveContainer o con SideStore/AltStore). Ajustes → Depuración → Método de instalación solo informa del método detectado y de lo que ofrece frente al otro.

### LiveContainer + StikDebug
1. En LiveContainer → Ajustes, elige **StikDebug** como activador de JIT.
2. Si OmniStation también está dentro de LiveContainer, al abrir un juego con JIT hace lo mismo que LiveContainer desde su lista: deja apuntada la app (y el juego que debe abrir) y pide a StikDebug que relance LiveContainer con el JIT. Usa el script de JIT que tenga puesto esa app en sus ajustes de LiveContainer. Funciona con el activador StikDebug o SideStore de LiveContainer.
3. Añade los juegos como acceso directo de tipo *LiveContainer* (pega su enlace de lanzamiento o escribe su carpeta, `com.empresa.juego.app`).

### SideStore / AltStore + StikJIT integrado (sin StikDebug)
OmniStation lleva dentro **StikJIT** (MPL-2.0) y abre las apps con el depurador ella misma.
1. Crea el archivo de emparejamiento con **iloader** en un ordenador (Manage Pairing File, iPhone por cable). Tiene que ser del tipo **RPPairing**; el antiguo de SideStore ya no sirve.
2. Ajustes → Depuración → **Archivo de emparejamiento** → Importar (o déjalo en Archivos → En mi iPhone → OmniStation Dock).
3. Activa el **Modo desarrollador** y la VPN **LocalDevVPN** (mejor con Wi‑Fi).
4. No hay que hacer nada más: al abrir la app (y al volver a ella) OmniStation comprueba la VPN y monta la imagen de desarrollador por sí sola (la primera vez se descarga, unos 20 MB). Su estado se ve en Ajustes → Depuración → **JIT integrado**.
5. En las opciones de cada juego: *Elegir app instalada* (lista las apps de SideStore/AltStore con su Bundle ID) y, si hace falta, *Script JIT* (Automático, Universal o Legacy; solo cuenta con TXM en iOS 26).
6. Al pulsar el juego, OmniStation lo abre con JIT. Si algo falla, el motivo exacto aparece al volver a OmniStation.

También puedes elegir **App StikDebug** en *Activador de JIT* si prefieres seguir usándola.

Requisitos del JIT integrado: iOS 17.4 o posterior, apps instaladas con SideStore/AltStore (con `get-task-allow`), no funciona dentro de LiveContainer.

## Emuladores (ARMSX2 y MeloNX)
La primera vez (y en Ajustes → Juegos → Emuladores) la app pregunta qué emuladores tienes y la **carpeta de juegos de cada uno**: elige la misma que uses dentro del emulador. Sus juegos aparecen en OmniStation y se abren directamente en él con JIT. La carpeta externa general sigue existiendo para el resto.

| Emulador | Plataforma | Enlace que usa | Carpeta en LiveContainer por defecto |
|---|---|---|---|
| ARMSX2 | PS2 | `armsx2://launch?game=<archivo>` | `com.armsx2.ios.app` |
| MeloNX | Switch | `melonx://game?id=<Title ID>` o `?name=<título>` | `com.stossy11.MeloNX.app` |

- **MeloNX** abre un juego por su Title ID o por su título exacto (con tildes y todo). OmniStation usa, por orden: lo que pongas en *Nombre en MeloNX* (opciones del juego), el Title ID si el archivo lo lleva entre corchetes (`Juego [0100XXXXXXXXXXXX].nsp`) o el nombre del juego. Con MeloNX instalado aparte, *Leer biblioteca de MeloNX* (y al vincular su carpeta) le pide su lista de juegos (`melonx://gameInfo`), empareja cada archivo con su título aunque se escriba distinto (por ejemplo «Super Mario Wonder» con «Super Mario Bros. Wonder») y usa sus iconos como carátulas. Dentro de LiveContainer MeloNX no puede devolver esa lista: usa *Nombre en MeloNX* si un juego no arranca.
- **ARMSX2** abre un juego por su nombre de archivo. Con ARMSX2 instalado aparte, *Leer biblioteca de ARMSX2* (y automáticamente al encontrar juegos nuevos) le pide su lista (`armsx2://library`, ARMSX2 pide confirmación), usa el título real de cada juego como nombre (salvo los renombrados a mano) y vuelve a buscar su carátula con ese nombre. Nunca se piden las dos bibliotecas a la vez: primero MeloNX y, al volver, ARMSX2.
- **En LiveContainer**: un toque abre el emulador con JIT (pidiéndolo como hace LiveContainer) y arranca el juego.
- **SideStore/AltStore + JIT integrado**: MeloNX se abre con el juego y espera al JIT; OmniStation se lo da en segundo plano y el juego arranca solo. ARMSX2 no espera al JIT: la primera vez se abre con JIT y hay que volver y pulsar el juego otra vez (mientras siga abierto, arranca al momento).
- **Con la app StikDebug**: OmniStation abre el juego y el emulador pide el JIT a StikDebug por su cuenta.
- **Versiones nuevas** (cada emulador por separado, como mucho cada 6 h): ARMSX2 desde GitHub (solo las *nightly* traen IPA de iOS) y MeloNX desde su servidor Forgejo. La IPA se manda a LiveContainer o a SideStore/AltStore, que la instalan tras confirmar.

## ARMSX2 integrado (PS2 dentro de OmniStation)
Desde la 0.4.0 hay tres formas de jugar a PS2, separadas por completo (cada una con sus juegos y sus ajustes; ninguna depende de otra):

| Forma | Dónde están los juegos | JIT |
|---|---|---|
| App ARMSX2 en LiveContainer | La carpeta de juegos de ARMSX2 que vincules | LiveContainer + StikDebug |
| App ARMSX2 instalada con SideStore | La carpeta de juegos de ARMSX2 que vincules | JIT integrado / StikDebug |
| **Núcleo integrado en OmniStation** | `ARMSX2/Juegos` dentro de OmniStation | **Extensión de JIT propia** |

Se elige en Ajustes → ARMSX2 → *Modo de ARMSX2*. Cada modo enseña en Ajustes solo lo suyo. El integrado solo existe fuera de LiveContainer (las extensiones de iOS no corren dentro).

**Carpeta propia** (Archivos → En mi iPhone → OmniStation Dock → `ARMSX2`):
- `Juegos/`: ISO, CHD, CSO, ZSO, GZ, ELF… (también en subcarpetas). Se leen solos al abrir la app; *Importar juegos* los copia desde Archivos.
- `BIOS/`: tu BIOS de PS2 (Ajustes → ARMSX2 integrado → BIOS la importa).
- `Datos/`: lo crea el núcleo: tarjetas de memoria (`Saves/Memory Cards`), estados (`Saves/Savestates`), texturas, trucos, parches, ajustes por juego, caché, capturas y registros.

**Cómo consigue el JIT** (la técnica de NeoStation iOS): una app no puede ser su propio depurador, así que OmniStation lleva una extensión invisible (`OmniStationJITHelper.appex`) que iOS ejecuta como proceso aparte. OmniStation le pasa su PID y el archivo RPPairing por un puerto local; la extensión engancha StikJIT a OmniStation por LocalDevVPN. En iOS 26 una instrucción de prueba con una clave comprueba que el depurador responde y solo entonces se carga el núcleo (`dlopen`); después el núcleo prepara su memoria ejecutable y pide soltar el depurador. Antes de iOS 26 basta con enganchar y soltar.

**Requisitos**: OmniStation instalada con SideStore/AltStore **sin quitarle sus extensiones**, iOS 18+, Modo desarrollador, archivo RPPairing, VPN LocalDevVPN y tu BIOS.

**Durante la partida**: el mando lo lee el propio núcleo. Mando táctil como el de ARMSX2 (cruceta, botones, dos sticks, L1/L2/R1/R2, START/SELECT), oculto con un mando conectado salvo que actives *Controles táctiles siempre*. Menú de pausa con el botón ☰, el botón Home del mando o SELECT+START: continuar, ranura 1–5, guardar y cargar estado, controles táctiles y salir.

**El núcleo** (dos versiones, se elige en Ajustes → ARMSX2 integrado → *Versión del núcleo*):
- **NeoStation**: `ARMSX2Core.framework` (ARMSX2 iOS 2.6, interfaz C versión 6) compilado por NeoStation iOS 0.0.8. El workflow lo saca de su IPA pública y comprueba la huella del binario y de todos sus archivos.
- **OmniStation**: `ARMSX2CoreOmni.framework`, el mismo ARMSX2 2.6 con el parche y el adaptador de NeoStation (en `Cores/ARMSX2`), compilado por nosotros con **LTO** (como la app oficial de ARMSX2; NeoStation lo compila sin LTO). Se compila con el workflow **Build ARMSX2 core** (`armsx2-core.yml`, a mano, 40–90 min) y se publica como release `armsx2-core`; el workflow de la app lo descarga de ahí si existe.

Un núcleo cargado no se descarga: si cambias de versión, se usa al volver a abrir OmniStation.

## MeloNX integrado (Switch dentro de OmniStation)
Se elige en Ajustes → MeloNX → *Modo de MeloNX*. Solo fuera de LiveContainer (SideStore/AltStore), iOS 18+.

- **Runtime**: el workflow descarga la IPA oficial de MeloNX (su servidor Forgejo) y copia a `Frameworks/` su núcleo Ryujinx compilado y sus librerías (MoltenVK, SDL2, FFmpeg, RyujinxHelper, BreakpointJIT…), con `MeloNXRuntime.json`. Si subes tu propia `MeloNX.ipa` como release `melonx-runtime` de este repo, se usa esa. Si no se consigue, la app compila igual sin MeloNX integrado.
- **Anfitrión propio** (`OmniStation/Core/OSMeloNXEngine.m`): carga el runtime, activa el JIT con la extensión de OmniStation (script universal de StikDebug en iOS 26), crea la pantalla (CAMetalLayer 16:9), pasa el mando y la pantalla táctil y arranca el juego. Menú con Home o SELECT+START: continuar o salir.
- **Juegos**: Archivos → OmniStation Dock → `MeloNX/Juegos` (NSP, XCI, NRO, NCA).
- **Claves y firmware**: Ajustes → MeloNX integrado → *Claves* (prod.keys, title.keys) y *Firmware* (zip). Ryujinx guarda sus datos (`system`, `bis`, `sdcard`, `games`…) en la raíz de OmniStation Dock.
- **Registro**: `MeloNX/Registro.txt` (lo que escribe el núcleo en la última partida).
- **Memoria**: la IPA pide `com.apple.developer.kernel.increased-memory-limit` (se añade con `ldid` al empaquetar). Para que iOS lo conceda, usa la app **GetMoreRam** para añadir «Increased Memory Limit» al App ID de OmniStation y refresca la app en SideStore. Ajustes → MeloNX integrado → *Memoria* indica si está activo y cuánta memoria queda libre.

## Carátulas automáticas
Para los juegos sin carátula, OmniStation busca la suya en la colección pública **libretro-thumbnails** (PS1, PS2, PSP, GB/GBC/GBA, NDS, 3DS, NES, SNES, N64, GameCube, Wii, Mega Drive, Master System, Game Gear, Dreamcast y Saturn) y la descarga sola, emparejando por nombre y prefiriendo la región de tu idioma. En Switch usa los iconos de MeloNX (instalado aparte) o, dentro de LiveContainer, el icono de la eShop (api.nlib.cc, si el archivo lleva el Title ID) o la portada del artículo de Wikipedia. Si un juego no está en libretro-thumbnails, *Descargar* prueba también con Wikipedia. Las carátulas que elijas a mano nunca se sustituyen. En las opciones del juego, *Cambiar carátula* → **Descargar** la busca en ese momento (en Switch con MeloNX aparte, se la pide a MeloNX; dentro de LiveContainer, el icono de la eShop por su Title ID o la portada de Wikipedia), **Importar foto** abre la galería e **Importar archivo** abre Archivos. Se activa o desactiva en Ajustes → Juegos → Carátulas automáticas.

## Cerrar al abrir un juego
Con *Cerrar al abrir un juego* (Ajustes → General, activado por defecto), OmniStation se cierra en cuanto el juego está abierto (con el JIT integrado, cuando ha terminado de dárselo), para que no se quede detrás.

## Indicador de JIT
En horizontal, un punto verde o rojo indica si el JIT funciona ahora mismo: en LiveContainer, si OmniStation corre con JIT (lo mismo que *Estado JIT*); con SideStore y el JIT integrado, si está listo para dárselo a los juegos (en el Modo Dock, entre la batería y la hora; sin Dock, a la izquierda de las pestañas). Al tocarlo explica el motivo.

## Fondo animado predeterminado
Crea la carpeta `OmniStation/Resources/Background/` y pon dentro el vídeo con el nombre **`DefaultBackground.mp4`** (también vale `.mov` o `.m4v`). XcodeGen lo incluye solo en la app. Recomendado: bucle corto (10–30 s), H.264 o HEVC, 1080p o menos, menos de ~20 MB (GitHub no admite archivos de más de 100 MB). El audio se silencia. Si no hay vídeo, la opción aparece como «Animado predeterminado (no incluido)» y se usa el original estático.

## Sonidos propios
Crea la carpeta `OmniStation/Resources/Sounds/` y pon dentro tus archivos:

| Sonido | Nombre del archivo |
|---|---|
| Desplazamiento por menús | `sound_navigate` |
| Selección | `sound_select` |
| Música de ambiente (en bucle) | `sound_ambient` |

Formatos: `.wav`, `.mp3`, `.m4a`, `.caf`, `.aac`, `.aif`, `.flac`. Mayúsculas/minúsculas dan igual y se aceptan alias (`select`, `confirm`, `navigate`, `move`, `music`, `bgm`…). En Ajustes → Apariencia → Sonidos se ve qué archivo se está usando para cada sonido o por qué no se encuentra. También se pueden importar sin recompilar; los importados mandan sobre los incluidos.

## Compilación
El workflow `.github/workflows/ios-build.yml` compila una IPA sin firmar y la publica como prerelease. Antes de compilar descarga la librería `idevice` de StikJIT fijada a un commit concreto (y comprueba su huella SHA-256) en `Vendor/idevice`, así no hay que subir al repositorio el archivo de 57 MB. `Config/AppInfo.plist` añade los enlaces que la app consulta, la carpeta visible en Archivos y el audio en segundo plano (mantiene la app despierta mientras activa el JIT).

## Licencias
- StikJIT: MPL-2.0 (código en `OmniStation/JIT/StikJIT`, licencia incluida). Su librería idevice y sus scripts conservan sus licencias.
- ARMSX2 (GPL-3.0): el núcleo integrado `ARMSX2Core.framework` es ARMSX2 (https://github.com/ARMSX2/ARMSX2, etiqueta `iOSv2.6.0`) con el parche y el adaptador C de NeoStation iOS (https://github.com/TarbleFR/neostation-ios). La extensión de JIT (`Helper/`), el puente (`OmniStation/Core/`) y el script `Helper/Resources/armsx2-universal.js` están basados en NeoStation iOS (GPL-3.0-or-later). Con el núcleo integrado, OmniStation Dock en conjunto queda bajo GPL-3.0 (texto en `LICENSES/GPL-3.0.txt`): si se distribuye la IPA, hay que dar también su código fuente.
- MeloNX (AGPL-3.0, https://melonx.org) y Ryujinx (MIT): el runtime se empaqueta tal cual desde la IPA oficial de MeloNX; el anfitrión de OmniStation usa sus mismas funciones en C.
- Orbitron y Space Grotesk: SIL Open Font License 1.1.

## Tipografías
Orbitron y Space Grotesk (Google Fonts), licencia SIL Open Font License 1.1, en `OmniStation/Resources/Fonts`.

## Versión
- Marketing version: `0.4.5`
- Build: `45`
- Bundle ID: `com.omnistation.dock`
