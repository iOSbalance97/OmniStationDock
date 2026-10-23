import SwiftUI
import MetricKit

/// Permite cambiar en tiempo de ejecución las orientaciones admitidas
/// (ajustes «Bloquear horizontal» y «Dock con HDMI») y da su escena a la tele.
final class AppDelegate: NSObject, UIApplicationDelegate, MXMetricManagerSubscriber {
    /// Informes de cierres inesperados (MetricKit): iOS los entrega al abrir la app la vez
    /// siguiente y se guardan en Archivos → OmniStation Dock → «Registro de cierres.txt».
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        MXMetricManager.shared.add(self)
        return true
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let crashes: Int = payloads.reduce(0) { $0 + ($1.crashDiagnostics?.count ?? 0) }
        guard crashes > 0 || payloads.contains(where: { ($0.hangDiagnostics?.count ?? 0) > 0 }) else { return }
        var text: String = ""
        for payload in payloads {
            text += "===== \(payload.timeStampBegin) – \(payload.timeStampEnd)\n"
            for crash in payload.crashDiagnostics ?? [] {
                let signal: String = crash.signal.map { "\($0)" } ?? "-"
                let exception: String = crash.exceptionType.map { "\($0)" } ?? "-"
                text += "Cierre: señal \(signal), excepción \(exception), motivo: \(crash.terminationReason ?? "-")\n"
            }
            if let json = String(data: payload.jsonRepresentation(), encoding: .utf8) {
                text += json + "\n"
            }
        }
        let folder: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url: URL = folder.appendingPathComponent("Registro de cierres.txt")
        let old: String = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        // Solo lo último (el archivo no crece sin fin).
        let joined: String = String((old + text).suffix(400_000))
        try? joined.write(to: url, atomically: true, encoding: .utf8)
    }

    static var orientationMask: UIInterfaceOrientationMask = {
        UserDefaults.standard.bool(forKey: "keepLandscape") ? .landscape : .allButUpsideDown
    }()

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AppDelegate.orientationMask
    }

    /// Con una tele (AirPlay o HDMI), su escena es de OSExternalDisplay: duplica el iPhone
    /// salvo durante una partida de los núcleos integrados, que se ve a pantalla completa.
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let role: UISceneSession.Role = connectingSceneSession.role
        OSExternalDisplay.noteSceneRequest(forRole: role.rawValue)
        if role == .windowExternalDisplayNonInteractive {
            let configuration = UISceneConfiguration(name: "OmniStation TV", sessionRole: role)
            configuration.delegateClass = OSExternalDisplaySceneDelegate.self
            return configuration
        }
        // La de la app la sigue creando SwiftUI (WindowGroup).
        return UISceneConfiguration(name: nil, sessionRole: role)
    }
}

@main
struct OmniStationDockApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Orbitron y Space Grotesk van dentro de la app: se registran antes de pintar nada.
        AppFont.register()
    }

    var body: some Scene {
        WindowGroup {
            WelcomeView()
                .preferredColorScheme(.dark)
                .statusBarHidden(false)
                .onOpenURL { url in
                    IncomingLinks.shared.url = url
                }
        }
    }
}
