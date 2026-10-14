# OmniStation Dock — primera versión

Esta primera versión contiene únicamente:
- Nombre visible: **OmniStation Dock**
- Icono de app azul/negro preparado para iOS
- Bienvenida en SwiftUI con fondo espacial, icono centrado y nombre en SF Pro Display
- Animación sutil de aparición
- Flujo de GitHub Actions para compilar en un runner macOS

No incluye todavía biblioteca, juegos ni ajustes.

## Estructura

```text
OmniStationDock/
  App/OmniStationDockApp.swift
  Views/WelcomeView.swift
  Resources/Assets.xcassets/
    AppIcon.appiconset/
    OmniLogo.imageset/
    SpaceBackground.imageset/
project.yml
.github/workflows/ios-build.yml
```

## Cómo subirlo desde el iPhone

1. Descarga y descomprime `OmniStationDock-Starter.zip` en Archivos.
2. En GitHub, crea un repositorio vacío llamado `OmniStationDock` (sin README ni licencia para evitar conflictos).
3. Abre Working Copy y clona el repositorio.
4. En Archivos, copia el contenido de la carpeta `OmniStationDock-Starter` dentro de la carpeta del repositorio clonado en Working Copy. Asegúrate de incluir `.github`; si no aparece, activa la visualización de archivos ocultos o añade el workflow desde GitHub.
5. En Working Copy, haz commit y push.
6. En GitHub, abre **Actions** y entra en **Build OmniStation Dock**.
7. Descarga el artefacto `OmniStationDock-Simulator-App` cuando termine la compilación.

## Qué produce la compilación inicial

El workflow compila una app para el **simulador de iOS** y guarda el `.app` como artefacto. Esto permite comprobar que el código compila, pero no es instalable directamente en un iPhone real.

Para instalarla en el iPhone, el siguiente paso será preparar una compilación para dispositivo y una IPA firmada con el método de firma que uses (por ejemplo, tu flujo de sideloading). No compartas certificados privados ni contraseñas en el repositorio.

## Identificador

El bundle identifier inicial es `com.omnistation.dock`. Puedes cambiarlo antes de la firma si necesitas otro identificador único.

## Notas

- El icono de la app es opaco, cuadrado y de 1024 × 1024, para que iOS aplique su máscara de forma correcta.
- La imagen `OmniLogo.png` conserva transparencia y se usa dentro de la bienvenida.
- El fondo espacial está separado del código y puede sustituirse sin tocar SwiftUI.
