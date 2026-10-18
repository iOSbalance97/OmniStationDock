import Foundation
import ObjectiveC

/// JIT para otra app de LiveContainer cuando OmniStation también está dentro de LiveContainer.
///
/// Si una app de LiveContainer abre otra con `livecontainer://livecontainer-launch`, LiveContainer
/// solo se reinicia con la app elegida y no pide JIT (en iOS 26 la abre en modo sin JIT). Lo que
/// hace LiveContainer desde su propia lista es: apuntar la app elegida («selected») y el enlace que
/// debe recibir («launchAppUrlScheme») en sus ajustes y pedir a StikDebug que relance LiveContainer
/// con el depurador. Aquí se hace exactamente lo mismo, desde dentro de LiveContainer.
enum LiveContainerJIT {

    /// Solo tiene sentido dentro de LiveContainer.
    static var isAvailable: Bool {
        DebugSupport.isInsideLiveContainer && userDefaults != nil && bundleID != nil
    }

    /// ¿Se puede pedir el JIT desde aquí? (activador de LiveContainer: StikDebug o SideStore).
    static var canRequestJIT: Bool {
        guard isAvailable, let liveContainerID = bundleID else { return false }
        return enablerURL(liveContainerID: liveContainerID, script: nil) != nil
    }

    // MARK: Datos de LiveContainer (los publica LiveContainer en NSUserDefaults)

    private static func classProperty(_ name: String) -> AnyObject? {
        let selector: Selector = NSSelectorFromString(name)
        guard let method = class_getClassMethod(UserDefaults.self, selector) else { return nil }
        typealias Getter = @convention(c) (AnyClass, Selector) -> AnyObject?
        let getter: Getter = unsafeBitCast(method_getImplementation(method), to: Getter.self)
        return getter(UserDefaults.self, selector)
    }

    /// Ajustes propios de LiveContainer (no los de la app que corre dentro).
    private static var userDefaults: UserDefaults? {
        classProperty("lcUserDefaults") as? UserDefaults
    }

    /// Ajustes compartidos de LiveContainer (grupo de SideStore/AltStore).
    private static var sharedDefaults: UserDefaults? {
        classProperty("lcSharedDefaults") as? UserDefaults
    }

    /// Bundle ID real de LiveContainer (el que StikDebug tiene que relanzar).
    private static var bundleID: String? {
        (classProperty("lcMainBundle") as? Bundle)?.bundleIdentifier
    }

    private static var appGroupPath: String? {
        classProperty("lcAppGroupPath") as? String
    }

    // MARK: Apps de LiveContainer

    /// Carpeta de la app dentro de LiveContainer (privada o compartida).
    static func appFolderURL(_ folder: String) -> URL? {
        var candidates: [URL] = []
        if let home = ProcessInfo.processInfo.environment["LC_HOME_PATH"] {
            candidates.append(URL(fileURLWithPath: home).appendingPathComponent("Documents/Applications").appendingPathComponent(folder))
        }
        if let group = appGroupPath {
            candidates.append(URL(fileURLWithPath: group).appendingPathComponent("LiveContainer/Applications").appendingPathComponent(folder))
        }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Script de JIT que tiene puesto esa app en sus ajustes de LiveContainer (en base64).
    private static func script(forFolder folder: String) -> String? {
        guard let appURL = appFolderURL(folder),
              let info = NSDictionary(contentsOf: appURL.appendingPathComponent("LCAppInfo.plist")) as? [String: Any],
              let script = info["jitLaunchScriptJs"] as? String, !script.isEmpty else { return nil }
        return script
    }

    // MARK: Pedir el JIT

    enum Request {
        /// Enlace para el activador de JIT (StikDebug o SideStore).
        case ready(URL)
        /// LiveContainer no tiene ninguna app con esa carpeta.
        case appNotFound
        /// El activador elegido en LiveContainer no se puede usar desde aquí.
        case unsupported
    }

    /// Prepara LiveContainer para abrir `folder` con JIT y devuelve el enlace del activador.
    /// `openURL` es el enlace que recibirá la app al abrirse (por ejemplo, el del juego).
    static func request(folder: String, container: String? = nil, openURL: String?) -> Request {
        guard let defaults = userDefaults, let liveContainerID = bundleID else { return .unsupported }
        guard appFolderURL(folder) != nil else { return .appNotFound }
        guard let url = enablerURL(liveContainerID: liveContainerID, script: script(forFolder: folder)) else {
            return .unsupported
        }
        defaults.set(folder, forKey: "selected")
        if let container, !container.isEmpty {
            defaults.set(container, forKey: "selectedContainer")
        } else {
            defaults.removeObject(forKey: "selectedContainer")
        }
        if let openURL, !openURL.isEmpty {
            defaults.set(openURL, forKey: "launchAppUrlScheme")
        } else {
            defaults.removeObject(forKey: "launchAppUrlScheme")
        }
        defaults.synchronize()
        return .ready(url)
    }

    /// Lo mismo a partir de un enlace de lanzamiento de LiveContainer ya guardado.
    static func request(forLaunchLink link: String) -> Request {
        guard let components = URLComponents(string: link) else { return .unsupported }
        var folder: String? = nil
        var container: String? = nil
        var openURL: String? = nil
        for item in components.queryItems ?? [] {
            switch item.name {
            case "bundle-name": folder = item.value
            case "container-folder-name": container = item.value
            case "open-url":
                if let value = item.value, let data = Data(base64Encoded: value) {
                    openURL = String(data: data, encoding: .utf8)
                }
            default: break
            }
        }
        guard let folder, !folder.isEmpty else { return .unsupported }
        return request(folder: folder, container: container, openURL: openURL)
    }

    /// Si el activador no llega a abrirse, se deshace lo apuntado para que LiveContainer
    /// no abra la app sola la próxima vez.
    static func cancel() {
        guard let defaults = userDefaults else { return }
        defaults.removeObject(forKey: "selected")
        defaults.removeObject(forKey: "selectedContainer")
        defaults.removeObject(forKey: "launchAppUrlScheme")
        defaults.synchronize()
    }

    /// El mismo enlace que usa LiveContainer según el activador que tenga elegido.
    private static func enablerURL(liveContainerID: String, script: String?) -> URL? {
        let enabler: Int = sharedDefaults?.integer(forKey: "LCJITEnablerType") ?? -1
        var components = URLComponents()
        var items: [URLQueryItem] = [URLQueryItem(name: "bundle-id", value: liveContainerID)]
        switch enabler {
        case 1:
            // StikDebug
            components.scheme = "stikjit"
            if let script { items.append(URLQueryItem(name: "script-data", value: script)) }
        case 4:
            // SideStore
            components.scheme = "sidestore"
        default:
            return nil
        }
        components.host = "enable-jit"
        components.queryItems = items
        return components.url
    }
}
