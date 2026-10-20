import Foundation
import UIKit

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

    /// Busca y descarga la carátula de un juego (nil si no hay ninguna que encaje).
    /// Orden: libretro-thumbnails; en Switch, el icono de la eShop por su Title ID; y si nada
    /// encaja, la portada de su artículo en Wikipedia.
    static func findCover(for gameName: String, platform: String, fileName: String?, titleID: String? = nil) async -> Data? {
        if let repository = repository(for: platform) {
            let names: [String] = (try? await boxartNames(repository)) ?? []
            if let name = bestMatch(for: gameName, fileName: fileName, in: names),
               let data = try? await download(repository, name: name) {
                return data
            }
        }
        if platform == "Switch", let titleID, let url = SwitchArtwork.iconURL(titleID: titleID),
           let data = try? await fetch(url) {
            return data
        }
        return await WikipediaArtwork.cover(for: gameName, platform: platform)
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

    private static func cacheURL(_ repository: String, folder: String) -> URL {
        let name: String = folder == "Named_Boxarts" ? repository : repository + "-" + folder
        return AppFolders.folder("CoverIndex").appendingPathComponent(name + ".json")
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
        try await imageNames(repository, folder: "Named_Boxarts")
    }

    /// Nombres de las imágenes de una carpeta del sistema: Named_Boxarts (carátulas),
    /// Named_Snaps (capturas del juego) o Named_Titles (pantalla de título).
    static func imageNames(_ repository: String, folder: String) async throws -> [String] {
        let cache: URL = cacheURL(repository, folder: folder)
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
        guard let entry = root.tree.first(where: { $0.path == folder && $0.type == "tree" }),
              let folderURL = URL(string: base + entry.sha) else { return [] }
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

    static func download(_ repository: String, name: String, folder: String = "Named_Boxarts") async throws -> Data {
        let encoded: String = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        guard let url = URL(string: "https://raw.githubusercontent.com/libretro-thumbnails/" + repository + "/master/" + folder + "/" + encoded) else {
            throw URLError(.badURL)
        }
        return try await fetch(url)
    }

    /// Descarga sencilla (falla si el servidor no responde 2xx o no es una imagen).
    static func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("OmniStationDock/0.3 (iOS)", forHTTPHeaderField: "User-Agent")
        let result: (Data, URLResponse) = try await URLSession.shared.data(for: request)
        if let http = result.1 as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        guard UIImage(data: result.0) != nil else { throw URLError(.cannotDecodeContentData) }
        return result.0
    }
}

// MARK: - Switch: imágenes de la eShop (api.nlib.cc)

/// Icono y banner de cada juego de Switch por su Title ID (0100…).
enum SwitchArtwork {
    static func iconURL(titleID: String) -> URL? {
        URL(string: "https://api.nlib.cc/nx/" + titleID.uppercased() + "/icon/1024/1024")
    }

    /// Imagen horizontal 1920×1080.
    static func bannerURL(titleID: String) -> URL? {
        URL(string: "https://api.nlib.cc/nx/" + titleID.uppercased() + "/banner/1080")
    }
}

// MARK: - Wikipedia: portada del artículo del juego

/// Si ninguna colección la tiene, la portada sale de la imagen principal del artículo del juego
/// en la Wikipedia en inglés (la que lleva las portadas de los videojuegos).
enum WikipediaArtwork {
    private struct Response: Decodable {
        struct Query: Decodable {
            let pages: [Page]?
        }
        struct Page: Decodable {
            let title: String
            let thumbnail: Thumbnail?
        }
        struct Thumbnail: Decodable {
            let source: String
        }
        let query: Query?
    }

    static func cover(for gameName: String, platform: String) async -> Data? {
        let words: [String] = MeloNXLibrary.normalized(gameName)
        guard !words.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "en.wikipedia.org"
        components.path = "/w/api.php"
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
            URLQueryItem(name: "generator", value: "search"),
            URLQueryItem(name: "gsrsearch", value: words.joined(separator: " ") + " video game"),
            URLQueryItem(name: "gsrlimit", value: "1"),
            URLQueryItem(name: "prop", value: "pageimages"),
            URLQueryItem(name: "piprop", value: "thumbnail"),
            URLQueryItem(name: "pithumbsize", value: "900"),
            URLQueryItem(name: "redirects", value: "1")
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("OmniStationDock/0.3 (iOS)", forHTTPHeaderField: "User-Agent")
        guard let result = try? await URLSession.shared.data(for: request),
              let response = try? JSONDecoder().decode(Response.self, from: result.0),
              let page = response.query?.pages?.first,
              titleMatches(page.title, gameName),
              let source = page.thumbnail?.source,
              let imageURL = URL(string: source) else { return nil }
        return try? await CoverDownloader.fetch(imageURL)
    }

    /// El artículo tiene que ser de ese juego: casi todas las palabras del nombre en su título.
    static func titleMatches(_ title: String, _ name: String) -> Bool {
        let a: Set<String> = Set(MeloNXLibrary.normalized(title))
        let b: Set<String> = Set(MeloNXLibrary.normalized(name))
        guard !a.isEmpty, !b.isEmpty else { return false }
        return Double(a.intersection(b).count) / Double(b.count) >= 0.6
    }
}

// MARK: - Fondos horizontales (pantalla del juego)

/// Imagen horizontal de cada juego para el fondo de su pantalla: banner de la eShop en Switch;
/// en el resto, una captura del juego (o su pantalla de título) de libretro-thumbnails.
final class BackdropStore {
    static let shared = BackdropStore()

    private let cache = NSCache<NSString, UIImage>()

    /// Suelta las imágenes en memoria (se vuelven a leer del disco): antes de una partida.
    func purgeMemory() {
        cache.removeAllObjects()
    }
    private var tried = Set<String>()
    /// De dónde salió cada fondo guardado («hd»: SteamGridDB o banner de la eShop; «snap»: captura).
    private static let qualityKey = "backdropQuality"

    private func fileURL(for id: String) -> URL {
        AppFolders.folder("Backdrops").appendingPathComponent(AppFolders.safeName(id) + ".jpg")
    }

    private func quality(_ id: String) -> String? {
        (UserDefaults.standard.dictionary(forKey: Self.qualityKey) as? [String: String])?[id]
    }

    private func setQuality(_ id: String, _ value: String) {
        var values: [String: String] = (UserDefaults.standard.dictionary(forKey: Self.qualityKey) as? [String: String]) ?? [:]
        values[id] = value
        UserDefaults.standard.set(values, forKey: Self.qualityKey)
    }

    /// Después de poner la clave de SteamGridDB: se vuelven a buscar los fondos de poca calidad.
    func forgetMisses() {
        tried.removeAll()
    }

    func cached(for id: String) -> UIImage? {
        if let image = cache.object(forKey: id as NSString) { return image }
        guard let file = UIImage(contentsOfFile: fileURL(for: id).path) else { return nil }
        let image: UIImage = file.preparingForDisplay() ?? file
        cache.setObject(image, forKey: id as NSString)
        return image
    }

    /// ¿Merece la pena buscar uno mejor? (el guardado es una captura pequeña y hay SteamGridDB).
    func wantsUpgrade(_ id: String) -> Bool {
        quality(id) != "hd" && SteamGridDB.isConfigured && !tried.contains(id)
    }

    /// La guardada o, si no hay (o es de poca calidad), la busca y la guarda (una vez por sesión).
    @MainActor
    func image(id: String, name: String, platform: String, fileName: String?, titleID: String?) async -> UIImage? {
        if let image = cached(for: id), !wantsUpgrade(id) { return image }
        guard !tried.contains(id) else { return cached(for: id) }
        tried.insert(id)
        guard let found = await Self.find(name: name, platform: platform, fileName: fileName, titleID: titleID) else {
            return cached(for: id)
        }
        // Una captura no sustituye a un fondo bueno ya guardado.
        if found.hd == false, cached(for: id) != nil { return cached(for: id) }
        guard let jpeg = ImageResizer.jpeg(from: found.data, maxSide: 2560) else { return cached(for: id) }
        try? jpeg.write(to: fileURL(for: id), options: .atomic)
        setQuality(id, found.hd ? "hd" : "snap")
        cache.removeObject(forKey: id as NSString)
        return cached(for: id)
    }

    func remove(for id: String) {
        cache.removeObject(forKey: id as NSString)
        try? FileManager.default.removeItem(at: fileURL(for: id))
        tried.remove(id)
    }

    /// Por orden: SteamGridDB (fondo panorámico), banner de la eShop (Switch) y, si no hay nada,
    /// una captura de libretro-thumbnails.
    private static func find(name: String, platform: String, fileName: String?, titleID: String?) async -> (data: Data, hd: Bool)? {
        if let hero = await SteamGridDB.heroURL(for: name), let data = try? await CoverDownloader.fetch(hero) {
            return (data, true)
        }
        if platform == "Switch", let titleID, let url = SwitchArtwork.bannerURL(titleID: titleID),
           let data = try? await CoverDownloader.fetch(url) {
            return (data, true)
        }
        guard let data = await findSnapshot(name: name, platform: platform, fileName: fileName) else { return nil }
        return (data, false)
    }

    private static func findSnapshot(name: String, platform: String, fileName: String?) async -> Data? {
        guard let repository = CoverDownloader.repository(for: platform) else { return nil }
        for folder in ["Named_Snaps", "Named_Titles"] {
            let names: [String] = (try? await CoverDownloader.imageNames(repository, folder: folder)) ?? []
            if let match = CoverDownloader.bestMatch(for: name, fileName: fileName, in: names),
               let data = try? await CoverDownloader.download(repository, name: match, folder: folder) {
                return data
            }
        }
        return nil
    }
}
