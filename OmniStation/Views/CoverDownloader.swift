import Foundation

// MARK: - Carátulas automáticas

/// Carátulas puestas por la app (descargadas o de un emulador), no elegidas por el usuario:
/// estas sí se pueden sustituir por otras mejores; las del usuario nunca se tocan.
enum AutoCovers {
    private static let key = "autoCoverIDs"

    static func contains(_ id: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).contains(id)
    }

    static func mark(_ id: String) {
        var ids: Set<String> = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        ids.insert(id)
        UserDefaults.standard.set(Array(ids), forKey: key)
    }

    static func unmark(_ id: String) {
        var ids: Set<String> = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        ids.remove(id)
        UserDefaults.standard.set(Array(ids), forKey: key)
    }
}

/// Descarga carátulas de la colección pública libretro-thumbnails (GitHub), por plataforma:
/// baja una vez la lista de carátulas de cada sistema (se guarda una semana) y empareja cada
/// juego por su nombre, aunque no se escriba igual.
enum CoverDownloader {
    static let enabledKey = "autoCovers"
    private static let attemptedKey = "coverAttempts"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Repositorio de libretro-thumbnails de cada plataforma de OmniStation.
    static func repository(for platform: String) -> String? {
        switch platform {
        case "PS2": return "Sony_-_PlayStation_2"
        case "PS1": return "Sony_-_PlayStation"
        case "PSP": return "Sony_-_PlayStation_Portable"
        case "GBA": return "Nintendo_-_Game_Boy_Advance"
        case "Game Boy": return "Nintendo_-_Game_Boy"
        case "Game Boy Color": return "Nintendo_-_Game_Boy_Color"
        case "NDS": return "Nintendo_-_Nintendo_DS"
        case "3DS": return "Nintendo_-_Nintendo_3DS"
        case "NES": return "Nintendo_-_Nintendo_Entertainment_System"
        case "SNES": return "Nintendo_-_Super_Nintendo_Entertainment_System"
        case "N64": return "Nintendo_-_Nintendo_64"
        case "GameCube": return "Nintendo_-_GameCube"
        case "Wii": return "Nintendo_-_Wii"
        case "Mega Drive": return "Sega_-_Mega_Drive_-_Genesis"
        case "Master System": return "Sega_-_Master_System_-_Mark_III"
        case "Game Gear": return "Sega_-_Game_Gear"
        case "Dreamcast": return "Sega_-_Dreamcast"
        case "Saturn": return "Sega_-_Saturn"
        default: return nil
        }
    }

    // MARK: Intentos (para no repetir búsquedas que no encontraron nada)

    static func wasAttempted(_ id: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: attemptedKey) ?? []).contains(id)
    }

    static func markAttempted(_ id: String) {
        var ids: Set<String> = Set(UserDefaults.standard.stringArray(forKey: attemptedKey) ?? [])
        ids.insert(id)
        UserDefaults.standard.set(Array(ids), forKey: attemptedKey)
    }

    static func resetAttempts() {
        UserDefaults.standard.removeObject(forKey: attemptedKey)
    }

    // MARK: Lista de carátulas de un sistema

    private struct Tree: Decodable {
        struct Entry: Decodable {
            let path: String
            let type: String
            let sha: String
        }
        let tree: [Entry]
    }

    private static func cacheURL(_ repository: String) -> URL {
        AppFolders.folder("CoverIndex").appendingPathComponent(repository + ".json")
    }

    private static func fetchTree(_ url: URL) async throws -> Tree {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("OmniStationDock", forHTTPHeaderField: "User-Agent")
        let result: (Data, URLResponse) = try await URLSession.shared.data(for: request)
        if let http = result.1 as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Tree.self, from: result.0)
    }

    /// Nombres de las carátulas ("Juego (Europe).png") del sistema.
    static func boxartNames(_ repository: String) async throws -> [String] {
        let cache: URL = cacheURL(repository)
        if let attributes = try? FileManager.default.attributesOfItem(atPath: cache.path),
           let date = attributes[.modificationDate] as? Date,
           Date().timeIntervalSince(date) < 7 * 24 * 3600,
           let data = try? Data(contentsOf: cache),
           let names = try? JSONDecoder().decode([String].self, from: data) {
            return names
        }
        let base: String = "https://api.github.com/repos/libretro-thumbnails/" + repository + "/git/trees/"
        guard let rootURL = URL(string: base + "master") else { return [] }
        let root: Tree = try await fetchTree(rootURL)
        guard let folder = root.tree.first(where: { $0.path == "Named_Boxarts" && $0.type == "tree" }),
              let folderURL = URL(string: base + folder.sha) else { return [] }
        let list: Tree = try await fetchTree(folderURL)
        let names: [String] = list.tree.filter { $0.type == "blob" && $0.path.lowercased().hasSuffix(".png") }.map(\.path)
        if let data = try? JSONEncoder().encode(names) {
            try? data.write(to: cache, options: .atomic)
        }
        return names
    }

    // MARK: Emparejar

    /// Palabras comparables de un nombre (sin tildes, sin lo que va entre paréntesis o corchetes).
    static func words(_ text: String) -> [String] {
        MeloNXLibrary.normalized(text)
    }

    /// Regiones preferidas, en orden (por el idioma del iPhone).
    private static var preferredRegions: [String] {
        let spanish: Bool = Locale.preferredLanguages.first?.hasPrefix("es") ?? false
        return spanish ? ["(Spain", "(Europe", "(USA", "(World", "(Japan"] : ["(USA", "(World", "(Europe", "(Japan"]
    }

    private static func regionRank(_ name: String) -> Int {
        for (index, region) in preferredRegions.enumerated() where name.contains(region) {
            return index
        }
        return preferredRegions.count
    }

    /// La carátula que mejor encaja con el nombre del juego (nil si ninguna se parece lo bastante).
    static func bestMatch(for gameName: String, fileName: String?, in names: [String]) -> String? {
        // 1) El mismo nombre de archivo (las ROMs con nombre estándar coinciden exactas).
        if let fileName {
            let base: String = (fileName as NSString).deletingPathExtension
            let exact: String = libretroSafe(base) + ".png"
            if names.contains(exact) { return exact }
        }
        // 2) Por palabras.
        let target: [String] = words(gameName)
        guard !target.isEmpty else { return nil }
        let targetSet: Set<String> = Set(target)
        let targetJoined: String = target.joined()
        var best: String? = nil
        var bestScore: Double = 0
        var bestRank: Int = Int.max
        for name in names {
            let candidate: [String] = words((name as NSString).deletingPathExtension)
            guard !candidate.isEmpty else { continue }
            let score: Double
            if candidate.joined() == targetJoined {
                score = 1
            } else {
                let set: Set<String> = Set(candidate)
                score = Double(set.intersection(targetSet).count) / Double(set.union(targetSet).count)
            }
            let rank: Int = regionRank(name)
            if score > bestScore || (score == bestScore && rank < bestRank) {
                best = name
                bestScore = score
                bestRank = rank
            }
        }
        return bestScore >= 0.6 ? best : nil
    }

    /// libretro-thumbnails cambia por "_" los caracteres que no valen en un nombre de archivo.
    private static func libretroSafe(_ name: String) -> String {
        let forbidden: Set<Character> = ["&", "*", "/", ":", "`", "<", ">", "?", "\\", "|", "\""]
        return String(name.map { forbidden.contains($0) ? "_" : $0 })
    }

    // MARK: Descargar

    static func download(_ repository: String, name: String) async throws -> Data {
        let encoded: String = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        guard let url = URL(string: "https://raw.githubusercontent.com/libretro-thumbnails/" + repository + "/master/Named_Boxarts/" + encoded) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let result: (Data, URLResponse) = try await URLSession.shared.data(for: request)
        if let http = result.1 as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return result.0
    }
}
