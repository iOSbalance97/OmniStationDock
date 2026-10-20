import SwiftUI

/// Bienvenida: fondo animado (Resources/Background/WelcomeBackground.mp4), el planeta cae desde
/// arriba y rebota dos veces, «OMNISTATION» aparece de izquierda a derecha como grabado con un
/// láser y «DOCK» sale de un destello. Después, el lema y la barra de carga.
struct WelcomeView: View {
    @AppStorage("appLanguage") private var appLanguage = "system"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showHome = false

    // Animación
    @State private var started = false
    /// Desplazamiento vertical del planeta en múltiplos de la altura de la pantalla (−1: fuera, arriba).
    @State private var planetDrop: CGFloat = -1
    @State private var planetBounce: CGFloat = 0
    @State private var squash = false
    @State private var laser: CGFloat = 0
    @State private var laserVisible = false
    @State private var dockShown = false
    @State private var flash: Double = 0
    @State private var sloganShown = false
    @State private var progress: CGFloat = 0

    private static let welcomeVideo: URL? = BundleFiles.find(["welcomebackground"], extensions: ["mp4", "mov", "m4v"])
    private static let blue = Color(red: 0.08, green: 0.42, blue: 1)
    private static let cyan = Color(red: 0.0, green: 0.88, blue: 1)

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
            guard !showHome, !started else { return }
            started = true
            await play()
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.45)) { showHome = true }
        }
    }

    // MARK: Secuencia

    private func wait(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func impact() async {
        withAnimation(.easeOut(duration: 0.07)) { squash = true }
        await wait(0.07)
        withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) { squash = false }
    }

    private func play() async {
        if reduceMotion {
            planetDrop = 0
            withAnimation(.easeOut(duration: 0.5)) {
                laser = 1
                dockShown = true
                sloganShown = true
            }
            withAnimation(.easeInOut(duration: 1.2)) { progress = 1 }
            await wait(1.6)
            return
        }
        await wait(0.25)
        // 1) Cae desde arriba…
        withAnimation(.easeIn(duration: 0.62)) { planetDrop = 0 }
        await wait(0.62)
        await impact()
        // …rebota dos veces (cada vez menos) y se para.
        withAnimation(.easeOut(duration: 0.24)) { planetBounce = -0.075 }
        await wait(0.24)
        withAnimation(.easeIn(duration: 0.24)) { planetBounce = 0 }
        await wait(0.24)
        await impact()
        withAnimation(.easeOut(duration: 0.14)) { planetBounce = -0.025 }
        await wait(0.14)
        withAnimation(.easeIn(duration: 0.14)) { planetBounce = 0 }
        await wait(0.2)
        // 2) El nombre, de izquierda a derecha, como si lo grabase un láser.
        laserVisible = true
        withAnimation(.linear(duration: 0.85)) { laser = 1 }
        await wait(0.85)
        withAnimation(.easeOut(duration: 0.2)) { laserVisible = false }
        // 3) «DOCK» aparece de un destello.
        withAnimation(.easeIn(duration: 0.06)) { flash = 1 }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.62)) { dockShown = true }
        await wait(0.08)
        withAnimation(.easeOut(duration: 0.7)) { flash = 0 }
        await wait(0.4)
        // 4) Lema y barra de carga.
        withAnimation(.easeOut(duration: 0.5)) { sloganShown = true }
        withAnimation(.easeInOut(duration: 1.0)) { progress = 1 }
        await wait(1.2)
    }

    // MARK: Pantalla

    private var welcomeScreen: some View {
        GeometryReader { geometry in
            let width: CGFloat = geometry.size.width
            let height: CGFloat = geometry.size.height
            ZStack {
                welcomeBackground(geometry.size)

                VStack(spacing: 0) {
                    Spacer(minLength: 24)

                    // Un poco más grande que el de antes (0,80 del ancho y 380 como mucho).
                    let planetSize: CGFloat = min(min(width * 0.92, height * 0.46), 440)
                    Image("WelcomePlanet")
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: planetSize, height: planetSize)
                        .scaleEffect(x: squash ? 1.07 : 1, y: squash ? 0.9 : 1, anchor: .bottom)
                        .shadow(color: Color.cyan.opacity(0.34), radius: 22)
                        .shadow(color: Color.blue.opacity(0.26), radius: 38)
                        .offset(y: (planetDrop + planetBounce) * height)
                        .accessibilityLabel("Planeta de OmniStation Dock")

                    title(width: width)
                        .padding(.top, 18)

                    Spacer()

                    Text(L10n.tr("TU MUNDO, TUS REGLAS.", appLanguage))
                        .font(AppFont.text(13, .medium))
                        .tracking(3)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.82))
                        .opacity(sloganShown ? 1 : 0)
                        .offset(y: sloganShown ? 0 : 8)

                    Capsule()
                        .fill(.white.opacity(0.15))
                        .frame(width: min(width * 0.52, 210), height: 3)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(LinearGradient(colors: [Self.blue, Self.cyan], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(8, min(width * 0.52, 210) * progress), height: 3)
                                .shadow(color: .cyan, radius: 8)
                        }
                        .opacity(sloganShown ? 1 : 0)
                        .padding(.top, 26)

                    Spacer(minLength: 44)
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.black)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func welcomeBackground(_ size: CGSize) -> some View {
        ZStack {
            Image("SpaceBackground")
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
            if let video = Self.welcomeVideo {
                LoopingVideoBackground(url: video)
                    .frame(width: size.width, height: size.height)
                    .clipped()
            }
            LinearGradient(
                colors: [Color.black.opacity(0.15), Color.black.opacity(0.05), Color.black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    // MARK: Nombre

    private func title(width: CGFloat) -> some View {
        VStack(spacing: 3) {
            Text("OMNISTATION")
                .font(AppFont.brand(min(width * 0.075, 31), .semibold))
                .tracking(width < 400 ? 3.5 : 5.5)
                .foregroundStyle(.white)
                .minimumScaleFactor(0.65)
                .lineLimit(1)
                // Se descubre de izquierda a derecha…
                .mask(alignment: .leading) {
                    GeometryReader { proxy in
                        Rectangle()
                            .frame(width: proxy.size.width * laser)
                    }
                }
                // …con el haz del láser en el borde.
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(Color.white)
                            .frame(width: 2.5, height: proxy.size.height * 1.5)
                            .shadow(color: Self.cyan, radius: 6)
                            .shadow(color: Self.cyan, radius: 14)
                            .offset(x: proxy.size.width * laser - 1.25, y: -proxy.size.height * 0.25)
                            .opacity(laserVisible ? 1 : 0)
                    }
                    .allowsHitTesting(false)
                }

            ZStack {
                // Destello detrás de «DOCK».
                Ellipse()
                    .fill(RadialGradient(colors: [Color.white, Self.cyan.opacity(0.7), Color.clear],
                                         center: .center, startRadius: 2, endRadius: 120))
                    .frame(width: 240, height: 90)
                    .scaleEffect(0.6 + flash * 0.8)
                    .opacity(flash)
                    .blendMode(.screen)
                Text("DOCK")
                    .font(AppFont.brand(min(width * 0.09, 38), .heavy))
                    .tracking(width < 400 ? 7 : 10)
                    .foregroundStyle(LinearGradient(colors: [Self.blue, Self.cyan], startPoint: .leading, endPoint: .trailing))
                    .overlay {
                        // Al salir, «DOCK» brilla en blanco y se apaga hasta su color.
                        Text("DOCK")
                            .font(AppFont.brand(min(width * 0.09, 38), .heavy))
                            .tracking(width < 400 ? 7 : 10)
                            .foregroundStyle(Color.white)
                            .opacity(flash)
                    }
                    .shadow(color: Self.cyan.opacity(0.6 * flash + 0.25), radius: 12)
                    .scaleEffect(dockShown ? 1 : 1.35)
                    .opacity(dockShown ? 1 : 0)
            }
        }
    }
}

#Preview {
    WelcomeView()
}
