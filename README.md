# OmniStation Dock — versión 0.1.7

Lanzador de juegos y emuladores para iPhone con interfaz espacial/Liquid Glass, control completo con mando y **Modo Dock** (carrusel en horizontal, también al conectar HDMI).

## Funciones
- Inicio, Favoritos, Búsqueda y Ajustes, con filtros por plataforma y destacados más jugados.
- Biblioteca: carpeta vinculada con escaneo de juegos y accesos directos por URL.
- Mando (DualSense, Xbox…): cruceta, ✕ jugar, △ opciones, ○ atrás, L1/R1 plataforma, L2/R2 pestaña.
- Depuración: estado de JIT y activación con StikDebug (`stikjit://enable-jit`).
- LiveContainer: detección y accesos directos (`livecontainer://livecontainer-launch?bundle-name=`).

## Compilación
El workflow `.github/workflows/ios-build.yml` compila una IPA sin firmar y la publica como prerelease de GitHub Release.

## Tipografías
Orbitron y Space Grotesk (Google Fonts), bajo la licencia SIL Open Font License 1.1. Los archivos y sus licencias están en `OmniStation/Resources/Fonts`.

## Versión
- Marketing version: `0.1.7`
- Build: `17`
- Bundle ID: `com.omnistation.dock`
