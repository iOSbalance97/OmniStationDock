import SwiftUI

/// Permite cambiar en tiempo de ejecución las orientaciones admitidas
/// (ajustes «Bloquear horizontal» y «Dock con HDMI») y da su escena a la tele.
final class AppDelegate: NSObject, UIApplicationDelegate {
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
