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
        var kind: SwitchContentKind = titleID.map { kind(of: $0) } ?? .game
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
