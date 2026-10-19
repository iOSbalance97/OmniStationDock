import Foundation

// MARK: - MeloNX integrado (Switch dentro de OmniStation)

/// Cómo se juega a Switch: con la app MeloNX aparte o con su runtime integrado en OmniStation.
/// Son caminos separados, como en ARMSX2: cada uno con sus juegos.
enum MeloNXMode: String {
    case external
    case integrated

    static let storageKey = "melonxEngine"

    /// El integrado solo funciona fuera de LiveContainer (la extensión de JIT no corre dentro).
    static var integratedAvailable: Bool {
        !DebugSupport.isInsideLiveContainer
    }

    static func effective(_ raw: String) -> MeloNXMode {
        guard raw == MeloNXMode.integrated.rawValue, integratedAvailable else { return .external }
        return .integrated
    }
}

/// Carpetas del MeloNX integrado. Los juegos van en Archivos → OmniStation Dock → MeloNX → Juegos.
/// Ryujinx guarda sus datos (claves en «system», firmware en «bis», partidas…) en la raíz de
/// Documentos de OmniStation: no se puede cambiar desde fuera del núcleo.
enum MeloNXCoreFolders {
    static let source = "core:melonx"
    static let idPrefix = "MeloNX/"
    static let dockedKey = "melonxCoreDocked"
    /// Lo lee OSMeloNXEngine al abrir la partida (mismo nombre).
    static let touchAlwaysKey = "melonxCoreTouchAlways"

    static let gameExtensions: Set<String> = ["nsp", "xci", "nro", "nca", "pfs0"]

    private static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var root: URL { documents.appendingPathComponent("MeloNX", isDirectory: true) }
    static var games: URL { root.appendingPathComponent("Juegos", isDirectory: true) }
    static var keys: URL { URL(fileURLWithPath: OSMeloNXEngine.keysDirectory, isDirectory: true) }

    static func ensure() {
        for folder in [games, keys] {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
    }

    static func scanGames(limit: Int = 20000) -> [LibraryGame] {
        let base: URL = games.standardizedFileURL
        guard let enumerator = FileManager.default.enumerator(
            at: base,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        let baseCount: Int = base.pathComponents.count
        var found: [String: LibraryGame] = [:]
        var visited: Int = 0
        for case let url as URL in enumerator {
            visited += 1
            if visited > limit { break }
            guard gameExtensions.contains(url.pathExtension.lowercased()) else { continue }
            let parts: [String] = Array(url.standardizedFileURL.pathComponents.dropFirst(baseCount))
            guard !parts.isEmpty else { continue }
            let relative: String = parts.joined(separator: "/")
            let name: String = url.deletingPathExtension().lastPathComponent
            let id: String = idPrefix + relative
            found[id] = LibraryGame(id: id, name: name, platform: Emulator.melonx.platform, launchURL: nil,
                                    source: source, fileName: relative)
        }
        return found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func path(for fileName: String) -> String {
        games.appendingPathComponent(fileName).path
    }

    /// Copia archivos elegidos en Archivos a una carpeta. Devuelve cuántos copió.
    static func copy(_ urls: [URL], into folder: URL) -> Int {
        ensure()
        var copied: Int = 0
        for url in urls {
            let accessing: Bool = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let target: URL = folder.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: target.path) {
                try? FileManager.default.removeItem(at: target)
            }
            do {
                try FileManager.default.copyItem(at: url, to: target)
                copied += 1
            } catch {
                continue
            }
        }
        return copied
    }

    /// Copia las claves (.keys) a Documentos/system. Devuelve si ya hay prod.keys.
    static func importKeys(_ urls: [URL]) -> Bool {
        let keyFiles: [URL] = urls.filter { $0.pathExtension.lowercased() == "keys" }
        _ = copy(keyFiles, into: keys)
        return OSMeloNXEngine.keysInstalled
    }

    /// Copia el firmware elegido a un sitio temporal propio (el núcleo lo lee desde ahí).
    static func stageFirmware(_ url: URL) -> URL? {
        let accessing: Bool = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let folder: URL = FileManager.default.temporaryDirectory.appendingPathComponent("MeloNXFirmware", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target: URL = folder.appendingPathComponent(url.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: url, to: target)
            return target
        } catch {
            return nil
        }
    }

    static var filesAppURL: URL? {
        URL(string: "shareddocuments://" + root.path)
    }

    /// Memoria disponible en texto (por ejemplo «5,2 GB»).
    static var availableMemoryText: String {
        let bytes: UInt64 = OSMeloNXEngine.availableMemory
        guard bytes > 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }
}
