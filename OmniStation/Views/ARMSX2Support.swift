import Foundation

// MARK: - ARMSX2 (emulador de PS2 externo)

/// Juegos de PS2 en ARMSX2: se abren con su enlace oficial `armsx2://launch?game=<archivo>`,
/// dentro de LiveContainer (con JIT) o con la app instalada aparte.
enum ARMSX2 {
    enum Location: String {
        case liveContainer = "livecontainer"
        case native = "native"
    }

    static let enabledKey = "armsx2Enabled"
    static let locationKey = "armsx2Location"
    static let lcNameKey = "armsx2LCName"
    static let bundleIDKey = "armsx2BundleID"
    static let installedKey = "armsx2InstalledVersion"
    static let autoCheckKey = "armsx2AutoCheck"
    static let autoInstallKey = "armsx2AutoInstall"
    static let lastCheckKey = "armsx2LastCheck"
    static let latestTagKey = "armsx2LatestTag"
    static let latestURLKey = "armsx2LatestURL"
    static let skippedKey = "armsx2SkippedVersion"

    /// LiveContainer guarda cada app en una carpeta "<Bundle ID>.app".
    static let defaultLCName = "com.armsx2.ios.app"
    static let defaultBundleID = "com.armsx2.ios"
    static let platform = "PS2"

    /// Enlace oficial de ARMSX2 para arrancar un juego de su biblioteca por el nombre del archivo.
    static func gameURL(fileName: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        let encoded: String = fileName.addingPercentEncoding(withAllowedCharacters: allowed) ?? fileName
        return "armsx2://launch?game=" + encoded
    }

    /// LiveContainer: abre ARMSX2 con JIT y le pasa el enlace del juego (open-url en base64).
    static func liveContainerURL(appFolder: String, fileName: String?) -> URL? {
        var components = URLComponents()
        components.scheme = "livecontainer"
        components.host = "livecontainer-launch"
        var items: [URLQueryItem] = [
            URLQueryItem(name: "bundle-name", value: appFolder),
            URLQueryItem(name: "jit", value: "true")
        ]
        if let fileName {
            let link: String = gameURL(fileName: fileName)
            items.append(URLQueryItem(name: "open-url", value: Data(link.utf8).base64EncodedString()))
        }
        components.queryItems = items
        return components.url
    }

    /// Instalar o actualizar una IPA: LiveContainer, SideStore o AltStore la descargan e instalan.
    static func installURLs(ipa: String, location: Location) -> [URL] {
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

// MARK: - Versiones de ARMSX2 en GitHub

struct ARMSX2Release: Equatable {
    let tag: String
    let name: String
    let ipaURL: String
    let date: Date?
}

enum ARMSX2Updater {
    private struct GitHubRelease: Decodable {
        let tag_name: String
        let name: String?
        let draft: Bool?
        let published_at: String?
        let assets: [GitHubAsset]
    }

    private struct GitHubAsset: Decodable {
        let name: String
        let browser_download_url: String
    }

    private static let releasesURL = URL(string: "https://api.github.com/repos/ARMSX2/ARMSX2/releases?per_page=20")

    /// La versión más reciente que trae IPA de iOS (ahora solo las nightly la incluyen).
    static func latest() async throws -> ARMSX2Release? {
        guard let url = releasesURL else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("OmniStationDock", forHTTPHeaderField: "User-Agent")
        let result: (Data, URLResponse) = try await URLSession.shared.data(for: request)
        if let http = result.1 as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        let releases: [GitHubRelease] = try JSONDecoder().decode([GitHubRelease].self, from: result.0)
        let formatter = ISO8601DateFormatter()
        for release in releases where release.draft != true {
            guard let asset = release.assets.first(where: isIOSPackage) else { continue }
            let date: Date? = release.published_at.flatMap { formatter.date(from: $0) }
            return ARMSX2Release(tag: release.tag_name, name: release.name ?? release.tag_name, ipaURL: asset.browser_download_url, date: date)
        }
        return nil
    }

    private static func isIOSPackage(_ asset: GitHubAsset) -> Bool {
        let name: String = asset.name.lowercased()
        return name.hasSuffix(".ipa") && name.contains("ios")
    }

    /// ¿Toca mirar otra vez? (como mucho cada 6 horas).
    static var shouldCheck: Bool {
        let last: Double = UserDefaults.standard.double(forKey: ARMSX2.lastCheckKey)
        return Date().timeIntervalSince1970 - last > 6 * 3600
    }

    static func remember(_ release: ARMSX2Release) {
        let defaults = UserDefaults.standard
        defaults.set(Date().timeIntervalSince1970, forKey: ARMSX2.lastCheckKey)
        defaults.set(release.tag, forKey: ARMSX2.latestTagKey)
        defaults.set(release.ipaURL, forKey: ARMSX2.latestURLKey)
    }

    /// Nombre corto de una versión: "nightly-20261016" → "20261016".
    static func shortName(_ tag: String) -> String {
        tag.hasPrefix("nightly-") ? String(tag.dropFirst("nightly-".count)) : tag
    }
}
