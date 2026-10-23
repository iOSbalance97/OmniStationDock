import Foundation
import UIKit
import Combine

// MARK: - SteamGridDB: fondos panorámicos y logos en alta calidad
//
// SteamGridDB (https://www.steamgriddb.com) tiene, para casi cualquier juego de cualquier
// consola, fondos «hero» (1920×620 o 3840×1240) y logos con transparencia, que es lo que usa la
// pantalla de cada juego. Necesita una clave gratuita: se crea una cuenta y se copia la clave en
// Preferencias → API. Se guarda en el llavero del iPhone.

enum SteamGridDB {
    private static let account = "steamgriddb.apikey"
    private static let idsKey = "steamGridDBGameIDs"
    private static let base = "https://www.steamgriddb.com/api/v2"

    static var apiKey: String {
        (KeychainStore.read(account) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var isConfigured: Bool { !apiKey.isEmpty }

    static func setAPIKey(_ key: String) {
        let clean: String = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty {
            KeychainStore.delete(account)
        } else {
            KeychainStore.write(clean, for: account)
        }
        UserDefaults.standard.removeObject(forKey: idsKey)
        BackdropStore.shared.forgetMisses()
        GameLogoStore.shared.forgetMisses()
    }

    private struct SearchResponse: Decodable {
        struct Item: Decodable {
            let id: Int
            let name: String
        }
        let success: Bool?
        let data: [Item]?
    }

    private struct AssetResponse: Decodable {
        struct Item: Decodable {
            let url: String
            let width: Int?
            let height: Int?
        }
        let success: Bool?
        let data: [Item]?
    }

    /// Nombre para buscar: sin región, serie ni versión («Juego (Europe) [SLES-123]» → «Juego»).
    static func searchName(_ name: String) -> String {
        var text: String = name
        for (open, close) in [("(", ")"), ("[", "]")] {
            while let start = text.range(of: open), let end = text.range(of: close, range: start.upperBound..<text.endIndex) {
                text.removeSubrange(start.lowerBound..<end.upperBound)
            }
        }
        let cleaned: String = text.replacingOccurrences(of: "_", with: " ")
            .components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
        return cleaned.isEmpty ? name : cleaned
    }

    private static func request(_ path: String) async -> Data? {
        let key: String = apiKey
        guard !key.isEmpty, let url = URL(string: base + path) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("OmniStationDock (iOS)", forHTTPHeaderField: "User-Agent")
        guard let result = try? await URLSession.shared.data(for: request),
              let http = result.1 as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        return result.0
    }

    /// Id del juego en SteamGridDB (se guarda para no buscarlo otra vez).
    static func gameID(for name: String) async -> Int? {
        let term: String = searchName(name)
        var known: [String: Int] = (UserDefaults.standard.dictionary(forKey: idsKey) as? [String: Int]) ?? [:]
        if let id = known[term.lowercased()] { return id }
        var allowed: CharacterSet = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let encoded = term.addingPercentEncoding(withAllowedCharacters: allowed),
              let data = await request("/search/autocomplete/" + encoded),
              let response = try? JSONDecoder().decode(SearchResponse.self, from: data),
              let first = response.data?.first else { return nil }
        // El primero es el que mejor encaja; si hay uno que se llama igual, ese.
        let wanted: String = term.lowercased()
        let exact: SearchResponse.Item? = response.data?.first(where: { $0.name.lowercased() == wanted })
        let id: Int = (exact ?? first).id
        known[wanted] = id
        UserDefaults.standard.set(known, forKey: idsKey)
        return id
    }

    private static func firstAsset(_ path: String) async -> URL? {
        guard let data = await request(path),
              let response = try? JSONDecoder().decode(AssetResponse.self, from: data),
              let item = response.data?.first else { return nil }
        return URL(string: item.url)
    }

    /// Fondo panorámico (hero) o, si no hay, una portada horizontal.
    static func heroURL(for name: String) async -> URL? {
        guard let id = await gameID(for: name) else { return nil }
        if let hero = await firstAsset("/heroes/game/\(id)?dimensions=3840x1240,1920x620&types=static&nsfw=false&humor=false") {
            return hero
        }
        if let anyHero = await firstAsset("/heroes/game/\(id)?types=static&nsfw=false&humor=false") {
            return anyHero
        }
        return await firstAsset("/grids/game/\(id)?dimensions=920x430,460x215&types=static&nsfw=false&humor=false")
    }

    /// Logo del juego con fondo transparente.
    static func logoURL(for name: String) async -> URL? {
        guard let id = await gameID(for: name) else { return nil }
        return await firstAsset("/logos/game/\(id)?types=static&nsfw=false&humor=false")
    }
}

// MARK: - Logos

/// Logos de los juegos (PNG con transparencia), en disco y en memoria.
final class GameLogoStore {
    static let shared = GameLogoStore()

    private let cache = NSCache<NSString, UIImage>()

    /// Suelta las imágenes en memoria (se vuelven a leer del disco): antes de una partida.
    func purgeMemory() {
        cache.removeAllObjects()
    }
    private var tried = Set<String>()

    private func fileURL(for id: String) -> URL {
        AppFolders.folder("Logos").appendingPathComponent(AppFolders.safeName(id) + ".png")
    }

    func forgetMisses() {
        tried.removeAll()
    }

    func cached(for id: String) -> UIImage? {
        if let image = cache.object(forKey: id as NSString) { return image }
        guard let file = UIImage(contentsOfFile: fileURL(for: id).path) else { return nil }
        cache.setObject(file, forKey: id as NSString)
        return file
    }

    @MainActor
    func logo(id: String, name: String) async -> UIImage? {
        if let image = cached(for: id) { return image }
        guard SteamGridDB.isConfigured, !tried.contains(id) else { return nil }
        tried.insert(id)
        guard let url = await SteamGridDB.logoURL(for: name),
              let data = try? await CoverDownloader.fetch(url),
              let image = UIImage(data: data) else { return nil }
        // Se guarda en PNG (con transparencia) y como mucho a 1200 px de ancho.
        let scale: CGFloat = min(1, 1200 / max(image.size.width, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let resized: UIImage = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        if let png = resized.pngData() {
            try? png.write(to: fileURL(for: id), options: .atomic)
        }
        cache.setObject(resized, forKey: id as NSString)
        return resized
    }

    func remove(for id: String) {
        cache.removeObject(forKey: id as NSString)
        try? FileManager.default.removeItem(at: fileURL(for: id))
        tried.remove(id)
    }
}

// MARK: - Partidas (último día y tiempo jugado)

enum PlayStats {
    private static let lastKey = "playLastDates"
    private static let timeKey = "playSeconds"

    static func lastPlayed(_ id: String) -> Date? {
        guard let value = (UserDefaults.standard.dictionary(forKey: lastKey) as? [String: Double])?[id] else { return nil }
        return Date(timeIntervalSince1970: value)
    }

    static func playTime(_ id: String) -> TimeInterval {
        (UserDefaults.standard.dictionary(forKey: timeKey) as? [String: Double])?[id] ?? 0
    }

    static func markPlayed(_ id: String) {
        var values: [String: Double] = (UserDefaults.standard.dictionary(forKey: lastKey) as? [String: Double]) ?? [:]
        values[id] = Date().timeIntervalSince1970
        UserDefaults.standard.set(values, forKey: lastKey)
    }

    /// Olvida la última partida y el tiempo jugado de un juego (Borrar datos).
    static func forget(_ id: String) {
        for key in [lastKey, timeKey] {
            var values: [String: Double] = (UserDefaults.standard.dictionary(forKey: key) as? [String: Double]) ?? [:]
            values[id] = nil
            UserDefaults.standard.set(values, forKey: key)
        }
    }

    static func addPlayTime(_ id: String, seconds: TimeInterval) {
        guard seconds > 5 else { return }
        var values: [String: Double] = (UserDefaults.standard.dictionary(forKey: timeKey) as? [String: Double]) ?? [:]
        values[id] = (values[id] ?? 0) + seconds
        UserDefaults.standard.set(values, forKey: timeKey)
    }
}

// MARK: - Partida en marcha

/// Hay una partida de un núcleo integrado: la interfaz de detrás se para (vídeo de fondo,
/// música) para dejarle al juego toda la CPU y la GPU.
final class EmulationActivity: ObservableObject {
    static let shared = EmulationActivity()

    @Published private(set) var running = false
    private var gameID: String?
    private var startedAt: Date?

    func begin(gameID: String?) {
        running = true
        // Toda la RAM posible para el juego: fuera las imágenes en memoria de la interfaz.
        CoverStore.shared.purgeMemory()
        BackdropStore.shared.purgeMemory()
        GameLogoStore.shared.purgeMemory()
        URLCache.shared.removeAllCachedResponses()
        self.gameID = gameID
        startedAt = Date()
        if let gameID { PlayStats.markPlayed(gameID) }
    }

    func end() {
        if let gameID, let startedAt {
            PlayStats.addPlayTime(gameID, seconds: Date().timeIntervalSince(startedAt))
        }
        gameID = nil
        startedAt = nil
        running = false
    }
}
