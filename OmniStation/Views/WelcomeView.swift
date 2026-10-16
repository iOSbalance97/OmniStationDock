import SwiftUI

struct WelcomeView: View {
    @AppStorage("appLanguage") private var appLanguage = "system"
    @State private var isVisible = false
    @State private var showHome = false

    init() {
        // Si el ajuste «Bienvenida animada» está desactivado, se entra directo a la pantalla principal.
        let showWelcome = UserDefaults.standard.object(forKey: "showWelcome") as? Bool ?? true
        _showHome = State(initialValue: !showWelcome)
    }

    var body: some View {
        ZStack {
            if showHome {
                HomeView().transition(.opacity)
            } else {
                welcomeScreen.transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            guard !showHome else { return }
            withAnimation(.easeOut(duration: 0.9)) { isVisible = true }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.45)) { showHome = true }
        }
    }

    private var welcomeScreen: some View {
        GeometryReader { geometry in
            ZStack {
                Image("SpaceBackground")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [
                        Color(red: 0.005, green: 0.018, blue: 0.055).opacity(0.2),
                        Color(red: 0.005, green: 0.025, blue: 0.08).opacity(0.45),
                        .black.opacity(0.72)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer(minLength: 24)

                    // El PNG del planeta es transparente y con el anillo completo (ya no hace falta mezclar).
                    let planetSize = min(min(geometry.size.width * 0.80, geometry.size.height * 0.40), 380)
                    Image("WelcomePlanet")
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: planetSize, height: planetSize)
                        .shadow(color: Color.cyan.opacity(0.34), radius: 22)
                        .shadow(color: Color.blue.opacity(0.26), radius: 38)
                        .accessibilityLabel("Planeta de OmniStation Dock")

                    VStack(spacing: 3) {
                        Text("OMNISTATION")
                            .font(.system(size: min(geometry.size.width * 0.075, 31), weight: .medium, design: .rounded))
                            .tracking(geometry.size.width < 400 ? 3.5 : 5.5)
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.65)
                            .lineLimit(1)

                        Text("DOCK")
                            .font(.system(size: min(geometry.size.width * 0.09, 38), weight: .bold, design: .rounded))
                            .tracking(geometry.size.width < 400 ? 7 : 10)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(red: 0.08, green: 0.42, blue: 1), Color(red: 0.0, green: 0.88, blue: 1)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                    .padding(.top, 22)

                    Spacer()

                    Text(L10n.tr("TU UNIVERSO DE JUEGOS,\nEN UN SOLO LUGAR.", appLanguage))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .tracking(2.5)
                        .multilineTextAlignment(.center)
                        .lineSpacing(7)
                        .foregroundStyle(.white.opacity(0.78))

                    Capsule()
                        .fill(.white.opacity(0.15))
                        .frame(width: min(geometry.size.width * 0.52, 210), height: 3)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(LinearGradient(colors: [Color(red: 0.08, green: 0.42, blue: 1), Color(red: 0.0, green: 0.9, blue: 1)], startPoint: .leading, endPoint: .trailing))
                                .frame(width: isVisible ? min(geometry.size.width * 0.52, 210) : 8, height: 3)
                                .shadow(color: .cyan, radius: 8)
                        }
                        .padding(.top, 28)

                    Spacer(minLength: 44)
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(isVisible ? 1 : 0)
                .scaleEffect(isVisible ? 1 : 0.97)
            }
            .background(Color.black)
        }
        .ignoresSafeArea()
    }
}

#Preview {
    WelcomeView()
}
