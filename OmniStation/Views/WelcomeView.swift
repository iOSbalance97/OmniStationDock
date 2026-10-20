import SwiftUI

/// Bienvenida: fondo animado (Resources/Background/WelcomeBackground.mp4), el planeta cae desde
/// arriba y rebota dos veces, «OMNISTATION» aparece de izquierda a derecha como grabado con un
/// láser y «DOCK» sale de un destello. Después, el lema y la barra de carga.
///
/// Toda la animación sale del tiempo transcurrido (TimelineView a la frecuencia de la pantalla):
/// cada fotograma se calcula con curvas continuas, así no hay saltos entre fases.
struct WelcomeView: View {
    @AppStorage("appLanguage") private var appLanguage = "system"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showHome = false
    @State private var start: Date?

    private static let welcomeVideo: URL? = BundleFiles.find(["welcomebackground"], extensions: ["mp4", "mov", "m4v"])
    private static let blue = Color(red: 0.08, green: 0.42, blue: 1)
    private static let cyan = Color(red: 0.0, green: 0.88, blue: 1)

    // MARK: Guion (segundos)

    private enum Script {
        static let fallStart: Double = 0.25
        static let fallEnd: Double = 1.0
        static let bounce1: Double = 0.44     // duración del primer rebote
        static let bounce2: Double = 0.26     // y del segundo
        static var landed: Double { fallEnd + bounce1 + bounce2 }
        static var laserStart: Double { landed + 0.2 }
        static let laserDuration: Double = 1.0
        static var flashStart: Double { laserStart + laserDuration + 0.1 }
        static var sloganStart: Double { flashStart + 0.7 }
        static var progressEnd: Double { sloganStart + 1.1 }
        /// Al terminar todo, un segundo más antes de entrar.
        static var finish: Double { progressEnd + 1.0 }
    }

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
            guard !showHome, start == nil else { return }
            start = Date()
            let total: Double = reduceMotion ? 2.2 : Script.finish
            try? await Task.sleep(nanoseconds: UInt64(total * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.5)) { showHome = true }
        }
    }

    // MARK: Curvas

    private static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }

    private static func progress(_ t: Double, from: Double, duration: Double) -> Double {
        clamp((t - from) / duration)
    }

    /// Suave al empezar y al acabar.
    private static func smooth(_ x: Double) -> Double { x * x * (3 - 2 * x) }

    private static func easeOutCubic(_ x: Double) -> Double { 1 - pow(1 - x, 3) }

    /// Altura del planeta (en alturas de pantalla, negativa hacia arriba) como una pelota:
    /// caída con gravedad, dos rebotes parabólicos cada vez más bajos y reposo.
    private static func planetOffset(_ t: Double) -> Double {
        if t < Script.fallStart { return -1.15 }
        if t < Script.fallEnd {
            let p: Double = (t - Script.fallStart) / (Script.fallEnd - Script.fallStart)
            return -1.15 * (1 - p * p)
        }
        let b1: Double = t - Script.fallEnd
        if b1 < Script.bounce1 {
            let s: Double = b1 / Script.bounce1
            return -0.07 * 4 * s * (1 - s)
        }
        let b2: Double = b1 - Script.bounce1
        if b2 < Script.bounce2 {
            let s: Double = b2 / Script.bounce2
            return -0.022 * 4 * s * (1 - s)
        }
        return 0
    }

    /// Aplastamiento al tocar el suelo (se recupera con un pequeño muelle).
    private static func squash(_ t: Double) -> Double {
        let impacts: [(Double, Double)] = [(Script.fallEnd, 0.085),
                                           (Script.fallEnd + Script.bounce1, 0.04),
                                           (Script.landed, 0.016)]
        var total: Double = 0
        for (time, amount) in impacts where t >= time {
            let dt: Double = t - time
            total += amount * exp(-dt / 0.07) * cos(dt * 34)
        }
        return total
    }

    private struct Frame {
        var planetY: Double
        var squash: Double
        var laser: Double
        var beam: Double
        var dock: Double
        var flash: Double
        var slogan: Double
        var bar: Double
    }

    private func animationFrame(at t: Double) -> Frame {
        if reduceMotion {
            let p: Double = Self.smooth(Self.progress(t, from: 0, duration: 0.6))
            return Frame(planetY: 0, squash: 0, laser: p, beam: 0, dock: p, flash: 0, slogan: p,
                         bar: Self.smooth(Self.progress(t, from: 0.3, duration: 1.2)))
        }
        let laser: Double = Self.smooth(Self.progress(t, from: Script.laserStart, duration: Script.laserDuration))
        let beamIn: Double = Self.progress(t, from: Script.laserStart - 0.1, duration: 0.1)
        let beamOut: Double = 1 - Self.progress(t, from: Script.laserStart + Script.laserDuration, duration: 0.25)
        // Destello: sube en 0,25 s y se apaga despacio (algo más de un segundo).
        let rise: Double = Self.smooth(Self.progress(t, from: Script.flashStart, duration: 0.25))
        let decay: Double = t > Script.flashStart + 0.25 ? exp(-(t - Script.flashStart - 0.25) / 0.45) : 1
        let flash: Double = t < Script.flashStart ? 0 : rise * decay
        let dock: Double = Self.easeOutCubic(Self.progress(t, from: Script.flashStart + 0.08, duration: 0.7))
        return Frame(
            planetY: Self.planetOffset(t),
            squash: Self.squash(t),
            laser: laser,
            beam: min(beamIn, beamOut),
            dock: dock,
            flash: flash,
            slogan: Self.smooth(Self.progress(t, from: Script.sloganStart, duration: 0.6)),
            bar: Self.smooth(Self.progress(t, from: Script.sloganStart, duration: Script.progressEnd - Script.sloganStart))
        )
    }

    // MARK: Pantalla

    private var welcomeScreen: some View {
        GeometryReader { geometry in
            let width: CGFloat = geometry.size.width
            let height: CGFloat = geometry.size.height
            ZStack {
                welcomeBackground(geometry.size)
                TimelineView(.animation) { context in
                    let t: Double = start.map { context.date.timeIntervalSince($0) } ?? 0
                    let f: Frame = animationFrame(at: t)
                    welcomeContent(f, width: width, height: height)
                }
            }
            .background(Color.black)
        }
        .ignoresSafeArea()
    }

    private func welcomeContent(_ f: Frame, width: CGFloat, height: CGFloat) -> some View {
        // Un poco más grande que el de antes; el PNG va recortado al planeta y su anillo.
        let planetWidth: CGFloat = min(width * 0.92, height * 0.62, 460)
        return ZStack {
            // Planeta y nombre, juntos y centrados en la pantalla.
            VStack(spacing: 4) {
                Image("WelcomePlanet")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: planetWidth)
                    .scaleEffect(x: 1 + f.squash, y: 1 - f.squash, anchor: .bottom)
                    .shadow(color: Color.cyan.opacity(0.34), radius: 22)
                    .shadow(color: Color.blue.opacity(0.26), radius: 38)
                    .offset(y: f.planetY * height)
                    .accessibilityLabel("Planeta de OmniStation Dock")
                title(f, width: width)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(y: -height * 0.03)

            // Destello de «DOCK»: un poco de luz en toda la pantalla.
            Color.white
                .opacity(0.10 * f.flash)
                .allowsHitTesting(false)

            // Lema y barra, abajo.
            VStack(spacing: 0) {
                Spacer()
                Text(L10n.tr("TU MUNDO, TUS REGLAS.", appLanguage))
                    .font(AppFont.text(13, .medium))
                    .tracking(3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.82))
                    .opacity(f.slogan)
                    .offset(y: (1 - f.slogan) * 8)
                Capsule()
                    .fill(.white.opacity(0.15))
                    .frame(width: min(width * 0.52, 210), height: 3)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(LinearGradient(colors: [Self.blue, Self.cyan], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(8, min(width * 0.52, 210) * f.bar), height: 3)
                            .shadow(color: .cyan, radius: 8)
                    }
                    .opacity(f.slogan)
                    .padding(.top, 24)
                Spacer().frame(height: max(56, height * 0.09))
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
        }
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

    private func title(_ f: Frame, width: CGFloat) -> some View {
        let brandSize: CGFloat = min(width * 0.075, 31)
        let dockSize: CGFloat = min(width * 0.09, 38)
        return VStack(spacing: 3) {
            Text("OMNISTATION")
                .font(AppFont.brand(brandSize, .semibold))
                .tracking(width < 400 ? 3.5 : 5.5)
                .foregroundStyle(.white)
                .minimumScaleFactor(0.65)
                .lineLimit(1)
                // Se descubre de izquierda a derecha…
                .mask(alignment: .leading) {
                    GeometryReader { proxy in
                        Rectangle()
                            .frame(width: proxy.size.width * f.laser)
                    }
                }
                // …con el haz del láser y su chispa en el borde.
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        ZStack {
                            Capsule()
                                .fill(Color.white)
                                .frame(width: 2.5, height: proxy.size.height * 1.6)
                            Circle()
                                .fill(RadialGradient(colors: [Color.white, Self.cyan.opacity(0.6), Color.clear],
                                                     center: .center, startRadius: 0, endRadius: 14))
                                .frame(width: 28, height: 28)
                        }
                        .shadow(color: Self.cyan, radius: 6)
                        .shadow(color: Self.cyan, radius: 14)
                        .position(x: proxy.size.width * f.laser, y: proxy.size.height * 0.5)
                        .opacity(f.beam)
                    }
                    .allowsHitTesting(false)
                }

            ZStack {
                // Luz del destello: halo grande, núcleo blanco y una raya horizontal como de lente.
                Ellipse()
                    .fill(RadialGradient(colors: [Self.cyan.opacity(0.55), Self.blue.opacity(0.25), Color.clear],
                                         center: .center, startRadius: 4, endRadius: 190))
                    .frame(width: 380, height: 170)
                    .scaleEffect(0.7 + f.flash * 0.6)
                    .opacity(f.flash)
                    .blendMode(.screen)
                Ellipse()
                    .fill(RadialGradient(colors: [Color.white, Color.white.opacity(0.5), Color.clear],
                                         center: .center, startRadius: 1, endRadius: 70))
                    .frame(width: 190, height: 70)
                    .opacity(f.flash)
                    .blendMode(.screen)
                Capsule()
                    .fill(LinearGradient(colors: [Color.clear, Self.cyan.opacity(0.8), Color.white, Self.cyan.opacity(0.8), Color.clear],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: width * (0.5 + 0.5 * f.flash), height: 2.5)
                    .blur(radius: 0.6)
                    .opacity(f.flash)
                    .blendMode(.screen)
                Text("DOCK")
                    .font(AppFont.brand(dockSize, .heavy))
                    .tracking(width < 400 ? 7 : 10)
                    .foregroundStyle(LinearGradient(colors: [Self.blue, Self.cyan], startPoint: .leading, endPoint: .trailing))
                    .overlay {
                        // Sale blanco por la luz y se templa hasta su color.
                        Text("DOCK")
                            .font(AppFont.brand(dockSize, .heavy))
                            .tracking(width < 400 ? 7 : 10)
                            .foregroundStyle(Color.white)
                            .opacity(min(1, f.flash * 1.2))
                    }
                    .shadow(color: Self.cyan.opacity(0.25 + 0.7 * f.flash), radius: 6 + 14 * f.flash)
                    .scaleEffect(1.25 - 0.25 * f.dock)
                    .opacity(f.dock)
            }
        }
    }
}

#Preview {
    WelcomeView()
}
