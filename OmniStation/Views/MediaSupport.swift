import SwiftUI
import UIKit
import AVFoundation
import AudioToolbox
import Security

// MARK: - Archivos incluidos en la app

enum BundleFiles {
    /// Todos los archivos de la app (en cualquier carpeta), leídos una sola vez.
    static let all: [URL] = {
        guard let root = Bundle.main.resourceURL,
              let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
              ) else { return [] }
        var result: [URL] = []
        for case let url as URL in enumerator {
            result.append(url)
        }
        return result
    }()

    /// Primer archivo que se llame como uno de `names` (por orden), sin distinguir mayúsculas.
    static func find(_ names: [String], extensions: [String]) -> URL? {
        for name in names {
            for url in all {
                let base: String = url.deletingPathExtension().lastPathComponent.lowercased()
                if base == name && extensions.contains(url.pathExtension.lowercased()) {
                    return url
                }
            }
        }
        return nil
    }
}

// MARK: - Fondo: animado predeterminado, original estático, imagen propia o vídeo propio

enum BackgroundStore {
    /// "default" (animado incluido), "original" (estático de siempre), "static" (imagen propia)
    /// o "video" (vídeo propio).
    static let modeKey = "backgroundMode"
    static let videoExtensions: [String] = ["mp4", "mov", "m4v"]

    /// Vídeo de fondo incluido en la app (Resources/Background/DefaultBackground.mp4).
    static let defaultVideoURL: URL? = BundleFiles.find(
        ["defaultbackground", "default_background", "fondo_animado", "fondoanimado", "background"],
        extensions: videoExtensions
    )
    private static let videoNameKey = "backgroundVideoFile"

    private static var imageURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("custom_background.jpg")
    }

    static func load() -> UIImage? {
        UIImage(contentsOfFile: imageURL.path)
    }

    /// Reduce la imagen (máx. 2200 px) y la guarda como JPEG.
    static func save(_ data: Data) -> Bool {
        guard let jpeg = ImageResizer.jpeg(from: data, maxSide: 2200) else { return false }
        do {
            try jpeg.write(to: imageURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func remove() {
        try? FileManager.default.removeItem(at: imageURL)
    }

    /// Vídeo de fondo actual, si hay uno guardado.
    static var videoURL: URL? {
        guard let name = UserDefaults.standard.string(forKey: videoNameKey) else { return nil }
        let url: URL = AppFolders.folder("Background").appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Guarda el vídeo con un nombre nuevo cada vez (así el reproductor sabe que ha cambiado).
    static func saveVideo(_ data: Data, fileExtension: String) -> URL? {
        removeVideo()
        let ext: String = fileExtension.isEmpty ? "mov" : fileExtension
        let name = "video-\(Int(Date().timeIntervalSince1970)).\(ext)"
        let url: URL = AppFolders.folder("Background").appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return nil
        }
        UserDefaults.standard.set(name, forKey: videoNameKey)
        return url
    }

    static func removeVideo() {
        if let url = videoURL {
            try? FileManager.default.removeItem(at: url)
        }
        UserDefaults.standard.removeObject(forKey: videoNameKey)
    }
}

/// Vídeo en bucle, sin sonido y llenando la pantalla, para el fondo animado.
struct LoopingVideoBackground: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> LoopingVideoView {
        LoopingVideoView(url: url)
    }

    func updateUIView(_ uiView: LoopingVideoView, context: Context) {
        uiView.load(url)
    }
}

final class LoopingVideoView: UIView {
    private let playerLayer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var currentURL: URL?

    init(url: URL) {
        super.init(frame: .zero)
        playerLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(playerLayer)
        isUserInteractionEnabled = false
        load(url)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func load(_ url: URL) {
        guard url != currentURL else { return }
        currentURL = url
        SoundManager.shared.prepareSession()
        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer()
        queue.isMuted = true
        // Un fondo no debe impedir que la pantalla se apague sola.
        queue.preventsDisplaySleepDuringVideoPlayback = false
        looper = AVPlayerLooper(player: queue, templateItem: item)
        player = queue
        playerLayer.player = queue
        queue.play()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}

// MARK: - Sonidos de la app

enum SoundKind: String, CaseIterable, Identifiable {
    case navigate, select, ambient

    var id: String { rawValue }

    /// Nombre del archivo incluido en la app (Resources/Sounds), sin extensión.
    var bundleName: String { "sound_\(rawValue)" }

    /// Nombres que se aceptan para cada sonido (sin extensión y sin distinguir mayúsculas).
    var aliases: [String] {
        switch self {
        case .navigate:
            return ["sound_navigate", "sound_navigation", "navigate", "navigation", "sound_move", "move"]
        case .select:
            return ["sound_select", "sound_selection", "select", "selection", "sound_seleccion", "seleccion", "sound_confirm", "confirm"]
        case .ambient:
            return ["sound_ambient", "ambient", "sound_music", "music", "bgm"]
        }
    }

    var volumeKey: String {
        switch self {
        case .navigate: return "volumeNavigate"
        case .select: return "volumeSelect"
        case .ambient: return "volumeAmbient"
        }
    }

    var defaultVolume: Double {
        switch self {
        case .navigate: return 0.5
        case .select: return 0.7
        case .ambient: return 0.3
        }
    }
}

/// Estado de un sonido, para enseñarlo en Ajustes → Sonidos.
enum SoundStatus {
    case imported(String)
    case bundled(String)
    case unreadable(String)
    case unsupported(String)
    case missing
}

/// Reproduce los sonidos: los importados por el usuario mandan sobre los incluidos en la app.
final class SoundManager {
    static let shared = SoundManager()
    /// Formatos que reproduce iOS (AVAudioPlayer).
    static let extensions: [String] = ["wav", "mp3", "m4a", "caf", "aac", "aif", "aiff", "flac", "m4r", "mp4"]
    /// Formatos que suelen usarse pero iOS no reproduce.
    private static let unsupportedExtensions: [String] = ["ogg", "oga", "opus", "wma", "mid", "midi"]

    private var players: [SoundKind: AVAudioPlayer] = [:]
    private var unreadable: [SoundKind: String] = [:]
    private var sessionReady = false

    /// Todos los archivos de audio que van dentro de la app (en cualquier carpeta).
    private lazy var bundleFiles: [URL] = {
        guard let root = Bundle.main.resourceURL,
              let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
              ) else { return [] }
        let wanted: [String] = Self.extensions + Self.unsupportedExtensions
        var result: [URL] = []
        for case let url as URL in enumerator where wanted.contains(url.pathExtension.lowercased()) {
            result.append(url)
        }
        return result
    }()

    /// Modo «ambiente»: se mezcla con la música de otras apps y respeta el modo silencio.
    func prepareSession() {
        guard !sessionReady else { return }
        sessionReady = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    private var customFolder: URL {
        AppFolders.folder("Sounds")
    }

    /// Busca entre `files` el que se llame como uno de los nombres del sonido (por orden de preferencia).
    private func match(_ kind: SoundKind, in files: [URL], extensions: [String]) -> URL? {
        for alias in kind.aliases {
            for url in files {
                let name: String = url.deletingPathExtension().lastPathComponent.lowercased()
                let ext: String = url.pathExtension.lowercased()
                if name == alias && extensions.contains(ext) {
                    return url
                }
            }
        }
        return nil
    }

    func customURL(for kind: SoundKind) -> URL? {
        for ext in Self.extensions {
            let url: URL = customFolder.appendingPathComponent("\(kind.rawValue).\(ext)")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    func bundledURL(for kind: SoundKind) -> URL? {
        match(kind, in: bundleFiles, extensions: Self.extensions)
    }

    func hasCustom(_ kind: SoundKind) -> Bool {
        customURL(for: kind) != nil
    }

    func hasSound(_ kind: SoundKind) -> Bool {
        customURL(for: kind) != nil || bundledURL(for: kind) != nil
    }

    /// Qué archivo usa cada sonido, o por qué no suena.
    func status(_ kind: SoundKind) -> SoundStatus {
        if let failed = unreadable[kind] { return .unreadable(failed) }
        if let url = customURL(for: kind) { return .imported(url.lastPathComponent) }
        if let url = bundledURL(for: kind) { return .bundled(url.lastPathComponent) }
        if let url = match(kind, in: bundleFiles, extensions: Self.unsupportedExtensions) {
            return .unsupported(url.lastPathComponent)
        }
        return .missing
    }

    private func player(for kind: SoundKind) -> AVAudioPlayer? {
        if let existing = players[kind] { return existing }
        guard let url = customURL(for: kind) ?? bundledURL(for: kind) else { return nil }
        guard let player = try? AVAudioPlayer(contentsOf: url) else {
            unreadable[kind] = url.lastPathComponent
            return nil
        }
        unreadable[kind] = nil
        if kind == .ambient { player.numberOfLoops = -1 }
        player.prepareToPlay()
        players[kind] = player
        return player
    }

    /// Efecto corto (navegación o selección). Sin archivo de sonido, suena el clic del sistema.
    func play(_ kind: SoundKind, volume: Double) {
        guard volume > 0 else { return }
        prepareSession()
        guard let player = player(for: kind) else {
            AudioServicesPlaySystemSound(kind == .navigate ? 1105 : 1104)
            return
        }
        player.volume = Float(volume)
        player.currentTime = 0
        player.play()
    }

    /// Música de ambiente en bucle: con volumen 0 (o sin archivo) se para.
    func updateAmbient(volume: Double) {
        guard volume > 0, let player = player(for: .ambient) else {
            players[.ambient]?.stop()
            return
        }
        prepareSession()
        player.volume = Float(volume)
        if !player.isPlaying { player.play() }
    }

    @discardableResult
    func importSound(from url: URL, for kind: SoundKind) -> Bool {
        let accessing: Bool = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let ext: String = url.pathExtension.lowercased()
        guard Self.extensions.contains(ext) else { return false }
        removeCustom(kind)
        let target: URL = customFolder.appendingPathComponent("\(kind.rawValue).\(ext)")
        do {
            try FileManager.default.copyItem(at: url, to: target)
        } catch {
            return false
        }
        players[kind] = nil
        unreadable[kind] = nil
        return true
    }

    func removeCustom(_ kind: SoundKind) {
        players[kind]?.stop()
        for ext in Self.extensions {
            try? FileManager.default.removeItem(at: customFolder.appendingPathComponent("\(kind.rawValue).\(ext)"))
        }
        players[kind] = nil
        unreadable[kind] = nil
    }
}

// MARK: - Llavero (clave de RetroAchievements)

enum KeychainStore {
    private static let service = "com.omnistation.dock"

    private static func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    /// Algunas instalaciones por sideloading no tienen llavero: entonces se usa UserDefaults.
    private static func fallbackKey(_ account: String) -> String {
        "keychainFallback.\(account)"
    }

    static func read(_ account: String) -> String? {
        var query: [String: Any] = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status: OSStatus = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }
        return UserDefaults.standard.string(forKey: fallbackKey(account))
    }

    static func write(_ value: String, for account: String) {
        delete(account)
        var query: [String: Any] = baseQuery(account)
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status: OSStatus = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            UserDefaults.standard.set(value, forKey: fallbackKey(account))
        }
    }

    static func delete(_ account: String) {
        _ = SecItemDelete(baseQuery(account) as CFDictionary)
        UserDefaults.standard.removeObject(forKey: fallbackKey(account))
    }
}

// MARK: - RetroAchievements (API web)

struct RAProfile {
    let user: String
    let totalPoints: Int
    let truePoints: Int
    let motto: String
    let richPresence: String
    let avatarURL: URL?
}

struct RARecent: Identifiable {
    let id: Int
    let title: String
    let description: String
    let points: Int
    let gameTitle: String
    let badgeURL: URL?
    let date: String
}

struct RAAchievement: Identifiable {
    let id: Int
    let title: String
    let description: String
    let points: Int
    let badgeURL: URL?
    let earned: Bool
    let earnedHardcore: Bool
    let dateEarned: String
    let order: Int
}

struct RAGameProgress {
    let title: String
    let console: String
    let iconURL: URL?
    let total: Int
    let awarded: Int
    let completion: String
    let achievements: [RAAchievement]
}

struct RAGameMatch: Identifiable {
    let id: Int
    let title: String
    let console: String
    let iconURL: URL?
    let achievements: Int
    let score: Double
}

enum RAError: Error {
    case missingCredentials
    case unauthorized
    case badResponse
    case offline
    case unsupportedPlatform
}

/// Listas de juegos por consola ya descargadas (para no pedirlas otra vez).
actor RAListCache {
    static let shared = RAListCache()
    private var lists: [Int: [RAGameMatch]] = [:]

    func list(_ consoleID: Int) -> [RAGameMatch]? {
        lists[consoleID]
    }

    func store(_ list: [RAGameMatch], for consoleID: Int) {
        lists[consoleID] = list
    }
}

enum RetroAchievements {
    static let userKey = "raUsername"
    static let keyAccount = "raWebAPIKey"
    private static let apiBase = "https://retroachievements.org/API/"
    private static let mediaBase = "https://media.retroachievements.org"

    static var username: String {
        UserDefaults.standard.string(forKey: userKey) ?? ""
    }

    /// La clave se lee del llavero una sola vez: leerla en cada repintado de Ajustes iba lento.
    private static var keyCache: String?

    static var apiKey: String {
        if let keyCache { return keyCache }
        let value: String = KeychainStore.read(keyAccount) ?? ""
        keyCache = value
        return value
    }

    static var isConfigured: Bool {
        !username.isEmpty && !apiKey.isEmpty
    }

    static func save(username: String, apiKey: String) {
        UserDefaults.standard.set(username, forKey: userKey)
        KeychainStore.write(apiKey, for: keyAccount)
        keyCache = apiKey
    }

    static func signOut() {
        UserDefaults.standard.removeObject(forKey: userKey)
        KeychainStore.delete(keyAccount)
        keyCache = nil
        clearSession()
    }

    // Sesión recordada: el último perfil que respondió bien, para enseñarlo al momento.
    private static let sessionUserKey = "raSessionUser"
    private static let sessionPointsKey = "raSessionPoints"
    private static let sessionAvatarKey = "raSessionAvatar"

    static var isLoggedIn: Bool {
        isConfigured && !(UserDefaults.standard.string(forKey: sessionUserKey) ?? "").isEmpty
    }

    static func saveSession(_ profile: RAProfile) {
        let defaults = UserDefaults.standard
        defaults.set(profile.user, forKey: sessionUserKey)
        defaults.set(profile.totalPoints, forKey: sessionPointsKey)
        defaults.set(profile.avatarURL?.absoluteString ?? "", forKey: sessionAvatarKey)
    }

    static func clearSession() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: sessionUserKey)
        defaults.removeObject(forKey: sessionPointsKey)
        defaults.removeObject(forKey: sessionAvatarKey)
    }

    static var cachedProfile: RAProfile? {
        let defaults = UserDefaults.standard
        guard isConfigured, let user = defaults.string(forKey: sessionUserKey), !user.isEmpty else { return nil }
        let avatar: String = defaults.string(forKey: sessionAvatarKey) ?? ""
        return RAProfile(
            user: user,
            totalPoints: defaults.integer(forKey: sessionPointsKey),
            truePoints: 0,
            motto: "",
            richPresence: "",
            avatarURL: avatar.isEmpty ? nil : URL(string: avatar)
        )
    }

    /// Inicia sesión: comprueba usuario y clave con el servidor y, si van bien, los guarda.
    static func login(username: String, apiKey: String) async throws -> RAProfile {
        save(username: username, apiKey: apiKey)
        do {
            let result: RAProfile = try await profile()
            saveSession(result)
            return result
        } catch {
            clearSession()
            throw error
        }
    }

    /// IDs de consola de RetroAchievements para cada plataforma de la app.
    static func consoleID(for platform: String) -> Int? {
        switch platform {
        case "Mega Drive": return 1
        case "N64": return 2
        case "SNES": return 3
        case "Game Boy": return 4
        case "GBA": return 5
        case "Game Boy Color": return 6
        case "NES": return 7
        case "Master System": return 11
        case "PS1": return 12
        case "Game Gear": return 15
        case "GameCube": return 16
        case "NDS": return 18
        case "Wii": return 19
        case "PS2": return 21
        case "Saturn": return 39
        case "Dreamcast": return 40
        case "PSP": return 41
        case "3DS": return 62
        default: return nil
        }
    }

    /// Texto simplificado para comparar títulos: sin tildes, regiones ni signos.
    static func normalized(_ title: String) -> String {
        var value: String = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
        value = value.replacingOccurrences(of: "\\([^)]*\\)|\\[[^\\]]*\\]", with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
        value = " " + value + " "
        // RetroAchievements usa los títulos en inglés: equivalencias habituales del español.
        for (spanish, english) in spanishTitles {
            value = value.replacingOccurrences(of: " " + spanish + " ", with: " " + english + " ")
        }
        return value.trimmingCharacters(in: .whitespaces)
    }

    private static let spanishTitles: [(String, String)] = [
        ("rojo fuego", "firered"), ("verde hoja", "leafgreen"), ("oro heartgold", "heartgold"),
        ("plata soulsilver", "soulsilver"), ("esmeralda", "emerald"), ("rubi", "ruby"),
        ("zafiro", "sapphire"), ("oro", "gold"), ("plata", "silver"), ("cristal", "crystal"),
        ("diamante", "diamond"), ("perla", "pearl"), ("platino", "platinum"), ("negro", "black"),
        ("blanco", "white"), ("amarillo", "yellow"), ("azul", "blue"), ("rojo", "red"), ("verde", "green")
    ]

    private static let ignoredWords: Set<String> = ["the", "a", "an", "of", "and", "de", "la", "el", "los", "las", "y", "version"]

    private static func words(_ text: String) -> Set<String> {
        Set(text.split(separator: " ").map(String.init).filter { !ignoredWords.contains($0) })
    }

    /// Parecido entre dos títulos, de 0 a 1.
    static func similarity(_ first: String, _ second: String) -> Double {
        let a: String = normalized(first)
        let b: String = normalized(second)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        if a == b { return 1 }
        let wordsA: Set<String> = words(a)
        let wordsB: Set<String> = words(b)
        let union: Int = wordsA.union(wordsB).count
        guard union > 0 else { return 0 }
        var score: Double = Double(wordsA.intersection(wordsB).count) / Double(union)
        if a.contains(b) || b.contains(a) { score += 0.15 }
        return min(score, 0.99)
    }

    /// Todos los juegos con logros de una consola.
    static func gameList(consoleID: Int) async throws -> [RAGameMatch] {
        if let cached = await RAListCache.shared.list(consoleID) { return cached }
        guard let list = try await request("API_GetGameList.php", ["i": String(consoleID), "f": "1"]) as? [[String: Any]] else {
            throw RAError.badResponse
        }
        var result: [RAGameMatch] = []
        for entry in list {
            result.append(RAGameMatch(
                id: int(entry["ID"]),
                title: text(entry["Title"]),
                console: text(entry["ConsoleName"]),
                iconURL: mediaURL(text(entry["ImageIcon"])),
                achievements: int(entry["NumAchievements"]),
                score: 0
            ))
        }
        await RAListCache.shared.store(result, for: consoleID)
        return result
    }

    /// Juegos de RetroAchievements que más se parecen al nombre, de mejor a peor.
    static func searchGames(title: String, platform: String) async throws -> [RAGameMatch] {
        guard let consoleID = consoleID(for: platform) else { throw RAError.unsupportedPlatform }
        let list: [RAGameMatch] = try await gameList(consoleID: consoleID)
        var scored: [RAGameMatch] = []
        for game in list {
            var score: Double = similarity(title, game.title)
            // Hacks, homebrew y similares van detrás.
            if game.title.contains("~") { score -= 0.3 }
            guard score > 0.2 else { continue }
            scored.append(RAGameMatch(id: game.id, title: game.title, console: game.console, iconURL: game.iconURL, achievements: game.achievements, score: score))
        }
        scored.sort { $0.score > $1.score }
        return Array(scored.prefix(8))
    }

    /// Las imágenes vienen como rutas ("/Badge/123.png") del servidor de medios.
    static func mediaURL(_ path: String) -> URL? {
        guard !path.isEmpty else { return nil }
        if path.hasPrefix("http") { return URL(string: path) }
        let slash: String = path.hasPrefix("/") ? "" : "/"
        return URL(string: mediaBase + slash + path)
    }

    static func badgeURL(_ badgeName: String) -> URL? {
        guard !badgeName.isEmpty else { return nil }
        return URL(string: "\(mediaBase)/Badge/\(badgeName).png")
    }

    // Lectura tolerante: la API a veces da números como texto.
    private static func int(_ value: Any?) -> Int {
        if let number = value as? Int { return number }
        if let number = value as? Double { return Int(number) }
        if let text = value as? String, let number = Int(text) { return number }
        return 0
    }

    private static func text(_ value: Any?) -> String {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }

    private static func request(_ endpoint: String, _ params: [String: String]) async throws -> Any {
        let user: String = username
        let key: String = apiKey
        guard !user.isEmpty, !key.isEmpty else { throw RAError.missingCredentials }
        var components = URLComponents(string: apiBase + endpoint)
        var items: [URLQueryItem] = [URLQueryItem(name: "y", value: key), URLQueryItem(name: "u", value: user)]
        for (name, value) in params {
            items.append(URLQueryItem(name: name, value: value))
        }
        components?.queryItems = items
        guard let url = components?.url else { throw RAError.badResponse }
        let result: (Data, URLResponse)
        do {
            result = try await URLSession.shared.data(from: url)
        } catch {
            throw RAError.offline
        }
        let data: Data = result.0
        let response: URLResponse = result.1
        let status: Int = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 { throw RAError.unauthorized }
        guard (200..<300).contains(status) else { throw RAError.badResponse }
        return try JSONSerialization.jsonObject(with: data)
    }

    static func profile() async throws -> RAProfile {
        guard let json = try await request("API_GetUserProfile.php", [:]) as? [String: Any] else {
            throw RAError.badResponse
        }
        let user: String = text(json["User"])
        guard !user.isEmpty else { throw RAError.unauthorized }
        return RAProfile(
            user: user,
            totalPoints: int(json["TotalPoints"]),
            truePoints: int(json["TotalTruePoints"]),
            motto: text(json["Motto"]),
            richPresence: text(json["RichPresenceMsg"]),
            avatarURL: mediaURL(text(json["UserPic"]))
        )
    }

    /// Logros conseguidos en los últimos `minutes` minutos (por defecto, 30 días).
    static func recentAchievements(minutes: Int = 43_200) async throws -> [RARecent] {
        guard let list = try await request("API_GetUserRecentAchievements.php", ["m": String(minutes)]) as? [[String: Any]] else {
            throw RAError.badResponse
        }
        var result: [RARecent] = []
        for entry in list {
            let badgePath: String = text(entry["BadgeURL"])
            result.append(RARecent(
                id: int(entry["AchievementID"]),
                title: text(entry["Title"]),
                description: text(entry["Description"]),
                points: int(entry["Points"]),
                gameTitle: text(entry["GameTitle"]),
                badgeURL: badgePath.isEmpty ? badgeURL(text(entry["BadgeName"])) : mediaURL(badgePath),
                date: text(entry["Date"])
            ))
        }
        return result
    }

    static func gameProgress(gameID: Int) async throws -> RAGameProgress {
        guard let json = try await request("API_GetGameInfoAndUserProgress.php", ["g": String(gameID)]) as? [String: Any] else {
            throw RAError.badResponse
        }
        var achievements: [RAAchievement] = []
        if let dict = json["Achievements"] as? [String: Any] {
            for value in dict.values {
                guard let entry = value as? [String: Any] else { continue }
                let dateEarned: String = text(entry["DateEarned"])
                let dateHardcore: String = text(entry["DateEarnedHardcore"])
                achievements.append(RAAchievement(
                    id: int(entry["ID"]),
                    title: text(entry["Title"]),
                    description: text(entry["Description"]),
                    points: int(entry["Points"]),
                    badgeURL: badgeURL(text(entry["BadgeName"])),
                    earned: !dateEarned.isEmpty || !dateHardcore.isEmpty,
                    earnedHardcore: !dateHardcore.isEmpty,
                    dateEarned: dateHardcore.isEmpty ? dateEarned : dateHardcore,
                    order: int(entry["DisplayOrder"])
                ))
            }
        }
        achievements.sort { first, second in
            first.order == second.order ? first.id < second.id : first.order < second.order
        }
        return RAGameProgress(
            title: text(json["Title"]),
            console: text(json["ConsoleName"]),
            iconURL: mediaURL(text(json["ImageIcon"])),
            total: int(json["NumAchievements"]),
            awarded: int(json["NumAwardedToUser"]),
            completion: text(json["UserCompletion"]),
            achievements: achievements
        )
    }
}
