import SwiftUI
import UIKit
import GameController
import AudioToolbox
import CoreText

// MARK: - Idioma

enum L10n {
    /// "system", "es" o "en" -> "es" o "en".
    static func resolve(_ raw: String) -> String {
        if raw == "es" || raw == "en" { return raw }
        let first = Locale.preferredLanguages.first ?? "es"
        return first.hasPrefix("en") ? "en" : "es"
    }

    /// El español es el idioma base: la clave es el propio texto. En inglés se busca la traducción.
    static func tr(_ key: String, _ raw: String) -> String {
        guard resolve(raw) == "en" else { return key }
        return english[key] ?? key
    }

    static let english: [String: String] = [
        "Inicio": "Home",
        "Favoritos": "Favorites",
        "Búsqueda": "Search",
        "Ajustes": "Settings",
        "TU UNIVERSO DE JUEGOS,\nEN UN SOLO LUGAR.": "YOUR GAMING UNIVERSE,\nIN ONE PLACE.",
        "OmniStation Dock": "OmniStation Dock",
        "Todos": "All",
        "DESTACADO": "FEATURED",
        "MÁS JUGADO": "MOST PLAYED",
        "Jugar": "Play",
        "%@ · %ld veces": "%@ · %ld plays",
        "%ld elementos": "%ld items",
        "%ld encontrados": "%ld found",
        "%ld conectados": "%ld connected",
        "Juegos recientes": "Recent games",
        "Tu biblioteca": "Your library",
        "Tu biblioteca está vacía": "Your library is empty",
        "Vincula una carpeta o añade un acceso directo en Ajustes → Juegos.": "Link a folder or add a shortcut in Settings → Games.",
        "Tu universo está tomando forma": "Your universe is taking shape",
        "Estos son juegos de ejemplo. Vincula una carpeta o añade accesos directos en Ajustes → Juegos.": "These are sample games. Link a folder or add shortcuts in Settings → Games.",
        "Resultados": "Results",
        "Sin resultados": "No results",
        "Prueba otro nombre o plataforma.": "Try another name or platform.",
        "Encuentra un juego o filtra por plataforma.": "Find a game or filter by platform.",
        "Buscar juegos y plataformas…": "Search games and platforms…",
        "Tus favoritos": "Your favorites",
        "Tus juegos marcados con estrella.": "Your starred games.",
        "Aún no hay favoritos": "No favorites yet",
        "Toca la estrella de un juego para guardarlo aquí.": "Tap a game's star to save it here.",
        "Añadir a favoritos": "Add to favorites",
        "Quitar de favoritos": "Remove from favorites",
        "Quitar de la biblioteca": "Remove from library",
        "Personaliza tu experiencia.": "Customize your experience.",
        "General": "General",
        "Apariencia": "Appearance",
        "Juegos": "Games",
        "Mandos": "Controllers",
        "Ninguno conectado": "None connected",
        "Ningún mando conectado": "No controller connected",
        "Conecta un mando por Bluetooth (DualSense, Xbox…) y aparecerá aquí.": "Connect a controller over Bluetooth (DualSense, Xbox…) and it will appear here.",
        "Navegar con el mando": "Navigate with controller",
        "L1 y R1 cambian de pestaña": "L1 and R1 switch tabs",
        "Cargando": "Charging",
        "Vibración": "Vibration",
        "Respuesta háptica al tocar": "Haptic feedback on tap",
        "Sonido al pulsar": "Tap sound",
        "Clic al tocar botones": "Click when tapping buttons",
        "Dock en horizontal": "Dock in landscape",
        "Mantener la app en horizontal": "Keep the app in landscape",
        "Horizontal con HDMI": "Landscape on HDMI",
        "Avisa y gira al conectar HDMI": "Warns and rotates on HDMI connect",
        "Pantalla HDMI detectada. Cambiando a horizontal…": "HDMI display detected. Switching to landscape…",
        "Acerca de": "About",
        "Versión %@": "Version %@",
        "Fondo personalizado": "Custom background",
        "Predeterminado": "Default",
        "Imagen propia": "Your own image",
        "Elegir otra imagen": "Choose another image",
        "Restaurar fondo": "Restore background",
        "Fondo actualizado": "Background updated",
        "Fondo restaurado": "Background restored",
        "No se pudo usar esa imagen": "That image couldn't be used",
        "Idioma": "Language",
        "Sistema": "System",
        "Reorganizar plataformas": "Reorder platforms",
        "Orden de los filtros": "Filter order",
        "Arrastra para cambiar el orden de los filtros.": "Drag to change the order of the filters.",
        "Restablecer": "Reset",
        "Cuadrícula completa": "Full grid",
        "Más juegos por pantalla": "More games per screen",
        "Bienvenida animada": "Animated welcome",
        "Pantalla de inicio al abrir": "Splash screen on launch",
        "Logo en cabecera": "Header logo",
        "Icono junto al nombre": "Icon next to the name",
        "Escaneo de juegos": "Game scan",
        "Vincula una carpeta primero": "Link a folder first",
        "Buscar en «%@»": "Search in “%@”",
        "Escaneando…": "Scanning…",
        "Escaneo completo: %ld juegos": "Scan complete: %ld games",
        "No se encontraron juegos en la carpeta": "No games found in the folder",
        "Primero vincula una carpeta de juegos": "Link a games folder first",
        "Vincular carpeta": "Link folder",
        "Carpeta contenedora": "Games folder",
        "Carpeta vinculada: %@": "Folder linked: %@",
        "No se pudo vincular la carpeta": "The folder couldn't be linked",
        "Acceso directo (URL)": "Shortcut (URL)",
        "Abre un emulador con un enlace": "Opens an emulator with a link",
        "Acceso directo añadido": "Shortcut added",
        "Añadir acceso directo": "Add shortcut",
        "Plataforma": "Platform",
        "Nombre": "Name",
        "Nombre del juego": "Game name",
        "URL de acceso directo": "Shortcut URL",
        "Debe incluir el esquema de la app, por ejemplo app://…": "It must include the app scheme, for example app://…",
        "Este juego aún no tiene acceso directo": "This game has no shortcut yet",
        "No se pudo abrir el enlace": "The link couldn't be opened",
        "Juegos de ejemplo": "Sample games",
        "Mostrar los de demostración": "Show the demo ones",
        "Borrar favoritos": "Clear favorites",
        "Quita todos los marcados": "Removes all starred games",
        "¿Borrar todos los favoritos?": "Clear all favorites?",
        "Quitar añadidos": "Remove added",
        "Escaneados y accesos directos": "Scanned games and shortcuts",
        "¿Quitar los juegos añadidos?": "Remove the added games?",
        "Quitar juegos": "Remove games",
        "Añadir": "Add",
        "Cancelar": "Cancel",
        "Cerrar": "Close",
        "Si lo desactivas, el mando dejará de mover la interfaz.": "If you turn it off, the controller will stop moving the interface.",
        "Con el mando: X agarra y suelta, ↑↓ mueve.": "Controller: X grabs and drops, ↑↓ moves.",
        "Giro a horizontal cancelado": "Rotation to landscape cancelled",
        "A/X: elegir": "A/X: choose",
        "Selecciona letras con el mando": "Select letters with the controller",
        "Modo Dock": "Dock Mode",
        "Carrusel al girar a horizontal": "Carousel when rotated to landscape",
        "Dock con HDMI": "Dock on HDMI",
        "Activa Dock y horizontal al conectar HDMI": "Turns on Dock and landscape when HDMI connects",
        "Bloquear horizontal": "Lock landscape",
        "Reloj 24 horas": "24-hour clock",
        "Formato de la hora en Dock": "Time format in Dock",
        "Pantalla HDMI detectada. Activando Modo Dock…": "HDMI display detected. Turning on Dock Mode…",
        "Pestaña": "Tab",
        "Opciones": "Options",
        "Atrás": "Back",
        "Presiona ✕ para jugar": "Press ✕ to play",
        "Sin juegos en esta plataforma": "No games on this platform",
        "Mando": "Controller",
        "Rendimiento": "Performance",
        "%@: próximamente": "%@: coming soon",
        "Depuración": "Debugging",
        "Estado JIT": "JIT status",
        "Activo en esta app": "Active in this app",
        "No activo en esta app": "Not active in this app",
        "JIT activo en esta app": "JIT is active in this app",
        "JIT no activo en esta app": "JIT is not active in this app",
        "Activar JIT": "Enable JIT",
        "Con StikDebug, en esta app": "With StikDebug, in this app",
        "Abrir StikDebug": "Open StikDebug",
        "Emparejamiento y scripts JIT": "Pairing and JIT scripts",
        "Copiar Bundle ID": "Copy Bundle ID",
        "Bundle ID copiado": "Bundle ID copied",
        "No se pudo abrir StikDebug. ¿Está instalado?": "StikDebug couldn't be opened. Is it installed?",
        "Estado": "Status",
        "Dentro de LiveContainer": "Inside LiveContainer",
        "Fuera de LiveContainer": "Outside LiveContainer",
        "SÍ": "YES",
        "NO": "NO",
        "Abrir LiveContainer": "Open LiveContainer",
        "Abre la app de LiveContainer": "Opens the LiveContainer app",
        "No se pudo abrir LiveContainer. ¿Está instalado?": "LiveContainer couldn't be opened. Is it installed?",
        "Juego de LiveContainer": "LiveContainer game",
        "Acceso directo a una app de LiveContainer": "Shortcut to a LiveContainer app",
        "✕: escribir": "✕: type",
        "%ld de %ld logros": "%ld of %ld achievements",
        "%ld puntos": "%ld points",
        "Abre un juego, app o emulador": "Opens a game, app or emulator",
        "Acceso directo": "Shortcut",
        "Actualizar": "Refresh",
        "App iOS": "iOS app",
        "Asignar plataforma": "Assign platform",
        "Añadir plataforma": "Add platform",
        "Cambiar carpeta": "Change folder",
        "Cambiar carátula": "Change cover",
        "Cambiar nombre": "Rename",
        "Carpeta desvinculada": "Folder unlinked",
        "Carpeta externa": "External folder",
        "Carátula": "Cover",
        "Carátula actualizada": "Cover updated",
        "Clave web (Web API Key)": "Web API Key",
        "Clic del sistema": "System click",
        "Conecta RetroAchievements": "Connect RetroAchievements",
        "Conecta tu cuenta de RetroAchievements en Ajustes → Logros.": "Connect your RetroAchievements account in Settings → Achievements.",
        "Conectar": "Connect",
        "Conseguido %@": "Earned %@",
        "Crea tus propias plataformas": "Create your own platforms",
        "Desconectar": "Disconnect",
        "Desplazamiento por menús": "Menu navigation",
        "Desvincular carpeta": "Unlink folder",
        "Dock a pantalla completa": "Full-width Dock",
        "El mapa se guarda para este juego. iOS no deja que una app cambie los botones dentro de otra: úsalo como referencia o configúralo igual en el emulador.": "The mapping is saved for this game. iOS doesn't let one app change the buttons inside another: use it as a reference or set the same mapping in the emulator.",
        "Elegir carátula": "Choose cover",
        "Elegir imagen": "Choose image",
        "Elegir otro vídeo": "Choose another video",
        "Elegir vídeo": "Choose video",
        "En uso": "In use",
        "Escribe el Bundle ID de la app. Se abrirá con StikDebug (sirve para cualquier app instalada, también ports).": "Type the app's Bundle ID. It will open through StikDebug (works for any installed app, ports too).",
        "Escribe el ID del juego en RetroAchievements (es el número de la dirección de su página, por ejemplo retroachievements.org/game/1234).": "Type the game's RetroAchievements ID (the number in its page address, for example retroachievements.org/game/1234).",
        "Escribe el nombre de la app dentro de LiveContainer (el de su enlace de lanzamiento).": "Type the app name inside LiveContainer (the one in its launch link).",
        "Este juego no tiene logros.": "This game has no achievements.",
        "Fondo animado": "Animated background",
        "Fondo animado actualizado": "Animated background updated",
        "Fondo animado quitado": "Animated background removed",
        "Fondo estático": "Static background",
        "Formatos: wav, mp3, m4a, caf, aac o aif. Con el mando: ←→ volumen, X probar.": "Formats: wav, mp3, m4a, caf, aac or aif. Controller: ←→ volume, X preview.",
        "Guardada": "Saved",
        "Guardado": "Saved",
        "Guardar": "Save",
        "ID de RetroAchievements: %@": "RetroAchievements ID: %@",
        "Icono": "Icon",
        "Importar": "Import",
        "Juegos añadidos": "Added games",
        "Juegos iOS encontrados: %ld": "iOS games found: %ld",
        "Juegos instalados en el iPhone": "Games installed on the iPhone",
        "La clave está en retroachievements.org, en los ajustes de tu perfil (apartado de claves). Se guarda en el llavero del iPhone.": "The key is on retroachievements.org, in your profile settings (keys section). It's stored in the iPhone keychain.",
        "Logros": "Achievements",
        "Logros recientes": "Recent achievements",
        "Mapear botones": "Map buttons",
        "Música de ambiente": "Ambient music",
        "No hay juegos añadidos.": "No added games.",
        "No se encontraron juegos iOS conocidos": "No known iOS games found",
        "No se pudo conectar con RetroAchievements.": "Couldn't connect to RetroAchievements.",
        "No se pudo importar ese archivo": "That file couldn't be imported",
        "No se pudo usar ese vídeo": "That video couldn't be used",
        "Nombre de la plataforma": "Platform name",
        "Nueva plataforma": "New platform",
        "Opciones del juego": "Game options",
        "Original": "Original",
        "Pega aquí tu clave web": "Paste your web key here",
        "Plataforma original": "Original platform",
        "Plataformas": "Platforms",
        "Probar": "Preview",
        "Pulsa otra vez para confirmar": "Press again to confirm",
        "Quitar": "Remove",
        "Quitar carátula": "Remove cover",
        "Quitar imagen": "Remove image",
        "Quitar todos": "Remove all",
        "Quitar vídeo": "Remove video",
        "ROMs de todas las plataformas": "ROMs from every platform",
        "Selección": "Selection",
        "Sin logros en los últimos 30 días.": "No achievements in the last 30 days.",
        "Sin música: importa una": "No music: import one",
        "Sonido de la app": "App sound",
        "Sonido importado": "Imported sound",
        "Sonidos": "Sounds",
        "Sonidos de navegación y selección": "Navigation and selection sounds",
        "Tipo de enlace": "Link type",
        "Tu usuario de RetroAchievements": "Your RetroAchievements username",
        "Tus plataformas": "Your platforms",
        "URL": "URL",
        "Usa todo el ancho en horizontal": "Uses the full width in landscape",
        "Usar esta imagen": "Use this image",
        "Usar este vídeo": "Use this video",
        "Usuario": "Username",
        "Usuario o clave web no válidos.": "Invalid username or web key.",
        "Ver y quitar uno a uno": "View and remove one by one",
        "Volumen e importación": "Volume and import",
        "Volver a escanear": "Scan again",
        "Ya existe una plataforma con ese nombre.": "A platform with that name already exists.",
        "%@: formato no compatible": "%@: unsupported format",
        "%ld logros": "%ld achievements",
        "Abriendo con JIT…": "Opening with JIT…",
        "Abrir con JIT": "Open with JIT",
        "Abrir página de la clave": "Open key page",
        "Activa la VPN de StikDebug (LocalDevVPN) y abre tus juegos con JIT desde OmniStation.": "Turn on the StikDebug VPN (LocalDevVPN) and open your games with JIT from OmniStation.",
        "Animado predeterminado": "Default animated",
        "Animado predeterminado (no incluido)": "Default animated (not included)",
        "Archivo de emparejamiento": "Pairing file",
        "Archivo de emparejamiento importado.": "Pairing file imported.",
        "Archivo de emparejamiento quitado.": "Pairing file removed.",
        "Archivo de emparejamiento válido": "Valid pairing file",
        "Así la app sabe cómo activar el JIT de tus juegos. Puedes cambiarlo cuando quieras en Ajustes → Depuración.": "This tells the app how to enable JIT for your games. You can change it anytime in Settings → Debugging.",
        "Bundle ID guardado": "Bundle ID saved",
        "Bundle ID para JIT": "Bundle ID for JIT",
        "Bundle ID quitado": "Bundle ID removed",
        "Cambiar imagen propia": "Change custom image",
        "Cambiar juego (ID %@)": "Change game (ID %@)",
        "Cambiar vídeo propio": "Change custom video",
        "Cerrar sesión": "Log out",
        "Confirmar": "Confirm",
        "Consigue tu archivo de emparejamiento (SideStore lo guarda como ALTPairingFile.mobiledevicepairing en su carpeta de Archivos, o créalo con jitterbugpair en un ordenador).": "Get your pairing file (SideStore keeps it as ALTPairingFile.mobiledevicepairing in its Files folder, or create it with jitterbugpair on a computer).",
        "Cómo funciona": "How it works",
        "De la app: %@": "From the app: %@",
        "Detectado": "Detected",
        "Elegir imagen propia": "Choose custom image",
        "Elegir vídeo propio": "Choose custom video",
        "Entra en retroachievements.org → Ajustes → apartado «Keys», copia la «Web API Key» y pégala aquí. La sesión queda guardada en este iPhone.": "Go to retroachievements.org → Settings → “Keys”, copy the “Web API Key” and paste it here. The session stays saved on this iPhone.",
        "Es el número de la dirección de su página, por ejemplo retroachievements.org/game/1234.": "It is the number in its page address, for example retroachievements.org/game/1234.",
        "Ese archivo no es un archivo de emparejamiento válido.": "That file is not a valid pairing file.",
        "Exportado. Si lo guardaste en la carpeta de StikDebug, ya está listo.": "Exported. If you saved it in the StikDebug folder, it is ready.",
        "Exportar a StikDebug": "Export to StikDebug",
        "FALTA": "MISSING",
        "Imagen propia quitada": "Custom image removed",
        "Importado": "Imported",
        "Importado: %@": "Imported: %@",
        "Importar para SideStore/AltStore": "Import for SideStore/AltStore",
        "Impórtalo aquí: la app comprueba que es válido. También puedes dejarlo en Archivos → En mi iPhone → OmniStation Dock y se importa solo.": "Import it here: the app checks that it is valid. You can also drop it in Files → On My iPhone → OmniStation Dock and it is imported automatically.",
        "Inicia sesión en RetroAchievements en Ajustes → Juegos → Logros.": "Log in to RetroAchievements in Settings → Games → Achievements.",
        "Iniciando sesión…": "Logging in…",
        "Iniciar sesión": "Log in",
        "Iniciar sesión en RetroAchievements": "Log in to RetroAchievements",
        "JIT al abrir juegos": "JIT when opening games",
        "La app está instalada directamente. El JIT lo activa StikDebug con tu archivo de emparejamiento, que puedes gestionar desde aquí.": "The app is installed directly. StikDebug enables JIT using your pairing file, which you can manage from here.",
        "La app y tus juegos están dentro de LiveContainer. El JIT lo activa LiveContainer con StikDebug (elige StikDebug como activador de JIT en los ajustes de LiveContainer).": "The app and your games are inside LiveContainer. LiveContainer enables JIT with StikDebug (choose StikDebug as the JIT enabler in LiveContainer settings).",
        "La clave web tiene 32 caracteres. ¿Has puesto tu contraseña?": "The web key has 32 characters. Did you enter your password?",
        "La sesión de RetroAchievements no es válida. Vuelve a iniciarla en Ajustes.": "The RetroAchievements session is not valid. Log in again in Settings.",
        "Método de instalación": "Install method",
        "Método de instalación: %@": "Install method: %@",
        "No es tu contraseña": "It is not your password",
        "No se encontró automáticamente: escribe su ID.": "Not found automatically: enter its ID.",
        "No se pudo exportar el archivo.": "The file could not be exported.",
        "No se pudo leer %@": "Could not read %@",
        "O escribe su ID": "Or enter its ID",
        "Original estático": "Original static",
        "Para abrirlo con JIT, añade su Bundle ID en las opciones del juego": "To open it with JIT, add its Bundle ID in the game options",
        "Para los juegos sin ajuste propio": "For games without their own setting",
        "Pega el enlace de lanzamiento de LiveContainer (mantén pulsada la app en LiveContainer → Copiar enlace de lanzamiento) o escribe el nombre de su carpeta, por ejemplo Juego.app.": "Paste the LiveContainer launch link (long-press the app in LiveContainer → Copy launch URL) or type its folder name, for example Game.app.",
        "Pulsa «Exportar a StikDebug» y guárdalo en Archivos → En mi iPhone → StikDebug. StikDebug lo usa automáticamente.": "Tap “Export to StikDebug” and save it in Files → On My iPhone → StikDebug. StikDebug uses it automatically.",
        "Quitar imagen propia": "Remove custom image",
        "Quitar vídeo propio": "Remove custom video",
        "Recuerda: StikDebug necesita tu archivo de emparejamiento": "Remember: StikDebug needs your pairing file",
        "Reemplazar": "Replace",
        "RetroAchievements no tiene logros para esta plataforma.": "RetroAchievements has no achievements for this platform.",
        "Se abrirá con JIT": "Will open with JIT",
        "Se abrirá sin JIT": "Will open without JIT",
        "Sesión guardada en este iPhone": "Session saved on this iPhone",
        "Sesión iniciada como %@": "Logged in as %@",
        "Sesión: %@": "Session: %@",
        "Sin archivo de emparejamiento": "No pairing file",
        "Sin conexión a internet.": "No internet connection.",
        "Sin conexión: se muestra la sesión guardada.": "Offline: showing the saved session.",
        "Sin elegir": "Not chosen",
        "StikDebug instalado": "StikDebug installed",
        "StikDebug no detectado": "StikDebug not detected",
        "Usuario o clave web incorrectos. Recuerda: es la Web API Key, no tu contraseña.": "Wrong username or web key. Remember: it is the Web API Key, not your password.",
        "Vídeo propio": "Custom video",
        "Vídeo propio quitado": "Custom video removed",
        "¿Cuál es este juego en RetroAchievements?": "Which game is this on RetroAchievements?",
        "¿Cómo has instalado OmniStation Dock?": "How did you install OmniStation Dock?",
        "Listo": "Done"
    ]
}

// MARK: - Juegos

struct Game: Identifiable {
    let id: String
    let name: String
    let platform: String
    let symbol: String
    let tint: Color
    var launchURL: String? = nil
    var isCustom: Bool = false

    static let samples: [Game] = [
        Game(id: "God of War", name: "God of War", platform: "PS2", symbol: "flame.fill", tint: Color(red: 0.05, green: 0.42, blue: 1.0)),
        Game(id: "Silent Hill 2", name: "Silent Hill 2", platform: "PS2", symbol: "moon.fill", tint: Color(red: 0.10, green: 0.30, blue: 0.78)),
        Game(id: "Resident Evil 4", name: "Resident Evil 4", platform: "GameCube", symbol: "eye.fill", tint: Color(red: 0.06, green: 0.58, blue: 0.95)),
        Game(id: "Pokémon Esmeralda", name: "Pokémon Esmeralda", platform: "GBA", symbol: "leaf.fill", tint: Color(red: 0.00, green: 0.72, blue: 1.0)),
        Game(id: "Mario Kart DS", name: "Mario Kart DS", platform: "NDS", symbol: "flag.checkered", tint: Color(red: 0.10, green: 0.46, blue: 1.0)),
        Game(id: "Pokémon Rojo Fuego", name: "Pokémon Rojo Fuego", platform: "GBA", symbol: "bolt.fill", tint: Color(red: 0.16, green: 0.82, blue: 1.0))
    ]
}

/// Juego añadido por el usuario (escaneado de una carpeta o acceso directo por URL).
struct LibraryGame: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var platform: String
    var launchURL: String?
    var source: String   // "scan" o "url"

    var asGame: Game {
        Game(
            id: id,
            name: name,
            platform: platform,
            symbol: Platforms.symbol(for: platform),
            tint: Platforms.tint(for: platform),
            launchURL: launchURL,
            isCustom: true
        )
    }
}

enum LibraryStore {
    private static var fileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("library.json")
    }

    static func load() -> [LibraryGame] {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([LibraryGame].self, from: data) else { return [] }
        return list
    }

    static func save(_ list: [LibraryGame]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - Carpeta de juegos y escaneo

enum LibraryFolder {
    static func bookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    static func resolve(_ data: Data) -> URL? {
        var stale = false
        return try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
    }
}

// MARK: - Vibración y sonido

enum Feedback {
    static func tap(haptics: Bool, sound: Bool) {
        if haptics {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        if sound {
            AudioServicesPlaySystemSound(1104)
        }
    }
}

// MARK: - Orientación

enum OrientationController {
    /// Fija la orientación permitida y pide a iOS que gire ahora.
    static func apply(landscape: Bool) {
        AppDelegate.orientationMask = landscape ? .landscape : .allButUpsideDown
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return }
        scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: landscape ? .landscape : .allButUpsideDown)) { _ in }
    }
}

// MARK: - Monitores de dispositivos

/// Detecta si hay una pantalla externa (HDMI) conectada.
final class HDMIMonitor: ObservableObject {
    @Published private(set) var isConnected = false
    private var tokens: [NSObjectProtocol] = []

    init() {
        isConnected = UIScreen.screens.count > 1
        let center = NotificationCenter.default
        let names: [Notification.Name] = [UIScreen.didConnectNotification, UIScreen.didDisconnectNotification]
        for name in names {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.isConnected = UIScreen.screens.count > 1
            })
        }
    }

    deinit {
        tokens.forEach { NotificationCenter.default.removeObserver($0) }
    }
}

/// Lista los mandos conectados y, si se activa, usa L1/R1 para cambiar de pestaña.
final class ControllerMonitor: ObservableObject {
    struct Info: Identifiable, Equatable {
        let id: String
        let name: String
        let category: String
        let battery: Int?
        let charging: Bool
    }

    @Published private(set) var controllers: [Info] = []
    var navigationEnabled = false
    /// L1/R1: cambiar plataforma.
    var onShoulder: ((Int) -> Void)?
    /// L2/R2: cambiar sección principal.
    var onTrigger: ((Int) -> Void)?
    /// B/círculo: volver atrás.
    var onCancel: (() -> Void)?
    /// Cruceta: navegación direccional dentro de la interfaz.
    var onDirection: ((Direction) -> Void)?
    /// A/X: activar el elemento que tenga el foco.
    var onAccept: (() -> Void)?
    /// Y/triángulo: opciones del juego (Modo Dock).
    var onOptions: (() -> Void)?

    enum Direction {
        case up, down, left, right
    }

    /// Dirección que se mantiene pulsada (cruceta o stick) y su temporizador de repetición.
    private var heldDirection: Direction?
    private var repeatTimer: Timer?
    /// Espera antes de empezar a repetir y ritmo de la repetición (moderado).
    private static let repeatDelay: TimeInterval = 0.42
    private static let repeatInterval: TimeInterval = 0.16

    private var tokens: [NSObjectProtocol] = []

    init() {
        refresh()
        let center = NotificationCenter.default
        let names: [Notification.Name] = [.GCControllerDidConnect, .GCControllerDidDisconnect]
        for name in names {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            })
        }
    }

    deinit {
        tokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func refresh() {
        let list = GCController.controllers()
        controllers = list.enumerated().map { index, controller in
            let level = controller.battery.map { Int(($0.batteryLevel * 100).rounded()) }
            return Info(
                id: "\(index)-\(controller.vendorName ?? "")",
                name: controller.vendorName ?? "Mando",
                category: controller.productCategory,
                battery: level,
                charging: controller.battery?.batteryState == .charging
            )
        }
        list.forEach(bind)
    }

    /// Dirección marcada: manda la cruceta; si está suelta, el stick izquierdo.
    private static func direction(of pad: GCExtendedGamepad) -> Direction? {
        if let dpad = direction(x: pad.dpad.xAxis.value, y: pad.dpad.yAxis.value) {
            return dpad
        }
        return direction(x: pad.leftThumbstick.xAxis.value, y: pad.leftThumbstick.yAxis.value)
    }

    private static func direction(x: Float, y: Float) -> Direction? {
        if abs(x) > abs(y), abs(x) > 0.5 {
            return x < 0 ? .left : .right
        }
        if abs(y) > 0.5 {
            return y < 0 ? .down : .up
        }
        return nil
    }

    /// Un paso al pulsar; tras una pequeña espera, repite mientras siga pulsada.
    private func updateHeld(_ direction: Direction?) {
        guard direction != heldDirection else { return }
        heldDirection = direction
        repeatTimer?.invalidate()
        repeatTimer = nil
        guard let direction, navigationEnabled else { return }
        onDirection?(direction)
        let delay = Timer(timeInterval: Self.repeatDelay, repeats: false) { [weak self] _ in
            self?.startRepeating(direction)
        }
        RunLoop.main.add(delay, forMode: .common)
        repeatTimer = delay
    }

    private func startRepeating(_ direction: Direction) {
        guard heldDirection == direction else { return }
        let timer = Timer(timeInterval: Self.repeatInterval, repeats: true) { [weak self] _ in
            guard let self, self.heldDirection == direction, self.navigationEnabled else { return }
            self.onDirection?(direction)
        }
        RunLoop.main.add(timer, forMode: .common)
        repeatTimer = timer
    }

    private func bind(_ controller: GCController) {
        guard let pad = controller.extendedGamepad else { return }
        pad.leftShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed, self?.navigationEnabled == true else { return }
            self?.onShoulder?(-1)
        }
        pad.rightShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed, self?.navigationEnabled == true else { return }
            self?.onShoulder?(1)
        }
        pad.leftTrigger.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed, self?.navigationEnabled == true else { return }
            self?.onTrigger?(-1)
        }
        pad.rightTrigger.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed, self?.navigationEnabled == true else { return }
            self?.onTrigger?(1)
        }
        // La cruceta y el stick izquierdo se leen juntos: una pulsación mueve un paso y,
        // si se mantiene, sigue moviendo a ritmo moderado.
        pad.dpad.valueChangedHandler = { [weak self, weak pad] _, _, _ in
            guard let self, let pad else { return }
            let direction: Direction? = Self.direction(of: pad)
            DispatchQueue.main.async { self.updateHeld(direction) }
        }
        pad.leftThumbstick.valueChangedHandler = { [weak self, weak pad] _, _, _ in
            guard let self, let pad else { return }
            let direction: Direction? = Self.direction(of: pad)
            DispatchQueue.main.async { self.updateHeld(direction) }
        }
        pad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed, self?.navigationEnabled == true else { return }
            DispatchQueue.main.async { self?.onAccept?() }
        }
        pad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed, self?.navigationEnabled == true else { return }
            DispatchQueue.main.async { self?.onCancel?() }
        }
        pad.buttonY.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed, self?.navigationEnabled == true else { return }
            DispatchQueue.main.async { self?.onOptions?() }
        }
    }
}


/// Estilo común de botones: se encoge un poco al pulsar.
/// No usa el foco de iOS: el mando tiene su propia selección, y el foco de iOS hacía que
/// apareciera un recuadro al tocar sin mando y que algunos toques solo enfocaran sin pulsar.
struct ControllerFocusableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Tarjetas: mientras se mantiene pulsada, se remarca con un borde cian.
struct TapHighlightButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 18

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                if configuration.isPressed {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.cyan.opacity(0.95), lineWidth: 2)
                        .shadow(color: Color.cyan.opacity(0.6), radius: 8)
                        .allowsHitTesting(false)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Tipografías

/// Orbitron (la de la bienvenida y la barra de plataformas) y Space Grotesk.
/// Los archivos van en Resources/Fonts y se registran al arrancar la app.
enum AppFont {
    /// Prueba de la versión 0.1.8: Orbitron para todo. En `false` vuelve Space Grotesk para el texto.
    static let useBrandEverywhere = true
    /// Orbitron es muy ancha: el texto normal se pinta algo más pequeño para que quepa igual.
    private static let brandTextScale: CGFloat = 0.88

    private static let files: [String] = [
        "Orbitron-Regular", "Orbitron-Medium", "Orbitron-SemiBold", "Orbitron-Bold", "Orbitron-ExtraBold",
        "SpaceGrotesk-Regular", "SpaceGrotesk-Medium", "SpaceGrotesk-SemiBold", "SpaceGrotesk-Bold"
    ]

    static func register() {
        for name in files {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    private static func orbitronName(_ weight: Font.Weight) -> String {
        if weight == .heavy || weight == .black {
            return "Orbitron-ExtraBold"
        } else if weight == .bold {
            return "Orbitron-Bold"
        } else if weight == .semibold {
            return "Orbitron-SemiBold"
        } else if weight == .medium {
            return "Orbitron-Medium"
        }
        return "Orbitron-Regular"
    }

    private static func groteskName(_ weight: Font.Weight) -> String {
        if weight == .bold || weight == .heavy || weight == .black {
            return "SpaceGrotesk-Bold"
        } else if weight == .semibold {
            return "SpaceGrotesk-SemiBold"
        } else if weight == .medium {
            return "SpaceGrotesk-Medium"
        }
        return "SpaceGrotesk-Regular"
    }

    /// Orbitron (marca: bienvenida, título y barra de plataformas).
    static func brand(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        Font.custom(orbitronName(weight), fixedSize: size)
    }

    /// Texto normal: Orbitron mientras dure la prueba, si no Space Grotesk.
    static func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        if useBrandEverywhere {
            return Font.custom(orbitronName(weight), fixedSize: (size * brandTextScale).rounded())
        }
        return Font.custom(groteskName(weight), fixedSize: size)
    }
}

// MARK: - Depuración (JIT, StikDebug y LiveContainer)

enum DebugSupport {
    /// Firma de csops, la función del sistema que informa del estado de firma del proceso.
    private typealias CSOpsFunction = @convention(c) (Int32, UInt32, UnsafeMutableRawPointer?, Int) -> Int32

    /// JIT activo en esta app: el sistema marca el proceso como depurado (CS_DEBUGGED).
    /// csops se busca en tiempo de ejecución (dlsym), sin declaraciones especiales.
    static var isJITEnabled: Bool {
        // RTLD_DEFAULT vale -2 en Apple: busca en todas las librerías cargadas.
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "csops") else { return false }
        let csops: CSOpsFunction = unsafeBitCast(symbol, to: CSOpsFunction.self)
        var flags: UInt32 = 0
        let result: Int32 = withUnsafeMutablePointer(to: &flags) { pointer in
            csops(getpid(), 0, UnsafeMutableRawPointer(pointer), MemoryLayout<UInt32>.size)
        }
        return result == 0 && (flags & 0x1000_0000) != 0
    }

    /// LiveContainer define LC_HOME_PATH en las apps que ejecuta dentro.
    static var isInsideLiveContainer: Bool {
        getenv("LC_HOME_PATH") != nil
    }

    static var bundleID: String {
        Bundle.main.bundleIdentifier ?? "com.omnistation.dock"
    }

    /// Pide a StikDebug que active JIT en esta app ya abierta (por su número de proceso).
    static var enableJITURL: URL? {
        URL(string: "stikjit://enable-jit?pid=\(getpid())")
    }

    static let stikDebugURL: URL? = URL(string: "stikjit://")
    static let liveContainerURL: URL? = URL(string: "livecontainer://")
    /// Enlace para abrir una app instalada dentro de LiveContainer (se completa con su nombre).
    static let liveContainerLaunchPrefix = "livecontainer://livecontainer-launch?bundle-name="
}

// MARK: - Batería

final class BatteryMonitor: ObservableObject {
    /// Porcentaje de 0 a 100, o -1 si el sistema no lo da.
    @Published private(set) var level: Int = -1
    @Published private(set) var charging = false
    private var tokens: [NSObjectProtocol] = []

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        update()
        let center = NotificationCenter.default
        let names: [Notification.Name] = [UIDevice.batteryLevelDidChangeNotification, UIDevice.batteryStateDidChangeNotification]
        for name in names {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.update()
            })
        }
    }

    deinit {
        tokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func update() {
        let raw: Float = UIDevice.current.batteryLevel
        level = raw < 0 ? -1 : Int((raw * 100).rounded())
        let state: UIDevice.BatteryState = UIDevice.current.batteryState
        charging = state == .charging || state == .full
    }

    var symbolName: String {
        if charging { return "battery.100percent.bolt" }
        switch level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

// MARK: - Desplazamiento y medidas de la interfaz

/// Desplazamiento vertical de la pantalla actual. Solo lo observa el título de la cabecera:
/// así deslizar no repinta toda la interfaz con todas sus tarjetas.
final class ScrollProgress: ObservableObject {
    @Published private(set) var offset: CGFloat = 0
    /// Pantalla que manda. Al cambiar de pestaña la pantalla anterior sigue un momento en
    /// pantalla (la transición) y no debe poder esconder el título de la nueva.
    private(set) var owner: String = "Inicio"

    /// Pasa el control a otra pantalla, que empieza arriba del todo.
    func activate(_ newOwner: String) {
        owner = newOwner
        if offset != 0 { offset = 0 }
    }

    /// Desplazamiento que informa una pantalla concreta (se ignora si no es la activa).
    func set(_ value: CGFloat, from source: String) {
        guard source == owner else { return }
        set(value)
    }

    func set(_ value: CGFloat) {
        // Más allá de 80 puntos el título ya está oculto: no hace falta seguir avisando.
        let limited: CGFloat = min(max(0, value), 80)
        if abs(limited - offset) > 0.5 || (limited == 0 && offset != 0) {
            offset = limited
        }
    }
}

/// Medidas de la cabecera y del área de scroll. Solo avisa cuando cambian de verdad.
final class LayoutMetrics: ObservableObject {
    @Published private(set) var headerHeight: CGFloat = 57
    @Published private(set) var fadeClear: CGFloat = 0
    private(set) var frames: [String: CGRect] = [:]

    /// Guarda las medidas y devuelve cuánto ha subido el contenido (si se ha medido).
    func update(_ newFrames: [String: CGRect]) -> CGFloat? {
        frames = newFrames
        guard let header = newFrames["header"] else { return nil }
        if abs(header.height - headerHeight) > 0.5 {
            headerHeight = header.height
        }
        if let scroll = newFrames["scroll"] {
            let clear: CGFloat = max(0, header.minY - scroll.minY)
            if abs(clear - fadeClear) > 0.5 {
                fadeClear = clear
            }
        }
        guard let content = newFrames["content"] else { return nil }
        return header.minY - content.minY
    }
}

enum ScrollSupport {
    /// iOS 18 da el desplazamiento directamente; en iOS 17 se calcula con las medidas.
    static var hasScrollGeometry: Bool {
        if #available(iOS 18.0, *) {
            return true
        }
        return false
    }
}

/// Lee el desplazamiento del ScrollView en iOS 18 (más fiable que medir marcos).
struct ScrollOffsetReader: ViewModifier {
    let progress: ScrollProgress
    /// Pantalla a la que pertenece este scroll.
    let owner: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, newValue in
                progress.set(newValue, from: owner)
            }
        } else {
            content
        }
    }
}

// MARK: - Medidas y bordes

struct FramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Mide la posición en pantalla de esta vista y la publica con un nombre.
    func reportFrame(_ id: String) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: FramesKey.self, value: [id: proxy.frame(in: .global)])
            }
        }
    }

    /// Igual que `reportFrame`, pero solo mide si `condition` es verdadera.
    func reportFrame(_ id: String, if condition: Bool) -> some View {
        background {
            if condition {
                GeometryReader { proxy in
                    Color.clear.preference(key: FramesKey.self, value: [id: proxy.frame(in: .global)])
                }
            }
        }
    }

    /// Desvanece el contenido por arriba (detrás de la barra superior) y por abajo.
    /// `clear`: zona de arriba donde no se ve nada; `fade`: puntos de degradado superior;
    /// `bottom`: puntos de degradado inferior.
    func edgeFade(clear: CGFloat, fade: CGFloat, bottom: CGFloat) -> some View {
        mask {
            VStack(spacing: 0) {
                Color.clear.frame(height: clear)
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.35), location: 0.5),
                        .init(color: .black, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: fade)
                Rectangle().fill(.black)
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black.opacity(0.35), location: 0.5),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: bottom)
            }
        }
    }
}

// MARK: - Cristal líquido

extension View {
    func glassCard(cornerRadius: CGFloat = 18, interactive: Bool = false) -> some View {
        liquidGlass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), interactive: interactive)
    }

    /// Cristal líquido. En iOS 26, compilando con Xcode 26, usa el `glassEffect` nativo de Apple;
    /// en el resto, una imitación con material translúcido, reflejos y borde de luz.
    @ViewBuilder
    func liquidGlass<S: InsettableShape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            glassEffect(nativeGlass(tint: tint, interactive: interactive), in: shape)
        } else {
            modifier(LiquidGlassFallback(shape: shape, tint: tint))
        }
        #else
        modifier(LiquidGlassFallback(shape: shape, tint: tint))
        #endif
    }

    /// Solo el borde de luz y el reflejo superior (sin fondo), para paneles que ya tienen el suyo.
    func glassRim<S: InsettableShape>(in shape: S) -> some View {
        modifier(LiquidGlassRim(shape: shape))
    }

    #if compiler(>=6.2)
    @available(iOS 26.0, *)
    private func nativeGlass(tint: Color?, interactive: Bool) -> Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint.opacity(0.55)) }
        if interactive { glass = glass.interactive() }
        return glass
    }
    #endif
}

private struct LiquidGlassRim<S: InsettableShape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        content
            .overlay { sheen }
            .overlay { rim }
    }

    // Reflejo suave en la mitad superior.
    private var sheen: some View {
        shape
            .fill(LinearGradient(
                colors: [Color.white.opacity(0.16), Color.white.opacity(0)],
                startPoint: .top,
                endPoint: .center
            ))
            .allowsHitTesting(false)
    }

    // Borde de luz: brillante arriba a la izquierda, tenue en medio, un destello abajo a la derecha.
    private var rim: some View {
        shape
            .strokeBorder(
                LinearGradient(
                    stops: [
                        Gradient.Stop(color: Color.white.opacity(0.60), location: 0),
                        Gradient.Stop(color: Color.white.opacity(0.10), location: 0.38),
                        Gradient.Stop(color: Color.cyan.opacity(0.16), location: 0.72),
                        Gradient.Stop(color: Color.white.opacity(0.34), location: 1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
            .allowsHitTesting(false)
    }
}

private struct LiquidGlassFallback<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?

    func body(content: Content) -> some View {
        content
            .background { glassFill }
            .modifier(LiquidGlassRim(shape: shape))
    }

    private var glassFill: some View {
        ZStack {
            shape.fill(.ultraThinMaterial)
            shape.fill(tintGradient)
        }
    }

    private var tintGradient: LinearGradient {
        if let tint {
            return LinearGradient(
                colors: [tint.opacity(0.80), tint.opacity(0.38)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [Color.blue.opacity(0.09), Color.black.opacity(0.22)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
