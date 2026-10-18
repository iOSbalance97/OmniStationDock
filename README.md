# OmniStation Dock — versión 0.3.1

Lanzador de juegos y emuladores para iPhone con interfaz espacial/Liquid Glass, control completo con mando y **Modo Dock** (carrusel en horizontal, también al conectar HDMI).

## Funciones
- Inicio, Favoritos, Búsqueda y Ajustes, con filtros por plataforma (incluidas Juegos iOS, Ports y las tuyas).
- Biblioteca: carpeta externa con ROMs de todas las plataformas, accesos directos (URL, app iOS por Bundle ID con StikDebug, o LiveContainer) y carátulas.
- Por juego: cambiar nombre, carátula y plataforma, favoritos, logros de RetroAchievements, mapa de botones y **abrir con JIT**.
- Mando (DualSense, Xbox…): cruceta (mantener = repetir), ✕ jugar, △ opciones, ○ atrás, L1/R1 plataforma, L2/R2 pestaña.
- Fondo: animado predeterminado, original estático, imagen propia o vídeo propio. Sonidos con volumen propio.

## JIT
La primera vez la app pregunta **cómo se instaló** (Ajustes → Depuración → Método de instalación).

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
- **En LiveContainer**: un toque abre el emulador con JIT (pidiéndolo como hace LiveContainer) y arranca el juego.
- **SideStore/AltStore + JIT integrado**: MeloNX se abre con el juego y espera al JIT; OmniStation se lo da en segundo plano y el juego arranca solo. ARMSX2 no espera al JIT: la primera vez se abre con JIT y hay que volver y pulsar el juego otra vez (mientras siga abierto, arranca al momento).
- **Con la app StikDebug**: OmniStation abre el juego y el emulador pide el JIT a StikDebug por su cuenta.
- **Versiones nuevas** (cada emulador por separado, como mucho cada 6 h): ARMSX2 desde GitHub (solo las *nightly* traen IPA de iOS) y MeloNX desde su servidor Forgejo. La IPA se manda a LiveContainer o a SideStore/AltStore, que la instalan tras confirmar.

## Indicador de JIT
En horizontal, un punto verde o rojo indica si OmniStation está corriendo con JIT ahora mismo (lo mismo que *Estado JIT* en Ajustes) (en el Modo Dock, entre la batería y la hora; sin Dock, a la izquierda de las pestañas). Al tocarlo explica el motivo.

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
- ARMSX2 no va incluido: se abre como app aparte (GPL-3.0).
- Orbitron y Space Grotesk: SIL Open Font License 1.1.

## Tipografías
Orbitron y Space Grotesk (Google Fonts), licencia SIL Open Font License 1.1, en `OmniStation/Resources/Fonts`.

## Versión
- Marketing version: `0.3.1`
- Build: `31`
- Bundle ID: `com.omnistation.dock`
