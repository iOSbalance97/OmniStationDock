import SwiftUI

// MARK: - Batería y reloj del Modo Dock

struct DockStatus: View {
    var use24h: Bool
    /// Indicador de JIT entre la batería y la hora (nil = no se muestra).
    var jitActive: Bool? = nil
    var onJITTap: () -> Void = {}
    @StateObject private var battery = BatteryMonitor()

    var body: some View {
        HStack(spacing: 12) {
            if battery.level >= 0 {
                batteryView
            }
            if let jitActive {
                JITIndicatorDot(active: jitActive)
                    .onTapGesture { onJITTap() }
            }
            TimelineView(.everyMinute) { context in
                Text(Self.text(for: context.date, use24h: use24h))
                    .font(AppFont.text(18, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.92))
            }
        }
    }

    private var batteryView: some View {
        let low: Bool = battery.level <= 20 && !battery.charging
        let color: Color = low ? Color.red : (battery.charging ? Color.green : Color.white.opacity(0.85))
        return HStack(spacing: 5) {
            Text("\(battery.level)%")
                .font(AppFont.text(14, .semibold))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))
            Image(systemName: battery.symbolName)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(color)
        }
    }

    static func text(for date: Date, use24h: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = use24h ? "HH:mm" : "h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Indicador de JIT

/// Punto verde (JIT disponible) o rojo (no disponible), con un brillo suave.
struct JITIndicatorDot: View {
    var active: Bool

    var body: some View {
        let color: Color = active ? Color.green : Color.red
        return Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .shadow(color: color.opacity(0.8), radius: 4)
            .padding(6)
            .contentShape(Rectangle())
            .accessibilityLabel(active ? "JIT ON" : "JIT OFF")
    }
}

// MARK: - Carrusel del Modo Dock

/// Carrusel horizontal: la tarjeta del centro es la seleccionada (grande y con su texto),
/// las demás se ven más pequeñas a los lados. Se mueve con el mando o deslizando.
struct DockCarousel: View {
    let games: [Game]
    @Binding var selectedID: String?
    var focused: Bool
    var favorites: Set<String>
    var cardWidth: CGFloat
    /// Cambia al guardar o quitar una carátula, para repintar.
    var coverVersion: Int = 0
    var playHint: String
    var emptyText: String
    var favoriteLabel: String = ""
    var onOpen: (Game) -> Void
    /// Estrella de cada tarjeta: añade o quita de favoritos.
    var onToggleFavorite: (Game) -> Void = { _ in }
    /// Al cambiar de tarjeta deslizando con el dedo (para que suene igual que con el mando).
    var onSwipe: () -> Void = {}

    /// Tamaño de las tarjetas laterales respecto a la seleccionada.
    static let sideScale: CGFloat = 0.72
    /// Alto que ocupan el nombre y la indicación bajo la portada.
    static let textHeight: CGFloat = 46
    /// Proporción alto/ancho de la portada.
    static let coverRatio: CGFloat = 1.12

    @State private var scrollID: String?

    var body: some View {
        GeometryReader { geometry in
            if games.isEmpty {
                Text(emptyText)
                    .font(AppFont.text(14, .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                carousel(width: geometry.size.width)
            }
        }
    }

    private func carousel(width: CGFloat) -> some View {
        // Cada lateral encoge por los dos lados: se compensa la mitad para dejar un hueco limpio.
        let spacing: CGFloat = 12 - cardWidth * (1 - Self.sideScale) / 2
        let margin: CGFloat = max(0, (width - cardWidth) / 2)
        let selectedIndex: Int = games.firstIndex(where: { $0.id == selectedID }) ?? 0
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: spacing) {
                ForEach(Array(games.enumerated()), id: \.element.id) { offset, game in
                    card(game)
                        .frame(width: cardWidth)
                        // La del centro delante; a cada lado, las más cercanas tapan a las de detrás.
                        .zIndex(Double(-abs(offset - selectedIndex)))
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, margin, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrollID, anchor: .center)
        .onChange(of: scrollID) { _, id in
            // Si cambia por el dedo (no por el mando), suena la navegación.
            if let id, id != selectedID {
                selectedID = id
                onSwipe()
            }
        }
        .onChange(of: selectedID) { _, id in
            if let id, id != scrollID {
                withAnimation(.easeOut(duration: 0.2)) { scrollID = id }
            }
        }
        .onChange(of: games.map(\.id)) { _, _ in
            centerSelection()
        }
        .onChange(of: width) { _, _ in
            centerSelection()
        }
        .onAppear {
            centerSelection()
        }
    }

    /// Coloca la tarjeta seleccionada en el centro. Se repite cuando la lista ya está dibujada:
    /// la primera vez, justo al aparecer, el carrusel aún puede no tener su tamaño.
    private func centerSelection() {
        let target: String? = selectedID ?? games.first?.id
        // Primero se suelta la posición y, en el siguiente instante, se fija la nueva:
        // si se hiciera todo a la vez, SwiftUI no notaría el cambio y no movería nada.
        scrollID = nil
        DispatchQueue.main.async {
            scrollID = target
        }
    }

    private func card(_ game: Game) -> some View {
        let isSelected: Bool = game.id == selectedID
        return VStack(spacing: 7) {
            cover(game, selected: isSelected)
            Text(game.name)
                .font(AppFont.text(15, .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(playHint)
                .font(AppFont.text(10, .medium))
                .foregroundStyle(Color.cyan.opacity(0.9))
                .lineLimit(1)
                .opacity(isSelected ? 1 : 0)
        }
        .scaleEffect(isSelected ? 1 : Self.sideScale)
        .opacity(isSelected ? 1 : 0.62)
        .animation(.smooth(duration: 0.22), value: isSelected)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected { onOpen(game) } else { selectedID = game.id }
        }
    }

    private func cover(_ game: Game, selected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return ZStack {
            coverArt(game)
            coverBadges(game)
        }
        .frame(width: cardWidth, height: cardWidth * Self.coverRatio)
        .clipShape(shape)
        .glassRim(in: shape)
        .padRing(selected && focused, cornerRadius: 18)
        // Brillo solo detrás de la seleccionada: una sombra en cada tarjeta (aunque fuera
        // transparente) se calculaba en todas y daba tirones al deslizar.
        .background {
            if selected {
                shape
                    .fill(Color.cyan.opacity(0.4))
                    .blur(radius: 14)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private func coverArt(_ game: Game) -> some View {
        if let image = coverImage(game.id) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: cardWidth, height: cardWidth * Self.coverRatio)
        } else {
            LinearGradient(
                colors: [
                    game.tint.opacity(0.82),
                    Color(red: 0.015, green: 0.055, blue: 0.14).opacity(0.95),
                    Color(red: 0.003, green: 0.012, blue: 0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color.cyan.opacity(0.18), Color.clear],
                center: .topTrailing,
                startRadius: 2,
                endRadius: cardWidth * 0.7
            )
            Image(systemName: game.symbol)
                .font(.system(size: cardWidth * 0.34, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
        }
    }

    private func coverImage(_ id: String) -> UIImage? {
        _ = coverVersion
        return CoverStore.shared.image(for: id)
    }

    private func favoriteButton(_ game: Game) -> some View {
        let isFavorite: Bool = favorites.contains(game.id)
        let side: CGFloat = 30
        return Button {
            onToggleFavorite(game)
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isFavorite ? Color.yellow : Color.white.opacity(0.85))
                .frame(width: side, height: side)
                .background(Color.black.opacity(0.38), in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(ControllerFocusableButtonStyle())
        .accessibilityLabel(favoriteLabel)
    }

    private func coverBadges(_ game: Game) -> some View {
        VStack {
            HStack {
                Text(game.platform)
                    .font(AppFont.text(9, .bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.38), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5))
                Spacer()
                favoriteButton(game)
            }
            Spacer()
        }
        .padding(8)
    }
}
