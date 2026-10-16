import SwiftUI

/// Permite cambiar en tiempo de ejecución las orientaciones admitidas
/// (ajustes «Dock en horizontal» y «Horizontal con HDMI»).
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationMask: UIInterfaceOrientationMask = {
        UserDefaults.standard.bool(forKey: "keepLandscape") ? .landscape : .allButUpsideDown
    }()

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AppDelegate.orientationMask
    }
}

@main
struct OmniStationDockApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            WelcomeView()
                .preferredColorScheme(.dark)
                .statusBarHidden(false)
        }
    }
}
