import SwiftUI

// MARK: - Deslizar entre pestañas (vertical)

/// Lo que mueve el dedo al deslizar entre pestañas. HomeView no lo observa (si no, se repintaría
/// entera en cada fotograma): solo lo miran las vistas pequeñas que se desplazan.
final class PageSwipe: ObservableObject {
    enum Axis { case undecided, horizontal, vertical }

    /// Desplazamiento de la página con el dedo.
    @Published var offset: CGFloat = 0
    /// Lo que se ha sacado el panel de Ajustes desde el borde derecho (la página se aparta un poco).
    @Published var edge: CGFloat = 0
    var axis: Axis = .undecided
}

/// La página sigue al dedo con un toque de profundidad (como en iOS 26): se aparta, se encoge
/// muy poco y se aclara.
struct SwipeShift: ViewModifier {
    @ObservedObject var swipe: PageSwipe
    var active: Bool

    func body(content: Content) -> some View {
        let width: CGFloat = max(UIScreen.main.bounds.width, 1)
        let x: CGFloat = active ? swipe.offset : 0
        let parallax: CGFloat = -swipe.edge * 0.18
        let amount: CGFloat = min(1, abs(x) / width)
        return content
            .offset(x: x + parallax)
            .scaleEffect(1 - 0.05 * amount - 0.03 * min(1, swipe.edge / width), anchor: .center)
            .opacity(Double(1 - 0.45 * amount))
            .blur(radius: 2.5 * amount)
    }
}

/// Transición de página según hacia dónde se va (la nueva entra por ese lado).
extension AnyTransition {
    static func page(forward: Bool) -> AnyTransition {
        .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity).combined(with: .scale(scale: 0.96)),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.96))
        )
    }
}

// MARK: - Ajustes desde el borde derecho

/// Arrastrar desde el borde derecho hacia la izquierda: aparece un panel de cristal con Ajustes que
/// sigue al dedo; al soltar (pasada la mitad o con impulso) se abren los Ajustes.
struct SettingsEdgeReveal: View {
    let enabled: Bool
    @ObservedObject var swipe: PageSwipe
    let title: String
    let onOpen: () -> Void

    @State private var opening = false

    private var width: CGFloat { UIScreen.main.bounds.width }

    var body: some View {
        let pulled: CGFloat = swipe.edge
        let progress: CGFloat = min(1, pulled / (width * 0.55))
        ZStack(alignment: .trailing) {
            if pulled > 0 {
                panel(pulled: pulled, progress: progress)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
            if enabled {
                Color.clear
                    .frame(width: 20)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(edgeGesture)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .allowsHitTesting(enabled || pulled > 0)
    }

    private func panel(pulled: CGFloat, progress: CGFloat) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 34, bottomLeadingRadius: 34, style: .continuous)
        return ZStack {
            shape.fill(Color(red: 0.02, green: 0.05, blue: 0.14).opacity(0.55 + 0.35 * progress))
            Color.clear.liquidGlass(in: shape)
            shape.strokeBorder(LinearGradient(colors: [Color.cyan.opacity(0.75), Color(red: 0.55, green: 0.42, blue: 1.0).opacity(0.35)],
                                              startPoint: .top, endPoint: .bottom), lineWidth: 1)
            VStack(spacing: 12) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [Color.cyan, Color(red: 0.55, green: 0.42, blue: 1.0)], startPoint: .top, endPoint: .bottom))
                    .rotationEffect(.degrees(Double(pulled) * 0.9))
                    .shadow(color: Color.cyan.opacity(0.7), radius: 10)
                Text(title)
                    .font(AppFont.text(16, .bold))
                    .foregroundStyle(.white)
                    .opacity(Double(min(1, progress * 1.6)))
                Image(systemName: "chevron.left.2")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45 * (1 - progress)))
            }
            .scaleEffect(0.8 + 0.2 * progress)
        }
        .frame(width: max(0, pulled))
        .frame(maxHeight: .infinity)
        .shadow(color: Color.cyan.opacity(0.25 * progress), radius: 24, x: -6)
        .ignoresSafeArea()
    }

    private var edgeGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { value in
                guard !opening else { return }
                // Con goma: cuanto más se saca, más cuesta.
                let raw: CGFloat = max(0, -value.translation.width)
                swipe.edge = raw < width * 0.6 ? raw : width * 0.6 + (raw - width * 0.6) * 0.3
            }
            .onEnded { value in
                guard !opening else { return }
                let open: Bool = -value.translation.width > width * 0.33 || -value.predictedEndTranslation.width > width * 0.6
                if open {
                    opening = true
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { swipe.edge = width }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        onOpen()
                        withAnimation(.easeOut(duration: 0.32)) { swipe.edge = 0 }
                        opening = false
                    }
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { swipe.edge = 0 }
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
