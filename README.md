# OmniStation Dock — versión 0.1.8

Lanzador de juegos y emuladores para iPhone con interfaz espacial/Liquid Glass, control completo con mando y **Modo Dock** (carrusel en horizontal, también al conectar HDMI).

## Funciones
- Inicio, Favoritos, Búsqueda y Ajustes, con filtros por plataforma (incluidas Juegos iOS, Ports y las tuyas).
- Biblioteca: carpeta externa con ROMs de todas las plataformas, accesos directos (URL, app iOS por Bundle ID con StikDebug, o LiveContainer) y carátulas.
- Por juego: cambiar nombre, carátula y plataforma, logros de RetroAchievements y mapa de botones.
- Mando (DualSense, Xbox…): cruceta, ✕ jugar, △ opciones, ○ atrás, L1/R1 plataforma, L2/R2 pestaña.
- Fondo estático (imagen) o animado (vídeo) y sonidos con volumen propio.

## Sonidos propios
Crea la carpeta `OmniStation/Resources/Sounds/` en el repositorio y pon dentro tus archivos con estos nombres exactos:

| Sonido | Nombre del archivo |
|---|---|
| Desplazamiento por menús | `sound_navigate` |
| Selección | `sound_select` |
| Música de ambiente (en bucle) | `sound_ambient` |

Formatos válidos: `.wav`, `.mp3`, `.m4a`, `.caf`, `.aac`, `.aif` (por ejemplo `sound_select.wav`). XcodeGen los incluye solos en la app. Desde Ajustes → Apariencia → Sonidos también se pueden importar otros sin recompilar; los importados mandan sobre los incluidos.

## Compilación
El workflow `.github/workflows/ios-build.yml` compila una IPA sin firmar y la publica como prerelease de GitHub Release. `Config/AppInfo.plist` añade al Info.plist los enlaces que la app puede consultar para detectar juegos iOS.

## Tipografías
Orbitron y Space Grotesk (Google Fonts), bajo la licencia SIL Open Font License 1.1. Los archivos y sus licencias están en `OmniStation/Resources/Fonts`. En esta versión toda la app usa Orbitron (`AppFont.useBrandEverywhere`).

## Versión
- Marketing version: `0.1.8`
- Build: `18`
- Bundle ID: `com.omnistation.dock`
