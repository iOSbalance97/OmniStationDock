import SwiftUI

private enum DockSection: String, CaseIterable {
    case inicio = "Inicio"
    case busqueda = "Búsqueda"
    case ajustes = "Ajustes"

    var symbol: String {
        switch self {
        case .inicio: return "house.fill"
        case .busqueda: return "magnifyingglass"
        case .ajustes: return "gearshape.fill"
        }
    }
}

struct HomeView: View {
    @State private var searchText = ""
    @State private var selectedPlatform = "Todos"
    @State private var selectedSection: DockSection = .inicio

    private let platforms: [(name: String, symbol: String)] = [
        ("Todos", "square.grid.2x2.fill"),
        ("PS2", "gamecontroller.fill"),
        ("PSP", "gamecontroller"),
        ("GameCube", "cube.fill"),
        ("Wii", "gamecontroller"),
        ("Switch", "rectangle.on.rectangle"),
        ("3DS", "square.3.layers.3d"),
        ("NDS", "rectangle.portrait"),
        ("GBA", "gameboy")
    ]

    private let games: [(name: String, platform: String, symbol: String, tint: Color)] = [
        ("God of War", "PS2", "flame.fill", Color(red: 0.05, green: 0.42, blue: 1.0)),
        ("Silent Hill 2", "PS2", "moon.fill", Color(red: 0.10, green: 0.30, blue: 0.78)),
        ("Resident Evil 4", "GameCube", "eye.fill", Color(red: 0.06, green: 0.58, blue: 0.95)),
        ("Pokémon Esmeralda", "GBA", "leaf.fill", Color(red: 0.00, green: 0.72, blue: 1.0)),
        ("Mario Kart DS", "NDS", "flag.checkered", Color(red: 0.10, green: 0.46, blue: 1.0)),
        ("Pokémon Rojo Fuego", "GBA", "bolt.fill", Color(red: 0.16, green: 0.82, blue: 1.0))
    ]

    private var filteredGames: [(name: String, platform: String, symbol: String, tint: Color)] {
        games.filter {
            (selectedPlatform == "Todos" || $0.platform == selectedPlatform) &&
            (searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText))
        }
    }

    private var isLandscape: Bool {
        // GeometryReader below provides the actual layout decision.
        false
    }

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            ZStack {
                background
                VStack(spacing: 0) {
                    topBar(compact: landscape)
                    if selectedSection == .inicio {
                        homeContent(landscape: landscape)
                    } else if selectedSection == .busqueda {
                        searchContent(landscape: landscape)
                    } else {
                        settingsContent(landscape: landscape)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .preferredColorScheme(.dark)
        }
    }

    private var background: some View {
        GeometryReader { geometry in
            ZStack {
                Image("SpaceBackground")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                // Keep the nebula visible while protecting text contrast.
                LinearGradient(
                    colors: [
                        Color(red: 0.005, green: 0.018, blue: 0.055).opacity(0.22),
                        Color(red: 0.002, green: 0.012, blue: 0.035).opacity(0.48),
                        Color.black.opacity(0.72)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [Color.cyan.opacity(0.12), .clear],
                    center: .topLeading,
                    startRadius: 5,
                    endRadius: geometry.size.width * 0.9
                )
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }

    private func topBar(compact: Bool) -> some View {
        HStack(spacing: compact ? 10 : 12) {
            Image("OmniLogo")
                .resizable()
                .scaledToFit()
                .frame(width: compact ? 40 : 48, height: compact ? 40 : 48)
                .interpolation(.high)
                .clipShape(RoundedRectangle(cornerRadius: compact ? 11 : 14, style: .continuous))
                .shadow(color: .cyan.opacity(0.24), radius: 9)

            HStack(spacing: 0) {
                Text("OmniStation").foregroundStyle(.white)
                Text(" Dock").foregroundStyle(Color(red: 0.08, green: 0.68, blue: 1.0))
            }
            .font(.system(size: compact ? 20 : 23, weight: .bold, design: .rounded))
            .tracking(0.15)
            .lineLimit(1)
            .minimumScaleFactor(0.75)

            Spacer(minLength: 8)

            HStack(spacing: 7) {
                ForEach(DockSection.allCases, id: \.self) { section in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedSection = section
                        }
                    } label: {
                        Image(systemName: section.symbol)
                            .font(.system(size: compact ? 15 : 17, weight: .semibold))
                            .foregroundStyle(selectedSection == section ? Color.cyan : .white.opacity(0.76))
                            .frame(width: compact ? 42 : 46, height: compact ? 40 : 44)
                            .background {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(selectedSection == section ? Color.cyan.opacity(0.24) : Color.white.opacity(0.055))
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .stroke(selectedSection == section ? Color.cyan : Color.white.opacity(0.12), lineWidth: selectedSection == section ? 1.4 : 1)
                            }
                            .shadow(color: selectedSection == section ? Color.cyan.opacity(0.42) : .clear, radius: 12, y: 0)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(section.rawValue)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.black.opacity(0.18))
    }

    private func homeContent(landscape: Bool) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: landscape ? 15 : 20) {
                platformFilters(compact: landscape)

                if landscape {
                    HStack(alignment: .top, spacing: 16) {
                        featuredPanel
                            .frame(maxWidth: geometryWidthFraction(0.34))
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeading("Juegos recientes", detail: "\(filteredGames.count) elementos")
                            gameGrid(columns: 3, compact: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    featuredPanel
                    sectionHeading("Tu biblioteca", detail: "\(filteredGames.count) elementos")
                    gameGrid(columns: 2, compact: false)
                }

                if filteredGames.isEmpty {
                    emptyResults
                }

                notice
            }
            .padding(.horizontal, 16)
            .padding(.top, 5)
            .padding(.bottom, 24)
        }
    }

    private func geometryWidthFraction(_ fraction: CGFloat) -> CGFloat {
        // Width is constrained by the parent stack; this is a safe preferred width.
        UIScreen.main.bounds.width * fraction
    }

    private var featuredPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [Color(red: 0.015, green: 0.22, blue: 0.58).opacity(0.94), Color(red: 0.015, green: 0.08, blue: 0.22).opacity(0.94), Color(red: 0.002, green: 0.009, blue: 0.03).opacity(0.98)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(Color.cyan.opacity(0.34))
                    .frame(width: 170, height: 170)
                    .blur(radius: 30)
                    .offset(x: 95, y: -70)
                Image(systemName: "flame.fill")
                    .font(.system(size: 82, weight: .light))
                    .foregroundStyle(.white.opacity(0.15))
                    .rotationEffect(.degrees(-14))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(20)
                VStack(alignment: .leading, spacing: 8) {
                    Text("DESTACADO")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(Color.cyan)
                    Text(selectedPlatform == "Todos" ? "God of War" : "Tu colección de \(selectedPlatform)")
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Tu universo de juegos, en un solo lugar.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.68))
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                        Text("Explorar biblioteca")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(LinearGradient(colors: [.blue, .cyan.opacity(0.78)], startPoint: .leading, endPoint: .trailing), in: Capsule())
                    .padding(.top, 3)
                }
                .padding(18)
            }
            .frame(minHeight: 175)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(LinearGradient(colors: [.cyan.opacity(0.5), .white.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            }
             .shadow(color: .blue.opacity(0.28), radius: 20, y: 5)
        }
    }

    private func platformFilters(compact: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(platforms, id: \.name) { platform in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectedPlatform = platform.name
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: platform.symbol)
                                .font(.system(size: 11, weight: .semibold))
                            Text(platform.name)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(selectedPlatform == platform.name ? .white : .white.opacity(0.72))
                        .padding(.horizontal, compact ? 13 : 15)
                        .padding(.vertical, compact ? 10 : 12)
                        .contentShape(Capsule())
                        .background {
                            Capsule().fill(
                                selectedPlatform == platform.name
                                ? LinearGradient(colors: [.blue, Color.cyan.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [Color.blue.opacity(0.15), .white.opacity(0.035)], startPoint: .top, endPoint: .bottom)
                            )
                        }
                        .overlay {
                            Capsule().stroke(selectedPlatform == platform.name ? .cyan.opacity(0.55) : .white.opacity(0.1), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .contentShape(Capsule())
                }
            }
            .padding(.vertical, 5)
        }
    }

    private func sectionHeading(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            Text(detail)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private func gameGrid(columns: Int, compact: Bool) -> some View {
        let gridColumns = Array(repeating: GridItem(.flexible(), spacing: compact ? 10 : 12), count: columns)
        return LazyVGrid(columns: gridColumns, alignment: .leading, spacing: compact ? 10 : 13) {
            ForEach(filteredGames, id: \.name) { game in
                GameTile(game: game, compact: compact)
            }
        }
    }

    private func searchContent(landscape: Bool) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Búsqueda")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Encuentra un juego o filtra por plataforma.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.55))
                }
                searchBar
                platformFilters(compact: landscape)
                sectionHeading("Resultados", detail: "\(filteredGames.count) encontrados")
                gameGrid(columns: landscape ? 4 : 2, compact: landscape)
                if filteredGames.isEmpty { emptyResults }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    private func settingsContent(landscape: Bool) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Ajustes")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Personaliza tu experiencia.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.55))
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: landscape ? 2 : 1), spacing: 10) {
                    settingRow("Apariencia", subtitle: "Tema oscuro y acentos azules", symbol: "paintpalette.fill", tint: .cyan)
                    settingRow("Biblioteca", subtitle: "Carpetas y organización", symbol: "square.grid.2x2.fill", tint: .blue)
                    settingRow("Plataformas", subtitle: "Gestionar emuladores y sistemas", symbol: "gamecontroller.fill", tint: Color(red: 0.0, green: 0.72, blue: 1.0))
                    settingRow("Controles", subtitle: "Mando y navegación", symbol: "dpad.fill", tint: Color(red: 0.18, green: 0.46, blue: 1.0))
                    settingRow("Acerca de", subtitle: "OmniStation Dock · versión 0.0.5", symbol: "info.circle.fill", tint: Color.cyan)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    private func settingRow(_ title: String, subtitle: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.48))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.38))
        }
        .padding(13)
        .glassCard()
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.cyan)
            TextField("Buscar juegos y plataformas…", text: $searchText)
                .font(.system(size: 14))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .glassCard()
    }

    private var emptyResults: some View {
        ContentUnavailableView(
            "Sin resultados",
            systemImage: "magnifyingglass",
            description: Text("Prueba otro nombre o plataforma.")
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var notice: some View {
        HStack(spacing: 11) {
            Image("OmniLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 35, height: 35)
            VStack(alignment: .leading, spacing: 3) {
                Text("Tu universo está tomando forma")
                    .font(.system(size: 13, weight: .semibold))
                Text("Estos juegos son ejemplos visuales. La importación real llegará en una próxima fase.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.52))
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .glassCard()
    }
}

private struct GameTile: View {
    let game: (name: String, platform: String, symbol: String, tint: Color)
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            ZStack {
                LinearGradient(
                    colors: [game.tint.opacity(0.76), Color(red: 0.015, green: 0.055, blue: 0.14).opacity(0.94), Color(red: 0.003, green: 0.012, blue: 0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(Color.cyan.opacity(0.12))
                    .frame(width: compact ? 64 : 90, height: compact ? 64 : 90)
                    .blur(radius: 2)
                    .offset(x: 24, y: -22)
                Image(systemName: game.symbol)
                    .font(.system(size: compact ? 27 : 34, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.3), radius: 8)
                VStack {
                    HStack {
                        Text(game.platform)
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.4), in: Capsule())
                        Spacer()
                    }
                    Spacer()
                }
                .padding(8)
            }
            .frame(height: compact ? 90 : 118)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text(game.name)
                .font(.system(size: compact ? 11 : 12, weight: .semibold, design: .rounded))
                .tracking(0.1)
                .lineLimit(2)
                .foregroundStyle(.white.opacity(0.95))
                .frame(maxWidth: .infinity, minHeight: compact ? 28 : 30, alignment: .topLeading)
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

private extension View {
    func glassCard() -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(LinearGradient(colors: [Color.blue.opacity(0.09), .black.opacity(0.22)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.28), .cyan.opacity(0.28), .white.opacity(0.055)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.1
                    )
            }
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.08), .clear], startPoint: .top, endPoint: .bottom))
                    .frame(height: 24)
                    .allowsHitTesting(false)
            }
    }
}

#Preview {
    HomeView()
}
