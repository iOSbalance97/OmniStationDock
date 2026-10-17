# OmniStation Dock — versión 0.1.9

Lanzador de juegos y emuladores para iPhone con interfaz espacial/Liquid Glass, control completo con mando y **Modo Dock** (carrusel en horizontal, también al conectar HDMI).

## Funciones
- Inicio, Favoritos, Búsqueda y Ajustes, con filtros por plataforma (incluidas Juegos iOS, Ports y las tuyas).
- Biblioteca: carpeta externa con ROMs de todas las plataformas, accesos directos (URL, app iOS por Bundle ID con StikDebug, o LiveContainer) y carátulas.
- Por juego: cambiar nombre, carátula y plataforma, favoritos, logros de RetroAchievements, mapa de botones y **abrir con JIT**.
- Mando (DualSense, Xbox…): cruceta (mantener = repetir), ✕ jugar, △ opciones, ○ atrás, L1/R1 plataforma, L2/R2 pestaña.
- Fondo: animado predeterminado, original estático, imagen propia o vídeo propio. Sonidos con volumen propio.

## JIT
La primera vez que se abre, la app pregunta **cómo se instaló** (se puede cambiar en Ajustes → Depuración → Método de instalación):

**LiveContainer**
1. En LiveContainer → Ajustes, elige **StikDebug** como activador de JIT.
2. Añade cada juego como acceso directo de tipo *LiveContainer*: pega su enlace (mantén pulsada la app en LiveContainer → *Copiar enlace de lanzamiento*) o escribe el nombre de su carpeta (`Juego.app`).
3. Al abrirlo con JIT, OmniStation abre el enlace con `jit=true` y LiveContainer pide el JIT a StikDebug.

**SideStore / AltStore**
1. Ajustes → Depuración → **Archivo de emparejamiento** → Importar (vale `.mobiledevicepairing` o `.plist`). También se importa solo si lo dejas en Archivos → En mi iPhone → OmniStation Dock.
2. Pulsa **Exportar a StikDebug** y guárdalo en Archivos → En mi iPhone → StikDebug (`pairingFile.plist`).
3. Cada juego necesita su **Bundle ID** (opciones del juego → *Bundle ID para JIT*). Los accesos de tipo *App iOS* ya lo llevan.
4. Con la VPN de StikDebug activa, OmniStation abre `stikjit://enable-jit?bundle-id=…` y StikDebug lanza el juego con JIT.

**JIT al abrir juegos** (Ajustes → Depuración) lo activa para todos; cada juego puede cambiarlo en sus opciones (*Abrir con JIT*).

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
El workflow `.github/workflows/ios-build.yml` compila una IPA sin firmar y la publica como prerelease. `Config/AppInfo.plist` añade al Info.plist los enlaces que la app puede consultar y la carpeta visible en Archivos.

## Tipografías
Orbitron y Space Grotesk (Google Fonts), licencia SIL Open Font License 1.1, en `OmniStation/Resources/Fonts`.

## Versión
- Marketing version: `0.1.9`
- Build: `19`
- Bundle ID: `com.omnistation.dock`
