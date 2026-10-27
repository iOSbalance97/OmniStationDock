import SwiftUI

// MARK: - Deslizar entre pestañas (vertical)

/// Lo que mueve el dedo al deslizar entre pestañas. HomeView no lo observa (si no, se repintaría
/// entera en cada fotograma): solo lo miran las vistas pequeñas que se desplazan.
final class PageSwipe: ObservableObject {
    enum Axis { case undecided, horizontal, vertical }

    /// Desplazamiento de la página con el dedo (ya amortiguado).
    @Published var offset: CGFloat = 0
    /// Lo que se ha sacado el panel de Ajustes desde el borde derecho.
    @Published var edge: CGFloat = 0
    var axis: Axis = .undecided
    /// Cuándo terminó el último deslizamiento: los toques de justo después no cuentan (al soltar el
    /// dedo encima de una tarjeta se abría sin querer).
    var lastHorizontal: Date = .distantPast

    var justSwiped: Bool { Date().timeIntervalSince(lastHorizontal) < 0.4 }
}

/// La página sigue al dedo (solo se desplaza y se aclara un poco: nada de desenfoques ni escalas,
/// que en una pantalla entera con cristal se notaban y calentaban).
struct SwipeShift: ViewModifier {
    @ObservedObject var swipe: PageSwipe
    var active: Bool

    func body(content: Content) -> some View {
        let width: CGFloat = max(UIScreen.main.bounds.width, 1)
        let x: CGFloat = active ? swipe.offset : 0
        return content
            .offset(x: x)
            .opacity(Double(1 - 0.35 * min(1, abs(x) / (width * 0.5))))
    }
}

/// Transición de página según hacia dónde se va (la nueva entra por ese lado).
extension AnyTransition {
    static func page(forward: Bool) -> AnyTransition {
        .asymmetric(
            insertion: .offset(x: forward ? 90 : -90).combined(with: .opacity),
            removal: .offset(x: forward ? -90 : 90).combined(with: .opacity)
        )
    }
}

// MARK: - Ajustes desde el borde derecho

/// Arrastrar desde el borde derecho hacia la izquierda: un panel de cristal con Ajustes entra con el
/// dedo; al soltar (pasado un tercio o con impulso) tapa la pantalla, se abren los Ajustes debajo y
/// el panel se desvanece.
struct SettingsEdgeReveal: View {
    let enabled: Bool
    @ObservedObject var swipe: PageSwipe
    let title: String
    let onOpen: () -> Void

    @State private var opening = false
    @State private var fade: Double = 1
    /// Si el gesto se corta (otra ventana, cambio de pestaña), vuelve a su sitio solo.
    @GestureState private var dragging = false

    private var width: CGFloat { UIScreen.main.bounds.width }

    var body: some View {
        let pulled: CGFloat = swipe.edge
        let progress: CGFloat = min(1, pulled / (width * 0.5))
        ZStack(alignment: .trailing) {
            if pulled > 0 {
                // Tamaño fijo y solo se desplaza (cambiar su ancho en cada fotograma costaba mucho).
                panel(pulled: pulled, progress: progress)
                    .offset(x: width - pulled)
                    .opacity(fade)
                    .allowsHitTesting(false)
            }
            if enabled {
                Color.clear
                    .frame(width: 20)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(edgeGesture)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .allowsHitTesting(enabled || pulled > 0)
        .onChange(of: dragging) { _, active in
            if !active && !opening && swipe.edge > 0 {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { swipe.edge = 0 }
            }
        }
    }

    private func panel(pulled: CGFloat, progress: CGFloat) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 34, bottomLeadingRadius: 34, style: .continuous)
        return ZStack(alignment: .leading) {
            shape.fill(Color(red: 0.02, green: 0.05, blue: 0.14).opacity(0.92))
            shape.strokeBorder(LinearGradient(colors: [Color.cyan.opacity(0.75), Color(red: 0.55, green: 0.42, blue: 1.0).opacity(0.35)],
                                              startPoint: .top, endPoint: .bottom), lineWidth: 1)
            VStack(spacing: 12) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [Color.cyan, Color(red: 0.55, green: 0.42, blue: 1.0)], startPoint: .top, endPoint: .bottom))
                    .rotationEffect(.degrees(Double(pulled) * 0.9))
                Text(title)
                    .font(AppFont.text(16, .bold))
                    .foregroundStyle(.white)
                    .opacity(Double(min(1, progress * 1.6)))
            }
            .frame(width: max(90, min(pulled, width * 0.5)))
            .scaleEffect(0.85 + 0.15 * progress)
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .ignoresSafeArea()
    }

    private var edgeGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .updating($dragging) { _, state, _ in state = true }
            .onChanged { value in
                guard !opening else { return }
                // Con goma: pasado el 60 % cuesta más.
                let raw: CGFloat = max(0, -value.translation.width)
                swipe.edge = raw < width * 0.6 ? raw : width * 0.6 + (raw - width * 0.6) * 0.3
            }
            .onEnded { value in
                guard !opening else { return }
                swipe.lastHorizontal = Date()
                let open: Bool = -value.translation.width > width * 0.33 || -value.predictedEndTranslation.width > width * 0.6
                guard open else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { swipe.edge = 0 }
                    return
                }
                opening = true
                withAnimation(.spring(response: 0.28, dampingFraction: 0.92)) { swipe.edge = width }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                    // Debajo del panel (ya tapa todo) se cambia a Ajustes sin animar; luego se desvanece.
                    onOpen()
                    withAnimation(.easeOut(duration: 0.3)) { fade = 0 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                        swipe.edge = 0
                        fade = 1
                        opening = false
                    }
                }
            }
    }
}

// MARK: - Sorpresa (4 toques en el título)

struct ThanksEasterEgg: View {
    let lang: String
    let onClose: () -> Void

    @State private var shown = false

    private func tr(_ key: String) -> String { L10n.tr(key, lang) }

    var body: some View {
        ZStack {
            Color.black.opacity(shown ? 0.7 : 0)
                .ignoresSafeArea()
            StarField()
                .ignoresSafeArea()
                .opacity(shown ? 1 : 0)
            card
                .scaleEffect(shown ? 1 : 0.82)
                .opacity(shown ? 1 : 0)
                .rotation3DEffect(.degrees(shown ? 0 : 12), axis: (x: 1, y: 0, z: 0))
        }
        .contentShape(Rectangle())
        .onTapGesture { close() }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.72)) { shown = true }
        }
    }

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
        return VStack(spacing: 16) {
            ZStack {
                NeonRing()
                    .frame(width: 112, height: 112)
                Image(systemName: "heart.fill")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [Color(red: 1.0, green: 0.35, blue: 0.55), Color(red: 0.55, green: 0.42, blue: 1.0)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: Color(red: 1.0, green: 0.35, blue: 0.55).opacity(0.7), radius: 12)
                    .symbolEffect(.pulse, options: .repeating)
            }
            Text(tr("¡Gracias!"))
                .font(AppFont.text(26, .bold))
                .foregroundStyle(.white)
            Text(tr("Gracias por la confianza puesta en la aplicación y en el equipo de desarrollo."))
                .font(AppFont.text(14))
                .foregroundStyle(.white.opacity(0.78))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("TEAM LRCT")
                .font(AppFont.brand(30, .bold))
                .tracking(4)
                .foregroundStyle(LinearGradient(colors: [Color.cyan, Color(red: 0.30, green: 0.60, blue: 1.0), Color(red: 0.55, green: 0.42, blue: 1.0)], startPoint: .leading, endPoint: .trailing))
                .shadow(color: Color.cyan.opacity(0.8), radius: 14)
                .padding(.top, 4)
            Rectangle()
                .fill(LinearGradient(colors: [.clear, Color.cyan.opacity(0.6), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
                .padding(.horizontal, 30)
            Text("Thanks Claude.")
                .font(AppFont.text(13, .semibold))
                .italic()
                .foregroundStyle(.white.opacity(0.6))
            Text(tr("Toca para cerrar"))
                .font(AppFont.text(10))
                .foregroundStyle(.white.opacity(0.35))
                .padding(.top, 2)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 30)
        .frame(maxWidth: 340)
        .background {
            ZStack {
                shape.fill(Color(red: 0.02, green: 0.05, blue: 0.14).opacity(0.86))
                Color.clear.liquidGlass(in: shape)
                shape.strokeBorder(LinearGradient(colors: [Color.cyan.opacity(0.85), Color(red: 0.55, green: 0.42, blue: 1.0).opacity(0.5), Color.cyan.opacity(0.2)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2)
            }
        }
        .shadow(color: Color.cyan.opacity(0.35), radius: 30)
        .padding(24)
    }

    private func close() {
        withAnimation(.easeIn(duration: 0.22)) { shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { onClose() }
    }
}

/// Anillo de neón que gira despacio.
private struct NeonRing: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let angle: Double = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 6) / 6 * 360
            ZStack {
                Circle()
                    .stroke(AngularGradient(colors: [Color.cyan, Color(red: 0.55, green: 0.42, blue: 1.0), Color(red: 1.0, green: 0.35, blue: 0.55), Color.cyan],
                                            center: .center), lineWidth: 3)
                    .rotationEffect(.degrees(angle))
                    .blur(radius: 0.5)
                Circle()
                    .stroke(Color.cyan.opacity(0.35), lineWidth: 10)
                    .blur(radius: 12)
            }
        }
    }
}

/// Estrellas que suben despacio y titilan (el espacio de nuestros primeros iconos).
private struct StarField: View {
    private struct Star {
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let speed: CGFloat
        let phase: Double
    }

    private static let stars: [Star] = (0..<70).map { index in
        var generator = SeededRandom(seed: UInt64(index + 1) * 2654435761)
        return Star(x: generator.next(), y: generator.next(), size: 1 + generator.next() * 2.4,
                    speed: 0.01 + generator.next() * 0.03, phase: Double(generator.next()) * 6.28)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            Canvas { canvas, size in
                let time: Double = context.date.timeIntervalSinceReferenceDate
                for star in Self.stars {
                    let y: CGFloat = (star.y - CGFloat(time) * star.speed).truncatingRemainder(dividingBy: 1)
                    let point = CGPoint(x: star.x * size.width, y: (y < 0 ? y + 1 : y) * size.height)
                    let twinkle: Double = 0.35 + 0.65 * (0.5 + 0.5 * sin(time * 2 + star.phase))
                    let rect = CGRect(x: point.x, y: point.y, width: star.size, height: star.size)
                    canvas.fill(Path(ellipseIn: rect), with: .color(Color(red: 0.6, green: 0.85, blue: 1.0).opacity(twinkle)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Números al azar repetibles (las estrellas siempre en el mismo sitio).
private struct SeededRandom {
    var state: UInt64

    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }

    mutating func next() -> CGFloat {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return CGFloat(state % 10_000) / 10_000
    }
}
