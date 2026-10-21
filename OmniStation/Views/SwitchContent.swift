import Foundation

// MARK: - Juegos, actualizaciones y DLC de Switch
//
// Las actualizaciones y los DLC también son archivos .nsp: si no se distinguen, salen en la
// biblioteca como si fuesen juegos. Aquí se mira qué es cada archivo sin claves ni descifrar nada:
// • En un .nsp (contenedor PFS0) el ticket se llama «<Rights ID>.tik»; los 16 primeros dígitos del
//   Rights ID son el Title ID del contenido.
// • Si no lleva ticket, el Title ID entre corchetes del nombre ([0100…]).
// El Title ID dice qué es: …000 juego, …800 actualización y el resto DLC (base + 0x1000 + n).

enum SwitchContentKind: String, Codable {
    case game, update, dlc
}

struct SwitchFileInfo {
    var titleID: String?
    var kind: SwitchContentKind
    /// Versión que lleva el nombre ([v65536]); nil si no la lleva.
    var version: Int?

    /// Title ID del juego al que pertenece (el propio en un juego).
    var baseTitleID: String? {
        guard let titleID, let value = UInt64(titleID, radix: 16) else { return nil }
        switch kind {
        case .game: return String(format: "%016llx", value & ~UInt64(0xFFF))
        case .update: return String(format: "%016llx", value & ~UInt64(0xFFF))
        case .dlc: return String(format: "%016llx", (value & ~UInt64(0xFFF)) &- 0x1000)
        }
    }
}

enum SwitchContent {
    static func kind(of titleID: String) -> SwitchContentKind {
        guard let value = UInt64(titleID, radix: 16) else { return .game }
        let low: UInt64 = value & 0xFFF
        if low == 0x800 { return .update }
        // Algunos juegos tienen varios programas (…000 a …00F).
        if low < 0x010 { return .game }
        return .dlc
    }

    /// Qué es un archivo de Switch (lee solo la cabecera).
    static func info(for url: URL) -> SwitchFileInfo {
        let name: String = url.lastPathComponent
        var titleID: String? = nil
        if url.pathExtension.lowercased() == "nsp" {
            titleID = ticketTitleID(url)
        }
        if titleID == nil { titleID = Emulator.titleID(in: name) }
        let version: Int? = versionTag(in: name)
        var kind: SwitchContentKind = titleID.map { SwitchContent.kind(of: $0) } ?? .game
        if titleID == nil {
            // Sin Title ID: solo el nombre del archivo.
            let lower: String = name.lowercased()
            if lower.contains("[upd]") || lower.contains("[update]") || lower.contains(" update") {
                kind = .update
            } else if lower.contains("[dlc]") {
                kind = .dlc
            }
        }
        return SwitchFileInfo(titleID: titleID, kind: kind, version: version)
    }

    /// «[v65536]» → 65536.
    static func versionTag(in name: String) -> Int? {
        guard let start = name.range(of: "[v", options: .caseInsensitive) else { return nil }
        let rest = name[start.upperBound...]
        let digits = rest.prefix { $0.isNumber }
        guard !digits.isEmpty, rest.dropFirst(digits.count).first == "]" else { return nil }
        return Int(digits)
    }

    /// Versión para enseñar: la de Switch va en el número de actualización (v65536 → 1).
    static func versionText(_ version: Int?) -> String? {
        guard let version, version > 0 else { return nil }
        let update: Int = version >> 16
        return update > 0 ? "v\(version) (#\(update))" : "v\(version)"
    }

    /// Title ID del ticket de un .nsp (cabecera PFS0: archivos y sus nombres).
    private static func ticketTitleID(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 16), header.count == 16 else { return nil }
        let bytes = [UInt8](header)
        guard bytes[0] == 0x50, bytes[1] == 0x46, bytes[2] == 0x53, bytes[3] == 0x30 else { return nil } // "PFS0"
        let count: Int = Int(readUInt32(bytes, 4))
        let tableSize: Int = Int(readUInt32(bytes, 8))
        guard count > 0, count < 4096, tableSize > 0, tableSize < 1 << 20 else { return nil }
        guard let rest = try? handle.read(upToCount: count * 24 + tableSize), rest.count == count * 24 + tableSize else { return nil }
        let table = [UInt8](rest[(count * 24)...])
        // Los nombres van seguidos, terminados en 0.
        var names: [String] = []
        var current: [UInt8] = []
        for byte in table {
            if byte == 0 {
                if !current.isEmpty, let text = String(bytes: current, encoding: .utf8) { names.append(text) }
                current = []
            } else {
                current.append(byte)
            }
        }
        let hex = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        for name in names where name.lowercased().hasSuffix(".tik") {
            let rights: String = String(name.dropLast(4))
            guard rights.count == 32, rights.unicodeScalars.allSatisfy({ hex.contains($0) }) else { continue }
            let id: String = String(rights.prefix(16)).lowercased()
            if id.hasPrefix("01") { return id }
        }
        return nil
    }

    private static func readUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }
}

// MARK: - Actualizaciones y DLC encontrados

struct SwitchAddon: Codable, Hashable, Identifiable {
    /// De qué carpeta salió (la misma «source» que los juegos).
    let source: String
    /// Ruta completa del archivo.
    let path: String
    let kind: SwitchContentKind
    let titleID: String?
    let baseTitleID: String
    let version: Int?

    var id: String { path }
    var fileName: String { (path as NSString).lastPathComponent }
}

/// Lo que se encontró al escanear: las actualizaciones y DLC de cada juego (por Title ID) y el
/// Title ID de cada juego de la biblioteca. Se guarda en disco para no volver a leer los archivos.
final class SwitchAddonStore {
    static let shared = SwitchAddonStore()

    private struct Saved: Codable {
        var addons: [SwitchAddon] = []
        var titles: [String: String] = [:]
    }

    private let lock = NSLock()
    private var saved = Saved()
    private let file: URL = AppFolders.folder("Switch").appendingPathComponent("addons.json")

    private init() {
        if let data = try? Data(contentsOf: file), let decoded = try? JSONDecoder().decode(Saved.self, from: data) {
            saved = decoded
        }
    }

    /// Cambia lo de una carpeta (lo de las demás se queda).
    func replace(source: String, addons: [SwitchAddon], titles: [String: String]) {
        lock.lock()
        saved.addons.removeAll { $0.source == source }
        saved.addons += addons
        for (gameID, titleID) in titles { saved.titles[gameID] = titleID }
        let snapshot: Saved = saved
        lock.unlock()
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: file, options: .atomic)
        }
    }

    func titleID(for gameID: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return saved.titles[gameID]
    }

    func addons(baseTitleID: String) -> [SwitchAddon] {
        lock.lock()
        defer { lock.unlock() }
        let wanted: String = baseTitleID.lowercased()
        return saved.addons
            .filter { $0.baseTitleID == wanted }
            .sorted { ($0.kind.rawValue, $0.version ?? 0, $0.fileName) < ($1.kind.rawValue, $1.version ?? 0, $1.fileName) }
    }
}

/// Clasifica los archivos de un escaneo de Switch: los juegos van a la biblioteca y lo demás,
/// dentro de su juego.
struct SwitchScanCollector {
    let source: String
    private(set) var addons: [SwitchAddon] = []
    private(set) var titles: [String: String] = [:]

    init(source: String) {
        self.source = source
    }

    /// Devuelve true si el archivo es un juego (y apunta su Title ID); false si es actualización o DLC.
    mutating func accept(_ url: URL, gameID: String) -> Bool {
        let info: SwitchFileInfo = SwitchContent.info(for: url)
        if info.kind == .game {
            if let id = info.titleID { titles[gameID] = id }
            return true
        }
        guard let base = info.baseTitleID else {
            // Actualización sin Title ID: no se sabe de qué juego es; mejor verla que perderla.
            return true
        }
        addons.append(SwitchAddon(source: source, path: url.path, kind: info.kind, titleID: info.titleID,
                                  baseTitleID: base, version: info.version))
        return false
    }

    func save() {
        SwitchAddonStore.shared.replace(source: source, addons: addons, titles: titles)
    }
}

// MARK: - Cómo llama la app MeloNX a cada juego

/// La app MeloNX abre un juego por su enlace solo si le llega su Title ID tal como lo calcula ella
/// (a veces no es el del archivo, o lo guarda en decimal) o su título exacto. OmniStation lo lee
/// del archivo con el núcleo de MeloNX que lleva dentro, igual que la app MeloNX, y lo guarda
/// para no volver a leerlo. Con eso no hace falta escribir el «Nombre en MeloNX».
enum MeloNXIdentity {
    private struct Entry: Codable {
        let path: String
        let size: Int64
        let modified: Double
        let titleID: String
        let title: String
    }

    private static let lock = NSLock()
    private static var cache: [String: Entry]? = nil
    private static var file: URL { AppFolders.folder("Switch").appendingPathComponent("melonx-ids.json") }
    /// Si la app se cierra mientras lee (núcleo que no carga aquí), no se vuelve a intentar.
    private static let runningKey = "melonxIdentityRunning"
    private static let disabledKey = "melonxIdentityDisabled"

    private static func entries() -> [String: Entry] {
        if let existing = cache { return existing }
        var loaded: [String: Entry] = [:]
        if let data = try? Data(contentsOf: file), let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            loaded = decoded
        }
        cache = loaded
        return loaded
    }

    private static func store(_ value: [String: Entry]) {
        cache = value
        if let data = try? JSONEncoder().encode(value) {
            try? data.write(to: file, options: .atomic)
        }
    }

    private static func encoded(_ text: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    /// Enlace de MeloNX para el juego (nil si aún no se sabe cómo lo llama MeloNX).
    static func link(for gameID: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries()[gameID] else { return nil }
        if !entry.titleID.isEmpty { return "melonx://game?id=" + encoded(entry.titleID) }
        if !entry.title.isEmpty { return "melonx://game?name=" + encoded(entry.title) }
        return nil
    }

    /// Si OmniStation no tiene claves, las de la app MeloNX (su carpeta «system»), si se ven.
    private static func importKeys(from folders: [URL]) {
        guard !OSMeloNXEngine.keysInstalled else { return }
        let manager = FileManager.default
        let target = URL(fileURLWithPath: OSMeloNXEngine.keysDirectory, isDirectory: true)
        for folder in folders {
            let system: URL = folder.appendingPathComponent("system", isDirectory: true)
            let prod: URL = system.appendingPathComponent("prod.keys")
            guard manager.fileExists(atPath: prod.path) else { continue }
            try? manager.createDirectory(at: target, withIntermediateDirectories: true)
            for name in ["prod.keys", "title.keys"] {
                let from: URL = system.appendingPathComponent(name)
                let to: URL = target.appendingPathComponent(name)
                guard manager.fileExists(atPath: from.path), !manager.fileExists(atPath: to.path) else { continue }
                try? manager.copyItem(at: from, to: to)
            }
            return
        }
    }

    /// Lee los juegos que aún no se conocen (fuera del hilo principal, con la carpeta accesible).
    /// `files`: id del juego → su archivo. `keyFolders`: dónde buscar las claves de la app MeloNX.
    static func identify(_ files: [String: URL], keyFolders: [URL]) {
        guard !files.isEmpty, !Thread.isMainThread, OSMeloNXEngine.runtimeBundled,
              ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 18 else { return }
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: runningKey) {
            defaults.set(false, forKey: runningKey)
            defaults.set(true, forKey: disabledKey)
        }
        guard !defaults.bool(forKey: disabledKey) else { return }
        lock.lock()
        var current: [String: Entry] = entries()
        lock.unlock()
        var pending: [(id: String, url: URL, size: Int64, modified: Double)] = []
        for (gameID, url) in files {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size: Int64 = Int64(values?.fileSize ?? 0)
            let modified: Double = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
            if let entry = current[gameID], entry.path == url.path, entry.size == size, entry.modified == modified { continue }
            pending.append((id: gameID, url: url, size: size, modified: modified))
        }
        guard !pending.isEmpty else { return }
        importKeys(from: keyFolders)
        guard OSMeloNXEngine.keysInstalled else { return }
        defaults.set(true, forKey: runningKey)
        defaults.synchronize()
        var changed: Bool = false
        for item in pending {
            guard let info = OSMeloNXEngine.shared.identifyGame(atPath: item.url.path) else { continue }
            current[item.id] = Entry(path: item.url.path, size: item.size, modified: item.modified,
                                     titleID: info["titleId"] ?? "", title: info["titleName"] ?? "")
            changed = true
        }
        defaults.set(false, forKey: runningKey)
        guard changed else { return }
        lock.lock()
        // Lo que se haya guardado mientras tanto se queda; lo nuevo encima.
        var merged: [String: Entry] = entries()
        for (key, value) in current { merged[key] = value }
        store(merged)
        lock.unlock()
    }
}
