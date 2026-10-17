import SwiftUI

// MARK: - Reloj del Modo Dock

struct DockClock: View {
    var use24h: Bool

    var body: some View {
        TimelineView(.everyMinute) { context in
            Text(Self.text(for: context.date, use24h: use24h))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.92))
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

/// Carrusel horizontal: la tarjeta del centro es la seleccionada (más grande y con su texto),
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

    @State private var scrollID: String?

    var body: some View {
        GeometryReader { geometry in
            if games.isEmpty {
                Text(emptyText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10 - cardWidth * 0.1) {
                        ForEach(games) { game in
                            card(game)
                                .frame(width: cardWidth)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, max(0, (geometry.size.width - cardWidth) / 2), for: .scrollContent)
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
        }
    }

    private func card(_ game: Game) -> some View {
        let isSelected = game.id == selectedID
        return VStack(spacing: 7) {
            cover(game, selected: isSelected)
            Text(game.name)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(playHint)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.cyan.opacity(0.9))
                .lineLimit(1)
                .opacity(isSelected ? 1 : 0)
        }
        .scaleEffect(isSelected ? 1 : 0.8)
        .opacity(isSelected ? 1 : 0.72)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: selectedID)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected { onOpen(game) } else { selectedID = game.id }
        }
    }

    private func cover(_ game: Game, selected: Bool) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    game.tint.opacity(0.82),
                    Color(red: 0.015, green: 0.055, blue: 0.14).opacity(0.95),
                    Color(red: 0.003, green: 0.012, blue: 0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.cyan.opacity(0.14))
                .frame(width: cardWidth * 0.6, height: cardWidth * 0.6)
                .blur(radius: 3)
                .offset(x: cardWidth * 0.18, y: -cardWidth * 0.2)
            Image(systemName: game.symbol)
                .font(.system(size: cardWidth * 0.34, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .shadow(color: .black.opacity(0.3), radius: 8)
            VStack {
                HStack {
                    Text(game.platform)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
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
        .frame(width: cardWidth, height: cardWidth * 1.12)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .glassRim(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padRing(selected && focused, cornerRadius: 18)
        .shadow(color: selected ? Color.cyan.opacity(0.45) : Color.clear, radius: 14)
    }
}
