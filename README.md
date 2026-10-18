# OmniStation Dock — versión 0.2.0

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
2. En los ajustes de cada app dentro de LiveContainer (ARMSX2 incluido), activa **iniciar con JIT**: cuando se cambia de una app a otra dentro de LiveContainer, es ese ajuste el que manda.
3. Añade los juegos como acceso directo de tipo *LiveContainer* (pega su enlace de lanzamiento o escribe su carpeta, `com.empresa.juego.app`).

### SideStore / AltStore + StikJIT integrado (sin StikDebug)
OmniStation lleva dentro **StikJIT** (MPL-2.0) y abre las apps con el depurador ella misma.
1. Crea el archivo de emparejamiento con **iloader** en un ordenador (Manage Pairing File, iPhone por cable). Tiene que ser del tipo **RPPairing**; el antiguo de SideStore ya no sirve.
2. Ajustes → Depuración → **Archivo de emparejamiento** → Importar (o déjalo en Archivos → En mi iPhone → OmniStation Dock).
3. Activa el **Modo desarrollador** y la VPN **LocalDevVPN** (mejor con Wi‑Fi).
4. Ajustes → Depuración → **JIT integrado** → *Preparar JIT*: comprueba la VPN y monta la imagen de desarrollador (la primera vez se descarga, unos 20 MB).
5. En las opciones de cada juego: *Elegir app instalada* (lista las apps de SideStore/AltStore con su Bundle ID) y, si hace falta, *Script JIT* (Automático, Universal o Legacy; solo cuenta con TXM en iOS 26).
6. Al pulsar el juego, OmniStation lo abre con JIT. Si algo falla, el motivo exacto aparece al volver a OmniStation.

También puedes elegir **App StikDebug** en *Activador de JIT* si prefieres seguir usándola.

Requisitos del JIT integrado: iOS 17.4 o posterior, apps instaladas con SideStore/AltStore (con `get-task-allow`), no funciona dentro de LiveContainer.

## ARMSX2 (PS2)
Los juegos de PS2 escaneados de tu carpeta se abren en **ARMSX2** con su enlace oficial `armsx2://launch?game=<archivo>`.
- **En LiveContainer**: un toque abre ARMSX2 con JIT y arranca el juego. Por defecto busca la carpeta `com.armsx2.ios.app` (cámbiala en Ajustes → ARMSX2 si la tuya es otra).
- **Instalado con SideStore/AltStore + JIT integrado**: la primera vez OmniStation abre ARMSX2 con JIT; vuelve y pulsa el juego otra vez y arranca al momento (mientras ARMSX2 siga abierto conserva el JIT).
- **Con la app StikDebug**: OmniStation abre el juego y ARMSX2 pide el JIT a StikDebug por su cuenta.
- ARMSX2 busca el juego por el **nombre del archivo** en su propia biblioteca: configura en ARMSX2 la misma carpeta de juegos. Si añadiste juegos con una versión anterior, vuelve a escanear la carpeta.

**Versiones nuevas**: al abrir la app (como mucho cada 6 h) mira las versiones de ARMSX2 en GitHub (solo las *nightly* traen IPA de iOS). Si hay una nueva, te ofrece instalarla: la IPA se manda a LiveContainer (`livecontainer://install`) o a SideStore/AltStore, que la descargan e instalan tras confirmar. Con *Instalar sin preguntar* abre el instalador directamente. iOS no permite que una app actualice a otra sin ningún toque.

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
- Marketing version: `0.2.0`
- Build: `20`
- Bundle ID: `com.omnistation.dock`
