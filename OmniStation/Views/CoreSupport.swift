import Foundation

// MARK: - ARMSX2 integrado (núcleo dentro de OmniStation)

/// Cómo se juega a PS2: con la app ARMSX2 aparte (en LiveContainer o instalada con SideStore)
/// o con el núcleo integrado en OmniStation. Son caminos separados: no comparten carpeta,
/// juegos ni ajustes.
enum ARMSX2Mode: String {
    case external
    case integrated

    static let storageKey = "armsx2Engine"

    /// El integrado solo funciona fuera de LiveContainer (la extensión de JIT no corre dentro).
    static var integratedAvailable: Bool {
        !DebugSupport.isInsideLiveContainer
    }

    /// El modo que de verdad se usa ahora.
    static func effective(_ raw: String) -> ARMSX2Mode {
        guard raw == ARMSX2Mode.integrated.rawValue, integratedAvailable else { return .external }
        return .integrated
    }
}

/// Carpeta propia del núcleo integrado, visible en Archivos → En mi iPhone → OmniStation Dock:
/// ARMSX2/Juegos, ARMSX2/BIOS y ARMSX2/Datos (tarjetas de memoria, estados, texturas, trucos,
/// ajustes… los crea el propio núcleo).
enum ARMSX2CoreFolders {
    /// Origen de los juegos de esta carpeta en la biblioteca.
    static let source = "core:armsx2"
    /// Prefijo de sus ids (distinto de los de la app ARMSX2 aparte).
    static let idPrefix = "ARMSX2/"
    static let touchAlwaysKey = "armsx2CoreTouchAlways"

    /// Extensiones que arranca el núcleo.
    static let gameExtensions: Set<String> = ["iso", "chd", "cso", "zso", "gz", "elf", "bin", "img", "mdf", "nrg"]

    static var root: URL {
        let documents: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("ARMSX2", isDirectory: true)
    }

    static var games: URL { root.appendingPathComponent("Juegos", isDirectory: true) }
    static var bios: URL { root.appendingPathComponent("BIOS", isDirectory: true) }
    static var data: URL { root.appendingPathComponent("Datos", isDirectory: true) }

    /// Donde el núcleo integrado busca las tarjetas de memoria (Datos/Saves/Memory Cards).
    static var memoryCards: URL {
        data.appendingPathComponent("Saves", isDirectory: true).appendingPathComponent("Memory Cards", isDirectory: true)
    }

    static func ensure() {
        for folder in [games, bios, data, memoryCards] {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        adoptMemoryCards()
    }

    /// La app ARMSX2 guarda las tarjetas en «memcards»; el núcleo integrado, en Saves/Memory Cards.
    /// Las que se copien a Datos/memcards, a Datos o a la carpeta ARMSX2 se pasan a su sitio.
    /// Si ya había una con el mismo nombre (la vacía que crea el núcleo), se guarda como «.bak».
    private static func adoptMemoryCards() {
        let manager = FileManager.default
        let sources: [URL] = [data.appendingPathComponent("memcards", isDirectory: true), data, root]
        for folder in sources {
            guard let names = try? manager.contentsOfDirectory(atPath: folder.path) else { continue }
            for name in names where name.lowercased().hasSuffix(".ps2") && !name.hasPrefix(".") {
                let source: URL = folder.appendingPathComponent(name)
                let target: URL = memoryCards.appendingPathComponent(name)
                guard source.standardizedFileURL != target.standardizedFileURL else { continue }
                if manager.fileExists(atPath: target.path) {
                    let backup: URL = memoryCards.appendingPathComponent(name + ".bak")
                    try? manager.removeItem(at: backup)
                    try? manager.moveItem(at: target, to: backup)
                }
                try? manager.moveItem(at: source, to: target)
            }
        }
    }

    /// Archivos de BIOS (el núcleo elige uno válido entre ellos).
    static func biosFiles() -> [String] {
        let names: [String] = (try? FileManager.default.contentsOfDirectory(atPath: bios.path)) ?? []
        return names.filter { name in
            !name.hasPrefix(".") && !isDirectory(bios.appendingPathComponent(name))
        }.sorted()
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
    }

    /// Juegos de ARMSX2/Juegos (también en subcarpetas). `fileName` es la ruta dentro de Juegos.
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
            found[id] = LibraryGame(id: id, name: name, platform: Emulator.armsx2.platform, launchURL: nil,
                                    source: source, fileName: relative)
        }
        return found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Ruta completa de un juego a partir de su `fileName`.
    static func path(for fileName: String) -> String {
        games.appendingPathComponent(fileName).path
    }

    /// Copia archivos elegidos en Archivos a una carpeta del núcleo. Devuelve cuántos copió.
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

    /// Enlace que abre esta carpeta en la app Archivos.
    static var filesAppURL: URL? {
        URL(string: "shareddocuments://" + root.path)
    }
}
