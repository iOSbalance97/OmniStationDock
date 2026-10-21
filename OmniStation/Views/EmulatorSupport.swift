import Foundation

// MARK: - Emuladores externos

/// Emuladores que OmniStation sabe abrir directamente en un juego, con JIT.
enum Emulator: String, CaseIterable, Identifiable {
    case armsx2
    case melonx

    enum Location: String {
        case liveContainer = "livecontainer"
        case native = "native"
    }

    var id: String { rawValue }

    var name: String {
        switch self {
        case .armsx2: return "ARMSX2"
        case .melonx: return "MeloNX"
        }
    }

    /// Plataforma de OmniStation cuyos juegos abre.
    var platform: String {
        switch self {
        case .armsx2: return "PS2"
        case .melonx: return "Switch"
        }
    }

    var symbol: String {
        switch self {
        case .armsx2: return "opticaldisc.fill"
        case .melonx: return "gamecontroller.fill"
        }
    }

    /// Archivos de juego que se buscan en su carpeta.
    var extensions: [String] {
        switch self {
        case .armsx2: return ["iso", "chd", "cso", "zso", "gz"]
        case .melonx: return ["nsp", "xci", "nro"]
        }
    }

    /// LiveContainer guarda cada app en una carpeta "<Bundle ID>.app".
    var defaultLCFolder: String { defaultBundleID + ".app" }

    var defaultBundleID: String {
        switch self {
        case .armsx2: return "com.armsx2.ios"
        case .melonx: return "com.stossy11.MeloNX"
        }
    }

    /// Nombre de la app (decide su script de JIT con TXM).
    var appName: String {
        switch self {
        case .armsx2: return "ARMSX2 iOS"
        case .melonx: return "MeloNX"
        }
    }

    /// MeloNX abre el juego y espera él solo a tener JIT («Waiting for JIT»), así que con el JIT
    /// integrado se le puede dar después de abrirlo. ARMSX2 no espera: necesita el JIT antes.
    var waitsForJIT: Bool {
        self == .melonx
    }

    /// Enlace oficial del emulador para arrancar un juego.
    /// - ARMSX2: por el nombre del archivo en su biblioteca.
    /// - MeloNX: por el Title ID si el archivo lo lleva entre corchetes; si no, por el título.
    func gameLink(fileName: String, title: String, override: String? = nil) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        // Lo que se haya guardado para este juego (Title ID o título exacto en el emulador) manda.
        if self == .melonx, let override, !override.isEmpty {
            if Self.isTitleID(override) {
                return "melonx://game?id=" + override.lowercased()
            }
            let encoded: String = override.addingPercentEncoding(withAllowedCharacters: allowed) ?? override
            return "melonx://game?name=" + encoded
        }
        switch self {
        case .armsx2:
            let encoded: String = fileName.addingPercentEncoding(withAllowedCharacters: allowed) ?? fileName
            return "armsx2://launch?game=" + encoded
        case .melonx:
            if let titleID = Self.titleID(in: fileName) {
                return "melonx://game?id=" + titleID
            }
            let encoded: String = title.addingPercentEncoding(withAllowedCharacters: allowed) ?? title
            return "melonx://game?name=" + encoded
        }
    }

    /// Explicación corta de cómo se añaden los juegos de este emulador cuando va como app aparte.
    /// Lo mismo, más largo, está en Ajustes → el emulador → «Cómo funciona».
    func setupHint(liveContainer: Bool, lang: String) -> String {
        switch (self, liveContainer) {
        case (.armsx2, true):
            return L10n.tr("Pon los juegos en ARMSX2 como siempre (su carpeta iso). OmniStation los ve solos y los abre en ARMSX2.", lang)
        case (.armsx2, false):
            return L10n.tr("Elige en Archivos la carpeta donde tienes los juegos de ARMSX2.", lang)
        case (.melonx, true):
            return L10n.tr("Añade los juegos en MeloNX como siempre. OmniStation los ve solos; las actualizaciones y DLC salen dentro de cada juego y se instalan desde MeloNX.", lang)
        case (.melonx, false):
            return L10n.tr("Elige en Archivos la carpeta de juegos de MeloNX. Las actualizaciones y DLC salen dentro de cada juego y se instalan desde MeloNX.", lang)
        }
    }

    static func isTitleID(_ text: String) -> Bool {
        let hex = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        return text.count == 16 && text.unicodeScalars.allSatisfy { hex.contains($0) }
    }

    /// Title ID de Switch escrito en el nombre del archivo, por ejemplo "Juego [0100ABCD12340000].nsp".
    static func titleID(in fileName: String) -> String? {
        let hex = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        var current: String = ""
        var inside = false
        for character in fileName {
            if character == "[" {
                inside = true
                current = ""
            } else if character == "]" {
                if inside, current.count == 16, current.hasPrefix("01"),
                   current.unicodeScalars.allSatisfy({ hex.contains($0) }) {
                    return current.lowercased()
                }
                inside = false
            } else if inside {
                current.append(character)
            }
        }
        return nil
    }

    /// Versiones publicadas (API de GitHub o de Forgejo, que responden igual).
    var releasesURL: URL? {
        switch self {
        case .armsx2: return URL(string: "https://api.github.com/repos/ARMSX2/ARMSX2/releases?per_page=20")
        case .melonx: return URL(string: "https://starforgejo.dev/api/v1/repos/projects/MeloNX/releases?limit=10")
        }
    }

    /// ¿Este archivo publicado es la IPA de iOS?
    func isIOSPackage(_ assetName: String) -> Bool {
        let name: String = assetName.lowercased()
        guard name.hasSuffix(".ipa") else { return false }
        return self == .armsx2 ? name.contains("ios") : true
    }

    /// Emulador que abre los juegos de una plataforma.
    static func handling(platform: String) -> Emulator? {
        allCases.first { $0.platform == platform }
    }
}

// MARK: - Ajustes de cada emulador

/// Ajustes guardados por emulador ("armsx2Enabled", "melonxLocation"…; los de ARMSX2 son los de antes).
enum EmulatorStore {
    private static var defaults: UserDefaults { .standard }

    private static func key(_ emulator: Emulator, _ suffix: String) -> String {
        emulator.rawValue + suffix
    }

    static func isEnabled(_ emulator: Emulator) -> Bool {
        defaults.object(forKey: key(emulator, "Enabled")) as? Bool ?? true
    }

    static func setEnabled(_ value: Bool, _ emulator: Emulator) {
        defaults.set(value, forKey: key(emulator, "Enabled"))
    }

    /// Dónde está instalado; si no se ha elegido, lo mismo que OmniStation.
    static func location(_ emulator: Emulator, installMethod: String) -> Emulator.Location {
        if let raw = defaults.string(forKey: key(emulator, "Location")), let location = Emulator.Location(rawValue: raw) {
            return location
        }
        return installMethod == InstallMethod.sideStore.rawValue ? .native : .liveContainer
    }

    static func setLocation(_ location: Emulator.Location, _ emulator: Emulator) {
        defaults.set(location.rawValue, forKey: key(emulator, "Location"))
    }

    static func lcFolder(_ emulator: Emulator) -> String {
        let value: String = defaults.string(forKey: key(emulator, "LCName")) ?? ""
        return value.isEmpty ? emulator.defaultLCFolder : value
    }

    static func setLCFolder(_ value: String, _ emulator: Emulator) {
        defaults.set(value, forKey: key(emulator, "LCName"))
    }

    static func bundleID(_ emulator: Emulator) -> String {
        let value: String = defaults.string(forKey: key(emulator, "BundleID")) ?? ""
        return value.isEmpty ? emulator.defaultBundleID : value
    }

    static func setBundleID(_ value: String, _ emulator: Emulator) {
        defaults.set(value, forKey: key(emulator, "BundleID"))
    }

    // Carpeta de juegos propia del emulador.

    static func folderBookmark(_ emulator: Emulator) -> Data? {
        defaults.data(forKey: key(emulator, "FolderBookmark"))
    }

    static func folderName(_ emulator: Emulator) -> String {
        defaults.string(forKey: key(emulator, "FolderName")) ?? ""
    }

    static func setFolder(bookmark: Data?, name: String, _ emulator: Emulator) {
        defaults.set(bookmark, forKey: key(emulator, "FolderBookmark"))
        defaults.set(name, forKey: key(emulator, "FolderName"))
    }

    // Versiones.

    static func installedVersion(_ emulator: Emulator) -> String {
        defaults.string(forKey: key(emulator, "InstalledVersion")) ?? ""
    }

    static func setInstalledVersion(_ value: String, _ emulator: Emulator) {
        defaults.set(value, forKey: key(emulator, "InstalledVersion"))
    }

    static func latestTag(_ emulator: Emulator) -> String {
        defaults.string(forKey: key(emulator, "LatestTag")) ?? ""
    }

    static func latestURL(_ emulator: Emulator) -> String {
        defaults.string(forKey: key(emulator, "LatestURL")) ?? ""
    }

    static func autoCheck(_ emulator: Emulator) -> Bool {
        defaults.object(forKey: key(emulator, "AutoCheck")) as? Bool ?? true
    }

    static func setAutoCheck(_ value: Bool, _ emulator: Emulator) {
        defaults.set(value, forKey: key(emulator, "AutoCheck"))
    }

    static func autoInstall(_ emulator: Emulator) -> Bool {
        defaults.bool(forKey: key(emulator, "AutoInstall"))
    }

    static func setAutoInstall(_ value: Bool, _ emulator: Emulator) {
        defaults.set(value, forKey: key(emulator, "AutoInstall"))
    }

    /// ¿Toca mirar otra vez? (como mucho cada 6 horas).
    static func shouldCheck(_ emulator: Emulator) -> Bool {
        let last: Double = defaults.double(forKey: key(emulator, "LastCheck"))
        return Date().timeIntervalSince1970 - last > 6 * 3600
    }

    static func remember(_ release: EmulatorRelease, _ emulator: Emulator) {
        defaults.set(Date().timeIntervalSince1970, forKey: key(emulator, "LastCheck"))
        defaults.set(release.tag, forKey: key(emulator, "LatestTag"))
        defaults.set(release.ipaURL, forKey: key(emulator, "LatestURL"))
    }
}

// MARK: - Enlaces de LiveContainer e instalación

enum EmulatorLinks {
    /// LiveContainer: abre la app con JIT y le pasa el enlace del juego (open-url en base64).
    static func liveContainerURL(appFolder: String, gameLink: String?) -> URL? {
        var components = URLComponents()
        components.scheme = "livecontainer"
        components.host = "livecontainer-launch"
        var items: [URLQueryItem] = [
            URLQueryItem(name: "bundle-name", value: appFolder),
            URLQueryItem(name: "jit", value: "true")
        ]
        if let gameLink {
            items.append(URLQueryItem(name: "open-url", value: Data(gameLink.utf8).base64EncodedString()))
        }
        components.queryItems = items
        return components.url
    }

    /// Instalar o actualizar una IPA: LiveContainer, SideStore o AltStore la descargan e instalan.
    static func installURLs(ipa: String, location: Emulator.Location) -> [URL] {
        let schemes: [String] = location == .liveContainer ? ["livecontainer"] : ["sidestore", "altstore"]
        return schemes.compactMap { scheme in
            var components = URLComponents()
            components.scheme = scheme
            components.host = "install"
            components.queryItems = [URLQueryItem(name: "url", value: ipa)]
            return components.url
        }
    }
}

// MARK: - Versiones nuevas

struct EmulatorRelease: Equatable {
    let tag: String
    let name: String
    let ipaURL: String
}

enum EmulatorUpdater {
    private struct Release: Decodable {
        let tag_name: String
        let name: String?
        let draft: Bool?
        let assets: [Asset]
    }

    private struct Asset: Decodable {
        let name: String
        let browser_download_url: String
    }

    /// La versión más reciente que trae IPA de iOS.
    static func latest(_ emulator: Emulator) async throws -> EmulatorRelease? {
        guard let url = emulator.releasesURL else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("OmniStationDock", forHTTPHeaderField: "User-Agent")
        let result: (Data, URLResponse) = try await URLSession.shared.data(for: request)
        if let http = result.1 as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        let releases: [Release] = try JSONDecoder().decode([Release].self, from: result.0)
        for release in releases where release.draft != true {
            guard let asset = release.assets.first(where: { emulator.isIOSPackage($0.name) }) else { continue }
            return EmulatorRelease(tag: release.tag_name, name: release.name ?? release.tag_name, ipaURL: asset.browser_download_url)
        }
        return nil
    }

    /// Nombre corto de una versión: "nightly-20261016" → "20261016".
    static func shortName(_ tag: String) -> String {
        tag.hasPrefix("nightly-") ? String(tag.dropFirst("nightly-".count)) : tag
    }
}

// MARK: - Enlaces que llegan a OmniStation

/// Enlaces "omnistation://…" que abren la app (por ejemplo, la lista de juegos que devuelve MeloNX).
/// Se guardan aquí porque pueden llegar antes de que se vea la pantalla principal.
final class IncomingLinks: ObservableObject {
    static let shared = IncomingLinks()
    @Published var url: URL?
}

// MARK: - Biblioteca de MeloNX

/// MeloNX abre un juego por su Title ID o por su título exacto (con tildes y todo). Para no depender
/// del nombre del archivo, OmniStation le pide su lista de juegos (`melonx://gameInfo`) y empareja
/// cada archivo con el título que tiene MeloNX.
struct MeloNXGame: Decodable {
    let titleName: String
    let titleId: String
    let iconData: Data?
}

enum MeloNXLibrary {
    /// Enlace que pide a MeloNX su lista; MeloNX responde con "omnistation://melonx?games=…".
    static let requestURL: URL? = URL(string: "melonx://gameInfo?scheme=omnistation")

    /// Lee la respuesta de MeloNX.
    static func games(from url: URL) -> [MeloNXGame]? {
        guard url.scheme?.lowercased() == "omnistation", url.host?.lowercased() == "melonx",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let text = components.queryItems?.first(where: { $0.name == "games" })?.value else { return nil }
        var base64: String = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONDecoder().decode([MeloNXGame].self, from: data)
    }

    /// Texto comparable: minúsculas, sin tildes, sin lo que va entre corchetes o paréntesis.
    static func normalized(_ text: String) -> [String] {
        var cleaned: String = ""
        var depth: Int = 0
        for character in text {
            if character == "[" || character == "(" { depth += 1; continue }
            if character == "]" || character == ")" { depth = max(0, depth - 1); continue }
            if depth == 0 { cleaned.append(character) }
        }
        let folded: String = cleaned.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
        let words: [String] = folded.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return words
    }

    /// El juego de MeloNX que mejor encaja con un nombre (nil si ninguno se parece lo bastante).
    static func bestMatch(for name: String, in games: [MeloNXGame]) -> MeloNXGame? {
        let target: [String] = normalized(name)
        guard !target.isEmpty else { return nil }
        let targetSet: Set<String> = Set(target)
        let targetJoined: String = target.joined()
        var best: MeloNXGame? = nil
        var bestScore: Double = 0
        for game in games {
            let words: [String] = normalized(game.titleName)
            guard !words.isEmpty else { continue }
            let joined: String = words.joined()
            var score: Double
            if joined == targetJoined {
                score = 1
            } else {
                let set: Set<String> = Set(words)
                let common: Double = Double(set.intersection(targetSet).count)
                score = common / Double(set.union(targetSet).count)
                if joined.contains(targetJoined) || targetJoined.contains(joined) { score = max(score, 0.8) }
            }
            if score > bestScore {
                bestScore = score
                best = game
            }
        }
        return bestScore >= 0.5 ? best : nil
    }
}

// MARK: - Biblioteca de ARMSX2

/// Un juego de la lista que exporta ARMSX2 (`armsx2://library`).
struct ARMSX2Game: Decodable {
    let title: String
    let fileName: String
    let serial: String?
}

/// ARMSX2 abre sus juegos por el nombre del archivo, pero conoce su título de verdad (por su base
/// de datos). OmniStation le pide la lista y usa ese título como nombre del juego.
enum ARMSX2Library {
    private struct Export: Decodable {
        let schema: String?
        let games: [ARMSX2Game]
    }

    /// ARMSX2 pide confirmación y responde con "omnistation://armsx2?source=armsx2-ios&payload=…".
    static var requestURL: URL? {
        var components = URLComponents()
        components.scheme = "armsx2"
        components.host = "library"
        components.queryItems = [URLQueryItem(name: "callback", value: "omnistation://armsx2")]
        return components.url
    }

    /// Lee la respuesta de ARMSX2 (JSON en base64url sin relleno).
    static func games(from url: URL) -> [ARMSX2Game]? {
        guard url.scheme?.lowercased() == "omnistation", url.host?.lowercased() == "armsx2",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let text = components.queryItems?.first(where: { $0.name == "payload" })?.value else { return nil }
        var base64: String = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        guard let data = Data(base64Encoded: base64),
              let export = try? JSONDecoder().decode(Export.self, from: data) else { return nil }
        return export.games
    }

    /// El juego de ARMSX2 con ese nombre de archivo (igual, o sin distinguir mayúsculas).
    static func match(fileName: String, in games: [ARMSX2Game]) -> ARMSX2Game? {
        if let exact = games.first(where: { $0.fileName == fileName }) { return exact }
        return games.first { $0.fileName.caseInsensitiveCompare(fileName) == .orderedSame }
    }
}

// MARK: - Carpetas de los emuladores dentro de LiveContainer

/// Con OmniStation dentro de LiveContainer, cada app tiene su carpeta de datos en
/// LiveContainer/Data/Application/<carpeta>, todas en el mismo almacenamiento. Así los juegos de
/// un emulador se leen directamente por su ruta: sin el selector de carpetas (que en LiveContainer
/// copia lo elegido a la carpeta Inbox de OmniStation) y sin archivos de relleno.
enum LiveContainerStorage {
    /// Carpeta Documents de LiveContainer (la que tiene Applications y Data).
    static var root: URL? {
        guard DebugSupport.isInsideLiveContainer else { return nil }
        var candidates: [URL] = []
        // Nuestra casa es LiveContainer/Documents/Data/Application/<carpeta de OmniStation>.
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).standardizedFileURL
        candidates.append(home.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
        if let raw = getenv("LC_HOME_PATH") {
            let lcHome = URL(fileURLWithPath: String(cString: raw), isDirectory: true)
            candidates.append(lcHome.appendingPathComponent("Documents", isDirectory: true))
            candidates.append(lcHome)
        }
        let manager = FileManager.default
        return candidates.first { url in
            manager.fileExists(atPath: url.appendingPathComponent("Data/Application", isDirectory: true).path)
        }
    }

    /// Carpeta de datos de la app de LiveContainer `appFolder` («<Bundle ID>.app»).
    static func dataContainer(appFolder: String, bundleID: String) -> URL? {
        guard let root else { return nil }
        let manager = FileManager.default
        let data: URL = root.appendingPathComponent("Data/Application", isDirectory: true)
        // 1) LCAppInfo.plist de la app dice cuál es su carpeta de datos.
        for apps in ["Applications", "Data/Applications"] {
            let info: URL = root.appendingPathComponent(apps, isDirectory: true)
                .appendingPathComponent(appFolder, isDirectory: true)
                .appendingPathComponent("LCAppInfo.plist")
            guard let plist = NSDictionary(contentsOf: info) as? [String: Any] else { continue }
            var names: [String] = []
            if let uuid = plist["LCDataUUID"] as? String { names.append(uuid) }
            if let containers = plist["LCContainers"] as? [[String: Any]] {
                names += containers.compactMap { $0["folderName"] as? String }
            }
            for name in names {
                let folder: URL = data.appendingPathComponent(name, isDirectory: true)
                if manager.fileExists(atPath: folder.path) { return folder }
            }
        }
        // 2) Si no, la carpeta que se llame como la app o su Bundle ID.
        let wanted: Set<String> = [appFolder.lowercased(), bundleID.lowercased(),
                                   (appFolder as NSString).deletingPathExtension.lowercased()]
        let names: [String] = (try? manager.contentsOfDirectory(atPath: data.path)) ?? []
        if let name = names.first(where: { wanted.contains($0.lowercased()) }) {
            return data.appendingPathComponent(name, isDirectory: true)
        }
        return nil
    }

    /// Carpeta donde buscar los juegos del emulador: su Documents.
    static func gamesFolder(_ emulator: Emulator) -> URL? {
        guard let container = dataContainer(appFolder: EmulatorStore.lcFolder(emulator), bundleID: EmulatorStore.bundleID(emulator)) else { return nil }
        let documents: URL = container.appendingPathComponent("Documents", isDirectory: true)
        return FileManager.default.fileExists(atPath: documents.path) ? documents : nil
    }
}
