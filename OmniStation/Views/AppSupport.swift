import SwiftUI
import UIKit
import GameController
import AudioToolbox

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
        "Listo": "Done"
    ]
}

// MARK: - Plataformas

enum Platforms {
    static let all: [(name: String, symbol: String)] = [
        ("Todos", "square.grid.2x2.fill"),
        ("PS2", "gamecontroller.fill"),
        ("PSP", "gamecontroller"),
        ("GameCube", "cube.fill"),
        ("Wii", "gamecontroller"),
        ("Switch", "rectangle.on.rectangle"),
        ("3DS", "square.3.layers.3d"),
        ("NDS", "rectangle.portrait"),
        ("GBA", "gameboy")
    ]

    /// Todas menos «Todos» (las que se pueden reordenar).
    static var movableNames: [String] { all.dropFirst().map(\.name) }

    static func symbol(for name: String) -> String {
        all.first { $0.name == name }?.symbol ?? "gamecontroller.fill"
    }

    static func tint(for name: String) -> Color {
        switch name {
        case "PS2": return Color(red: 0.05, green: 0.42, blue: 1.0)
        case "PSP": return Color(red: 0.10, green: 0.30, blue: 0.78)
        case "GameCube": return Color(red: 0.06, green: 0.58, blue: 0.95)
        case "Wii": return Color(red: 0.00, green: 0.72, blue: 1.0)
        case "Switch": return Color(red: 0.10, green: 0.46, blue: 1.0)
        case "3DS": return Color(red: 0.16, green: 0.82, blue: 1.0)
        case "NDS": return Color(red: 0.10, green: 0.46, blue: 1.0)
        default: return Color(red: 0.00, green: 0.72, blue: 1.0)
        }
    }

    /// Orden guardado (nombres separados por "|") completado con las plataformas que falten.
    static func ordered(_ raw: String) -> [String] {
        let known = movableNames
        var result: [String] = []
        for name in raw.split(separator: "|").map(String.init) where known.contains(name) && !result.contains(name) {
            result.append(name)
        }
        for name in known where !result.contains(name) {
            result.append(name)
        }
        return result
    }
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

enum LibraryScanner {
    /// Extensión de archivo -> plataforma más probable.
    static let extensionMap: [String: String] = [
        "gba": "GBA",
        "nds": "NDS",
        "3ds": "3DS", "cia": "3DS", "cci": "3DS", "cxi": "3DS",
        "gcm": "GameCube", "gcz": "GameCube", "ciso": "GameCube", "rvz": "GameCube",
        "wbfs": "Wii", "wad": "Wii",
        "nsp": "Switch", "xci": "Switch", "nsz": "Switch",
        "cso": "PSP", "pbp": "PSP",
        "iso": "PS2", "chd": "PS2", "cue": "PS2"
    ]

    /// Si una carpeta del camino se llama como una plataforma, manda sobre la extensión.
    private static func platformHint(from folders: [String]) -> String? {
        for folder in folders.reversed() {
            switch folder.lowercased() {
            case "ps2", "playstation 2", "playstation2": return "PS2"
            case "psp": return "PSP"
            case "gamecube", "gc", "ngc": return "GameCube"
            case "wii": return "Wii"
            case "switch", "nsw": return "Switch"
            case "3ds", "n3ds": return "3DS"
            case "nds", "ds": return "NDS"
            case "gba", "gameboy advance": return "GBA"
            default: continue
            }
        }
        return nil
    }

    static func scan(folder: URL, limit: Int = 20000) -> [LibraryGame] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        let baseCount = folder.standardizedFileURL.pathComponents.count
        var found: [String: LibraryGame] = [:]
        var visited = 0

        for case let url as URL in enumerator {
            visited += 1
            if visited > limit { break }
            guard let basePlatform = extensionMap[url.pathExtension.lowercased()] else { continue }
            let folders = Array(url.standardizedFileURL.pathComponents.dropFirst(baseCount).dropLast())
            let platform = platformHint(from: folders) ?? basePlatform
            let name = url.deletingPathExtension().lastPathComponent
            let id = "\(platform)/\(name)"
            if found[id] == nil {
                found[id] = LibraryGame(id: id, name: name, platform: platform, launchURL: nil, source: "scan")
            }
        }
        return found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Fondo personalizado

enum BackgroundStore {
    private static var fileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("custom_background.jpg")
    }

    static func load() -> UIImage? {
        UIImage(contentsOfFile: fileURL.path)
    }

    /// Reduce la imagen (máx. 2200 px) y la guarda como JPEG.
    static func save(_ data: Data) -> Bool {
        guard let image = UIImage(data: data) else { return false }
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, 2200 / longest)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpeg = resized.jpegData(compressionQuality: 0.85) else { return false }
        do {
            try jpeg.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func remove() {
        try? FileManager.default.removeItem(at: fileURL)
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

    enum Direction {
        case up, down, left, right
    }

    private var lastDirectionAt: TimeInterval = 0
    private var lastDirection: Direction?

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
        // La cruceta debe registrarse explícitamente: focusable() por sí solo no
        // convierte los eventos de GCController en navegación SwiftUI en iOS.
        pad.dpad.valueChangedHandler = { [weak self] _, x, y in
            guard let self, self.navigationEnabled else { return }
            let direction: Direction?
            if abs(x) > abs(y), abs(x) > 0.5 {
                direction = x < 0 ? .left : .right
            } else if abs(y) > 0.5 {
                direction = y < 0 ? .down : .up
            } else {
                direction = nil
            }
            guard let direction else {
                self.lastDirection = nil
                return
            }
            let now = ProcessInfo.processInfo.systemUptime
            // Un paso al pulsar y repetición moderada si se mantiene la dirección.
            guard direction != self.lastDirection || now - self.lastDirectionAt > 0.32 else { return }
            self.lastDirection = direction
            self.lastDirectionAt = now
            DispatchQueue.main.async { self.onDirection?(direction) }
        }
        pad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed, self?.navigationEnabled == true else { return }
            DispatchQueue.main.async { self?.onAccept?() }
        }
        pad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed, self?.navigationEnabled == true else { return }
            DispatchQueue.main.async { self?.onCancel?() }
        }
    }
}


/// Estilo común para que el foco del mando sea visible en botones de toda la app.
struct ControllerFocusableButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.cyan.opacity(0.98), lineWidth: 2.5)
                        .shadow(color: Color.cyan.opacity(0.72), radius: 9)
                        .padding(-3)
                        .allowsHitTesting(false)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.97 : (isFocused ? 1.015 : 1.0))
            .animation(.easeOut(duration: 0.12), value: isFocused)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
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
