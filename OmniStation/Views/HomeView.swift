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
    // Posiciones medidas en pantalla: "header", "scroll" (zona de scroll) y "content" (contenido).
    @State private var frames: [String: CGRect] = [:]

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

    // Puntos de scroll en los que logo y título terminan de desvanecerse (menos = más rápido).
    private static let titleCollapseDistance: CGFloat = 36
    // Altura de la barra superior mientras no se ha medido.
    private static let defaultHeaderHeight: CGFloat = 57
    // Logo junto al nombre: desactivado (no borrado). Ponlo en true para volver a mostrarlo.
    private static let showHeaderLogo = false

    private var headerHeight: CGFloat {
        frames["header"]?.height ?? Self.defaultHeaderHeight
    }

    /// Cuánto ha subido el contenido respecto a su posición de reposo (0 sin deslizar).
    private var scrollOffset: CGFloat {
        guard let header = frames["header"], let content = frames["content"] else { return 0 }
        return max(0, header.minY - content.minY)
    }

    /// 0 = logo y título visibles, 1 = ocultos del todo.
    private var titleHidden: CGFloat {
        min(1, scrollOffset / Self.titleCollapseDistance)
    }

    /// Zona por encima de la barra (p. ej. bajo la barra de estado) donde el contenido no se ve.
    private var fadeClearHeight: CGFloat {
        guard let header = frames["header"], let scroll = frames["scroll"] else { return 0 }
        return max(0, header.minY - scroll.minY)
    }

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            ZStack(alignment: .top) {
                background
                Group {
                    if selectedSection == .inicio {
                        homeContent(landscape: landscape)
                    } else if selectedSection == .busqueda {
                        searchContent(landscape: landscape)
                    } else {
                        settingsContent(landscape: landscape)
                    }
                }
                topBar(compact: landscape)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onPreferenceChange(FramesKey.self) { frames = $0 }
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
            // Título (y logo, si se activa): se desvanecen y suben un poco mientras se desliza.
            HStack(spacing: compact ? 10 : 12) {
                if Self.showHeaderLogo {
                    Image("OmniLogo")
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: compact ? 40 : 48, height: compact ? 40 : 48)
                        .clipShape(RoundedRectangle(cornerRadius: compact ? 11 : 14, style: .continuous))
                        .shadow(color: .cyan.opacity(0.24), radius: 9)
                }

                HStack(spacing: 5) {
                    Text("OmniStation")
                        .foregroundStyle(.white)
                    Text("Dock")
                        .foregroundStyle(Color(red: 0.08, green: 0.68, blue: 1.0))
                }
                .font(.system(size: compact ? 22 : 26, weight: .bold, design: .rounded))
                .tracking(-0.5)
                .lineLimit(1)
                .fixedSize(horizontal: false, vertical: true)
                .minimumScaleFactor(0.82)
                .layoutPriority(1)
                .shadow(color: Color.cyan.opacity(0.12), radius: 8, y: 0)
            }
            .opacity(1 - titleHidden)
            .offset(y: -10 * titleHidden)
            .scaleEffect(1 - 0.06 * titleHidden, anchor: .leading)

            Spacer(minLength: 5)

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
                            .frame(width: compact ? 38 : 42, height: compact ? 38 : 42)
                            .liquidGlass(
                                in: RoundedRectangle(cornerRadius: 13, style: .continuous),
                                tint: selectedSection == section ? Color.cyan : nil,
                                interactive: true
                            )
                            .overlay {
                                if selectedSection == section {
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .strokeBorder(Color.cyan.opacity(0.9), lineWidth: 1.2)
                                }
                            }
                            .shadow(color: selectedSection == section ? Color.cyan.opacity(0.42) : .clear, radius: 12, y: 0)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(section.rawValue)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 7)
        .reportFrame("header")
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
            .padding(.top, headerHeight + 5)
            .padding(.bottom, 24)
            .reportFrame("content")
        }
        .reportFrame("scroll")
        .topFade(clear: fadeClearHeight, fade: headerHeight)
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
            .glassRim(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
             .shadow(color: .blue.opacity(0.28), radius: 20, y: 5)
        }
    }

    private func platformFilters(compact: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(platforms, id: \.name) { platform in
                    let isSelected = selectedPlatform == platform.name
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectedPlatform = platform.name
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: platform.symbol)
                                .font(.system(size: 13, weight: .semibold))
                            Text(platform.name)
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.78))
                        .padding(.horizontal, compact ? 15 : 17)
                        .padding(.vertical, compact ? 11 : 13)
                        .contentShape(Capsule())
                        .liquidGlass(
                            in: Capsule(),
                            tint: isSelected ? Color(red: 0.05, green: 0.45, blue: 1.0) : nil,
                            interactive: true
                        )
                        .overlay {
                            if isSelected {
                                Capsule().strokeBorder(Color.cyan.opacity(0.7), lineWidth: 1)
                            }
                        }
                        .shadow(color: isSelected ? Color.cyan.opacity(0.30) : Color.clear, radius: 10)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        // Fade the scroll edges instead of covering the first/last chips with overlays.
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.055),
                    .init(color: .black, location: 0.94),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
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
            .padding(.top, headerHeight + 8)
            .padding(.bottom, 24)
            .reportFrame("content")
        }
        .reportFrame("scroll")
        .topFade(clear: fadeClearHeight, fade: headerHeight)
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
            .padding(.top, headerHeight + 8)
            .padding(.bottom, 24)
            .reportFrame("content")
        }
        .reportFrame("scroll")
        .topFade(clear: fadeClearHeight, fade: headerHeight)
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
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5))
                        Spacer()
                    }
                    Spacer()
                }
                .padding(8)
            }
            .frame(height: compact ? 90 : 118)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .glassRim(in: RoundedRectangle(cornerRadius: 14, style: .continuous))

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

private struct FramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private extension View {
    /// Mide la posición en pantalla de esta vista y la publica con un nombre.
    func reportFrame(_ id: String) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: FramesKey.self, value: [id: proxy.frame(in: .global)])
            }
        }
    }

    /// Desvanece el contenido que sube por detrás de la barra superior: invisible en la
    /// zona de arriba (`clear`) y cada vez más visible a lo largo de `fade` puntos.
    func topFade(clear: CGFloat, fade: CGFloat) -> some View {
        mask {
            VStack(spacing: 0) {
                Color.clear.frame(height: clear)
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.35), location: 0.5),
                        .init(color: .black, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: fade)
                Rectangle().fill(.black)
            }
        }
    }

    func glassCard(cornerRadius: CGFloat = 18) -> some View {
        liquidGlass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Cristal líquido. En iOS 26, compilando con Xcode 26, usa el `glassEffect` nativo de Apple;
    /// en el resto, una imitación con material translúcido, reflejos y borde de luz.
    @ViewBuilder
    func liquidGlass<S: InsettableShape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            glassEffect(nativeGlass(tint: tint, interactive: interactive), in: shape)
        } else {
            modifier(LiquidGlassFallback(shape: shape, tint: tint))
        }
        #else
        modifier(LiquidGlassFallback(shape: shape, tint: tint))
        #endif
    }

    /// Solo el borde de luz y el reflejo superior (sin fondo), para paneles que ya tienen el suyo.
    func glassRim<S: InsettableShape>(in shape: S) -> some View {
        modifier(LiquidGlassRim(shape: shape))
    }

    #if compiler(>=6.2)
    @available(iOS 26.0, *)
    private func nativeGlass(tint: Color?, interactive: Bool) -> Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint.opacity(0.55)) }
        if interactive { glass = glass.interactive() }
        return glass
    }
    #endif
}

private struct LiquidGlassRim<S: InsettableShape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        content
            .overlay { sheen }
            .overlay { rim }
    }

    // Reflejo suave en la mitad superior.
    private var sheen: some View {
        shape
            .fill(LinearGradient(
                colors: [Color.white.opacity(0.16), Color.white.opacity(0)],
                startPoint: .top,
                endPoint: .center
            ))
            .allowsHitTesting(false)
    }

    // Borde de luz: brillante arriba a la izquierda, tenue en medio, un destello abajo a la derecha.
    private var rim: some View {
        shape
            .strokeBorder(
                LinearGradient(
                    stops: [
                        Gradient.Stop(color: Color.white.opacity(0.60), location: 0),
                        Gradient.Stop(color: Color.white.opacity(0.10), location: 0.38),
                        Gradient.Stop(color: Color.cyan.opacity(0.16), location: 0.72),
                        Gradient.Stop(color: Color.white.opacity(0.34), location: 1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
            .allowsHitTesting(false)
    }
}

private struct LiquidGlassFallback<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?

    func body(content: Content) -> some View {
        content
            .background { glassFill }
            .modifier(LiquidGlassRim(shape: shape))
    }

    private var glassFill: some View {
        ZStack {
            shape.fill(.ultraThinMaterial)
            shape.fill(tintGradient)
        }
    }

    private var tintGradient: LinearGradient {
        if let tint {
            return LinearGradient(
                colors: [tint.opacity(0.80), tint.opacity(0.38)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [Color.blue.opacity(0.09), Color.black.opacity(0.22)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

#Preview {
    HomeView()
}
