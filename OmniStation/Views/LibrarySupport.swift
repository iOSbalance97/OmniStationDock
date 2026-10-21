import SwiftUI
import UIKit

// MARK: - Plataformas

enum Platforms {
    typealias Entry = (name: String, symbol: String)

    static let todos: Entry = ("Todos", "square.grid.2x2.fill")

    /// Siempre visibles en la barra de plataformas.
    static let core: [Entry] = [
        ("PS2", "gamecontroller.fill"),
        ("PSP", "gamecontroller"),
        ("GameCube", "cube.fill"),
        ("Wii", "gamecontroller"),
        ("Switch", "rectangle.on.rectangle"),
        ("3DS", "square.3.layers.3d"),
        ("NDS", "rectangle.portrait"),
        ("GBA", "gameboy"),
        ("Juegos iOS", "apps.iphone"),
        ("Ports", "shippingbox.fill")
    ]

    /// Las reconoce la carpeta externa; su filtro solo aparece cuando hay juegos suyos.
    static let extended: [Entry] = [
        ("PS1", "gamecontroller.fill"),
        ("PS3", "gamecontroller.fill"),
        ("N64", "gamecontroller"),
        ("SNES", "gamecontroller"),
        ("NES", "gamecontroller"),
        ("Game Boy", "rectangle.portrait"),
        ("Game Boy Color", "rectangle.portrait"),
        ("Mega Drive", "gamecontroller"),
        ("Master System", "gamecontroller"),
        ("Game Gear", "rectangle.portrait"),
        ("Dreamcast", "circle.circle"),
        ("Saturn", "circle.hexagongrid.fill")
    ]

    /// Iconos que se pueden elegir al crear una plataforma.
    static let symbolChoices: [String] = [
        "gamecontroller.fill", "gamecontroller", "arcade.stick", "cube.fill",
        "tv.fill", "rectangle.portrait", "star.fill", "flame.fill",
        "bolt.fill", "sparkles", "globe", "shippingbox.fill"
    ]

    static let customKey = "customPlatforms"
    /// Plataformas ocultas en la barra (nombres separados por "|").
    static let hiddenKey = "hiddenPlatforms"

    static func hidden(_ raw: String) -> Set<String> {
        Set(raw.split(separator: "|").map(String.init))
    }

    static func encodeHidden(_ names: Set<String>) -> String {
        names.sorted().joined(separator: "|")
    }

    /// Plataformas encendidas a mano (las de la carpeta externa salen aunque no tengan juegos).
    static let shownKey = "shownPlatforms"

    /// ¿Sale en la barra? Manda el interruptor; si nunca se tocó: las fijas y las tuyas siempre,
    /// las de la carpeta externa solo cuando tienen juegos.
    static func isVisible(_ name: String, hidden: Set<String>, shown: Set<String>, present: Set<String>) -> Bool {
        if hidden.contains(name) { return false }
        if shown.contains(name) { return true }
        return !isExtended(name) || present.contains(name)
    }

    /// Plataformas creadas por el usuario, guardadas como "Nombre::icono|Nombre::icono".
    static func parse(_ raw: String) -> [Entry] {
        var result: [Entry] = []
        for chunk in raw.split(separator: "|") {
            let parts = chunk.components(separatedBy: "::")
            guard let name = parts.first, !name.isEmpty else { continue }
            let symbol: String = parts.count > 1 ? parts[1] : "gamecontroller.fill"
            result.append((name: name, symbol: symbol))
        }
        return result
    }

    static func encode(_ list: [Entry]) -> String {
        list.map { "\($0.name)::\($0.symbol)" }.joined(separator: "|")
    }

    static var custom: [Entry] {
        parse(UserDefaults.standard.string(forKey: customKey) ?? "")
    }

    static func builtInNames() -> [String] {
        (core + extended).map(\.name) + [todos.name]
    }

    /// Todas las plataformas (sin «Todos»), con las del usuario.
    static func movableNames(customRaw: String) -> [String] {
        (core + extended + parse(customRaw)).map(\.name)
    }

    static var movableNames: [String] {
        movableNames(customRaw: UserDefaults.standard.string(forKey: customKey) ?? "")
    }

    static func isExtended(_ name: String) -> Bool {
        extended.contains { $0.name == name }
    }

    /// Nombre completo de la plataforma (para la pantalla del juego).
    static func fullName(for name: String) -> String {
        switch name {
        case "PS1": return "PlayStation"
        case "PS2": return "PlayStation 2"
        case "PS3": return "PlayStation 3"
        case "PSP": return "PlayStation Portable"
        case "GameCube": return "Nintendo GameCube"
        case "Wii": return "Nintendo Wii"
        case "Switch": return "Nintendo Switch"
        case "3DS": return "Nintendo 3DS"
        case "NDS": return "Nintendo DS"
        case "GBA": return "Game Boy Advance"
        case "N64": return "Nintendo 64"
        case "SNES": return "Super Nintendo"
        case "NES": return "Nintendo Entertainment System"
        case "Mega Drive": return "Sega Mega Drive"
        case "Master System": return "Sega Master System"
        case "Game Gear": return "Sega Game Gear"
        case "Dreamcast": return "Sega Dreamcast"
        case "Saturn": return "Sega Saturn"
        default: return name
        }
    }

    static func symbol(for name: String) -> String {
        if name == todos.name { return todos.symbol }
        let list: [Entry] = core + extended + custom
        return list.first { $0.name == name }?.symbol ?? "gamecontroller.fill"
    }

    static func tint(for name: String) -> Color {
        switch name {
        case "PS2", "PS1", "PS3": return Color(red: 0.05, green: 0.42, blue: 1.0)
        case "PSP": return Color(red: 0.10, green: 0.30, blue: 0.78)
        case "GameCube", "Wii": return Color(red: 0.06, green: 0.58, blue: 0.95)
        case "Switch", "NDS": return Color(red: 0.10, green: 0.46, blue: 1.0)
        case "3DS": return Color(red: 0.16, green: 0.82, blue: 1.0)
        case "Juegos iOS": return Color(red: 0.30, green: 0.60, blue: 1.0)
        case "Ports": return Color(red: 0.42, green: 0.40, blue: 1.0)
        default: return Color(red: 0.00, green: 0.72, blue: 1.0)
        }
    }

    /// Orden guardado (nombres separados por "|") completado con las plataformas que falten.
    static func ordered(_ raw: String, customRaw: String) -> [String] {
        let known: [String] = movableNames(customRaw: customRaw)
        var result: [String] = []
        for name in raw.split(separator: "|").map(String.init) where known.contains(name) && !result.contains(name) {
            result.append(name)
        }
        for name in known where !result.contains(name) {
            result.append(name)
        }
        return result
    }

    static func ordered(_ raw: String) -> [String] {
        ordered(raw, customRaw: UserDefaults.standard.string(forKey: customKey) ?? "")
    }
}

// MARK: - Imágenes

enum ImageResizer {
    /// Reduce la imagen (lado mayor como máximo `maxSide`) y la devuelve en JPEG.
    static func jpeg(from data: Data, maxSide: CGFloat, quality: CGFloat = 0.85) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest: CGFloat = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale: CGFloat = min(1, maxSide / longest)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized: UIImage = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}

enum AppFolders {
    /// Carpeta propia dentro de Application Support (se crea si no existe).
    static func folder(_ name: String) -> URL {
        let base: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url: URL = base.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Nombre de archivo seguro a partir de cualquier texto (por ejemplo, el id de un juego).
    static func safeName(_ text: String) -> String {
        text.utf8.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Carátulas

/// Carátulas de los juegos: se guardan en disco y se mantienen en memoria para pintar rápido.
final class CoverStore {
    static let shared = CoverStore()

    private let cache = NSCache<NSString, UIImage>()

    /// Suelta las imágenes en memoria (se vuelven a leer del disco): antes de una partida.
    func purgeMemory() {
        cache.removeAllObjects()
    }
    private var missing = Set<String>()

    private func fileURL(for id: String) -> URL {
        AppFolders.folder("Covers").appendingPathComponent(AppFolders.safeName(id) + ".jpg")
    }

    func image(for id: String) -> UIImage? {
        if let cached = cache.object(forKey: id as NSString) { return cached }
        if missing.contains(id) { return nil }
        guard let file = UIImage(contentsOfFile: fileURL(for: id).path) else {
            missing.insert(id)
            return nil
        }
        // Se descomprime una vez aquí y no cada vez que se dibuja (daba tirones al mover el carrusel).
        let image: UIImage = file.preparingForDisplay() ?? file
        cache.setObject(image, forKey: id as NSString)
        return image
    }

    @discardableResult
    func save(_ data: Data, for id: String) -> Bool {
        guard let jpeg = ImageResizer.jpeg(from: data, maxSide: 900) else { return false }
        do {
            try jpeg.write(to: fileURL(for: id), options: .atomic)
        } catch {
            return false
        }
        cache.removeObject(forKey: id as NSString)
        missing.remove(id)
        return true
    }

    func remove(for id: String) {
        try? FileManager.default.removeItem(at: fileURL(for: id))
        cache.removeObject(forKey: id as NSString)
        missing.insert(id)
    }
}

// MARK: - Datos propios de cada juego

/// Lo que el usuario cambia de un juego: nombre, plataforma, ID de RetroAchievements y botones.
struct GameMeta: Codable, Equatable {
    var name: String?
    var platform: String?
    var raGameID: Int?
    var buttonMap: [String: String]?
    /// nil = lo que diga el ajuste general «JIT al abrir juegos».
    var useJIT: Bool?
    /// Bundle ID del juego para pedir el JIT a StikDebug (SideStore/AltStore).
    var bundleID: String?
    /// Script de JIT con TXM: "auto", "universal", "legacy" o "none" (nil = automático).
    var jitScript: String?
    /// Cómo lo llama su emulador: Title ID o título exacto (MeloNX).
    var emulatorGameID: String?
}

enum GameMetaStore {
    private static var fileURL: URL {
        AppFolders.folder("Library").appendingPathComponent("game-meta.json")
    }

    static func load() -> [String: GameMeta] {
        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONDecoder().decode([String: GameMeta].self, from: data) else { return [:] }
        return dict
    }

    static func save(_ dict: [String: GameMeta]) {
        guard let data = try? JSONEncoder().encode(dict) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Aplica los cambios del usuario a un juego (el id no cambia nunca).
    static func apply(_ meta: GameMeta?, to game: Game) -> Game {
        guard let meta else { return game }
        let platform: String = meta.platform ?? game.platform
        let name: String = (meta.name?.isEmpty == false) ? (meta.name ?? game.name) : game.name
        let platformChanged: Bool = platform != game.platform
        return Game(
            id: game.id,
            name: name,
            platform: platform,
            symbol: platformChanged ? Platforms.symbol(for: platform) : game.symbol,
            tint: platformChanged ? Platforms.tint(for: platform) : game.tint,
            launchURL: game.launchURL,
            isCustom: game.isCustom
        )
    }
}

// MARK: - Carpeta externa: ROMs de todas las plataformas

enum LibraryScanner {
    /// Extensión de archivo -> plataforma más probable.
    static let extensionMap: [String: String] = [
        "gba": "GBA",
        "gb": "Game Boy",
        "gbc": "Game Boy Color",
        "nds": "NDS",
        "3ds": "3DS", "cia": "3DS", "cci": "3DS", "cxi": "3DS",
        "nes": "NES", "fds": "NES",
        "sfc": "SNES", "smc": "SNES",
        "n64": "N64", "z64": "N64", "v64": "N64",
        "gcm": "GameCube", "gcz": "GameCube", "ciso": "GameCube", "rvz": "GameCube",
        "wbfs": "Wii", "wad": "Wii",
        "nsp": "Switch", "xci": "Switch", "nsz": "Switch",
        "cso": "PSP", "pbp": "PSP",
        "iso": "PS2", "chd": "PS2",
        "cue": "PS1", "m3u": "PS1", "bin": "PS1",
        "md": "Mega Drive", "gen": "Mega Drive", "smd": "Mega Drive",
        "sms": "Master System",
        "gg": "Game Gear",
        "gdi": "Dreamcast", "cdi": "Dreamcast"
    ]

    /// Si una carpeta del camino se llama como una plataforma, manda sobre la extensión.
    private static func platformHint(from folders: [String]) -> String? {
        for folder in folders.reversed() {
            switch folder.lowercased() {
            case "ps1", "psx", "playstation", "playstation 1": return "PS1"
            case "ps2", "playstation 2", "playstation2": return "PS2"
            case "ps3", "playstation 3": return "PS3"
            case "psp": return "PSP"
            case "gamecube", "gc", "ngc": return "GameCube"
            case "wii": return "Wii"
            case "switch", "nsw": return "Switch"
            case "3ds", "n3ds": return "3DS"
            case "nds", "ds": return "NDS"
            case "gba", "gameboy advance", "game boy advance": return "GBA"
            case "gb", "gameboy", "game boy": return "Game Boy"
            case "gbc", "gameboy color", "game boy color": return "Game Boy Color"
            case "nes", "famicom": return "NES"
            case "snes", "super nintendo", "sfc": return "SNES"
            case "n64", "nintendo 64": return "N64"
            case "genesis", "megadrive", "mega drive", "md": return "Mega Drive"
            case "mastersystem", "master system", "sms": return "Master System"
            case "gamegear", "game gear", "gg": return "Game Gear"
            case "dreamcast", "dc": return "Dreamcast"
            case "saturn": return "Saturn"
            case "ports": return "Ports"
            default: continue
            }
        }
        return nil
    }

    /// Carpeta propia de un emulador: todos sus juegos van a su plataforma.
    static func scan(folder: URL, emulator: Emulator, limit: Int = 40000) -> [LibraryGame] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        let extensions: Set<String> = Set(emulator.extensions)
        let source: String = "emu:" + emulator.rawValue
        var found: [String: LibraryGame] = [:]
        var visited: Int = 0
        // Switch: las actualizaciones y DLC no son juegos; van dentro de su juego.
        var switchFiles: SwitchScanCollector? = emulator == .melonx ? SwitchScanCollector(source: source) : nil
        for case let url as URL in enumerator {
            visited += 1
            if visited > limit { break }
            // Las copias que hace iOS al abrir archivos con la app no son juegos nuevos.
            if url.lastPathComponent == "Inbox" { enumerator.skipDescendants(); continue }
            guard extensions.contains(url.pathExtension.lowercased()) else { continue }
            let name: String = url.deletingPathExtension().lastPathComponent
            let id = "\(emulator.platform)/\(name)"
            if switchFiles != nil, switchFiles?.accept(url, gameID: id) == false { continue }
            if found[id] == nil {
                found[id] = LibraryGame(id: id, name: name, platform: emulator.platform, launchURL: nil,
                                        source: source, fileName: url.lastPathComponent)
            }
        }
        switchFiles?.save()
        return found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func scan(folder: URL, limit: Int = 40000) -> [LibraryGame] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        let baseCount: Int = folder.standardizedFileURL.pathComponents.count
        var found: [String: LibraryGame] = [:]
        var visited: Int = 0

        for case let url as URL in enumerator {
            visited += 1
            if visited > limit { break }
            guard let basePlatform = extensionMap[url.pathExtension.lowercased()] else { continue }
            let folders: [String] = Array(url.standardizedFileURL.pathComponents.dropFirst(baseCount).dropLast())
            let platform: String = platformHint(from: folders) ?? basePlatform
            let name: String = url.deletingPathExtension().lastPathComponent
            let id = "\(platform)/\(name)"
            if found[id] == nil {
                found[id] = LibraryGame(id: id, name: name, platform: platform, launchURL: nil, source: "scan", fileName: url.lastPathComponent)
            }
        }
        return found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Juegos iOS instalados

/// iOS no deja que una app liste las apps instaladas. Lo que sí permite es preguntar si hay
/// alguna app que abra un enlace concreto, siempre que ese enlace esté declarado en
/// LSApplicationQueriesSchemes (Config/AppInfo.plist, máximo 50). Esta lista se comprueba así.
enum IOSGameCatalog {
    struct Entry {
        let name: String
        let scheme: String
    }

    static let entries: [Entry] = [
        Entry(name: "Minecraft", scheme: "minecraft"),
        Entry(name: "Roblox", scheme: "roblox"),
        Entry(name: "Clash of Clans", scheme: "clashofclans"),
        Entry(name: "Clash Royale", scheme: "clashroyale"),
        Entry(name: "Brawl Stars", scheme: "brawlstars"),
        Entry(name: "Hay Day", scheme: "hayday"),
        Entry(name: "Boom Beach", scheme: "boombeach"),
        Entry(name: "Squad Busters", scheme: "squadbusters"),
        Entry(name: "Fortnite", scheme: "fortnite"),
        Entry(name: "PUBG Mobile", scheme: "pubgmobile"),
        Entry(name: "Call of Duty: Mobile", scheme: "codm"),
        Entry(name: "Genshin Impact", scheme: "yuanshengame"),
        Entry(name: "Pokémon GO", scheme: "pokemongo"),
        Entry(name: "Among Us", scheme: "amongus"),
        Entry(name: "Asphalt 9", scheme: "asphalt9"),
        Entry(name: "Subway Surfers", scheme: "subwaysurfers"),
        Entry(name: "Candy Crush Saga", scheme: "candycrushsaga"),
        Entry(name: "Clash Mini", scheme: "clashmini"),
        Entry(name: "Steam Link", scheme: "steamlink"),
        Entry(name: "Xbox", scheme: "xbox")
    ]

    /// Comprueba la lista y devuelve los juegos encontrados para «Juegos iOS».
    @MainActor
    static func installed() -> [LibraryGame] {
        var result: [LibraryGame] = []
        for entry in entries {
            guard let url = URL(string: "\(entry.scheme)://") else { continue }
            if UIApplication.shared.canOpenURL(url) {
                result.append(LibraryGame(
                    id: "Juegos iOS/\(entry.name)",
                    name: entry.name,
                    platform: "Juegos iOS",
                    launchURL: "\(entry.scheme)://",
                    source: "ios"
                ))
            }
        }
        return result
    }
}
