import SwiftUI

@main
struct OmniStationDockApp: App {
    var body: some Scene {
        WindowGroup {
            WelcomeView()
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
        }
    }
}
