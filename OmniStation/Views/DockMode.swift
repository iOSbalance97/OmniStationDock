import SwiftUI

// MARK: - Batería y reloj del Modo Dock

struct DockStatus: View {
    var use24h: Bool
    @StateObject private var battery = BatteryMonitor()

    var body: some View {
        HStack(spacing: 12) {
            if battery.level >= 0 {
                batteryView
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

// MARK: - Carrusel del Modo Dock

/// Carrusel horizontal: la tarjeta del centro es la seleccionada (grande y con su texto),
/// las demás se ven más pequeñas a los lados. Se mueve con el mando o deslizando.
struct DockCarousel: View {
    let games: [Game]
    @Binding var selectedID: String?
    var focused: Bool
    var favorites: Set<String>
    var cardWidth: CGFloat
    var playHint: String
    var emptyText: String
    var onOpen: (Game) -> Void

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
        // Las laterales encogen: se compensa el hueco para que queden juntas.
        let spacing: CGFloat = 12 - cardWidth * (1 - Self.sideScale)
        let margin: CGFloat = max(0, (width - cardWidth) / 2)
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: spacing) {
                ForEach(games) { game in
                    card(game)
                        .frame(width: cardWidth)
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, margin, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrollID, anchor: .center)
        .onChange(of: scrollID) { _, id in
            if let id, id != selectedID { selectedID = id }
        }
        .onChange(of: selectedID) { _, id in
            if let id, id != scrollID {
                withAnimation(.easeInOut(duration: 0.28)) { scrollID = id }
            }
        }
        .onChange(of: games.map(\.id)) { _, _ in
            scrollID = selectedID ?? games.first?.id
        }
        .onAppear {
            scrollID = selectedID ?? games.first?.id
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
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: selectedID)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected { onOpen(game) } else { selectedID = game.id }
        }
    }

    private func cover(_ game: Game, selected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return ZStack {
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
            coverBadges(game)
        }
        .frame(width: cardWidth, height: cardWidth * Self.coverRatio)
        .clipShape(shape)
        .glassRim(in: shape)
        .padRing(selected && focused, cornerRadius: 18)
        .shadow(color: selected ? Color.cyan.opacity(0.45) : Color.clear, radius: 14)
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
                if favorites.contains(game.id) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.yellow)
                }
            }
            Spacer()
        }
        .padding(8)
    }
}
