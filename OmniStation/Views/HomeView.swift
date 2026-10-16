import SwiftUI
import UniformTypeIdentifiers

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
    @State private var featuredIndex = 0
    @State private var showScanMessage = false
    @State private var showShortcutEditor = false
    @State private var showFolderPicker = false
    @State private var shortcutURL = ""
    @State private var shortcutName = ""
    @State private var shortcutPlatform = "PS2"
    @State private var selectedFolderName = "Ninguna carpeta vinculada"
    @State private var savedShortcuts: [String] = []

    @AppStorage("dock.vibration") private var vibrationEnabled = true
    @AppStorage("dock.clickSound") private var clickSoundEnabled = true
    @AppStorage("dock.forceLandscape") private var forceLandscape = false
    @AppStorage("dock.hdmiLandscape") private var hdmiLandscape = true
    @AppStorage("dock.customBackground") private var customBackgroundEnabled = false
    @AppStorage("dock.language") private var appLanguage = "Español"
    @AppStorage("dock.fullGrid") private var fullGrid = false
    @AppStorage("dock.animatedWelcome") private var animatedWelcome = true
    @AppStorage("dock.headerLogo") private var headerLogo = true
    @AppStorage("dock.controllerNavigation") private var controllerNavigation = true

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
                VStack {
                    Spacer()
                    LinearGradient(colors: [.clear, Color.black.opacity(0.30), Color.black.opacity(0.78)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 76)
                        .allowsHitTesting(false)
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
                .interpolation(.high)
                .scaledToFit()
                .frame(width: compact ? 40 : 48, height: compact ? 40 : 48)
                .clipShape(RoundedRectangle(cornerRadius: compact ? 11 : 14, style: .continuous))
                .shadow(color: Color.cyan.opacity(0.24), radius: 9)

            HStack(spacing: 4) {
                Text("OmniStation")
                    .foregroundStyle(.white)
                Text("Dock")
                    .foregroundStyle(Color(red: 0.08, green: 0.68, blue: 1.0))
            }
            .font(.system(size: compact ? 16 : 18, weight: .bold, design: .rounded))
            .tracking(-0.35)
            .lineLimit(1)
            .fixedSize(horizontal: false, vertical: true)
            .minimumScaleFactor(0.82)
            .layoutPriority(1)
            .shadow(color: Color.cyan.opacity(0.12), radius: 8, y: 0)

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
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 7)
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
        let highlights: [(title: String, subtitle: String, symbol: String, platform: String, tint: Color)] = [
            ("God of War", "El viaje épico de Kratos", "flame.fill", "PS2", Color(red: 0.05, green: 0.42, blue: 1.0)),
            ("Silent Hill 2", "El misterio te espera", "moon.fill", "PS2", Color(red: 0.10, green: 0.30, blue: 0.78)),
            ("Resident Evil 4", "Sobrevive al horror", "eye.fill", "GameCube", Color(red: 0.06, green: 0.58, blue: 0.95)),
            ("Pokémon Esmeralda", "Una aventura por Hoenn", "leaf.fill", "GBA", Color(red: 0.00, green: 0.65, blue: 0.92))
        ]
        return VStack(spacing: 10) {
            TabView(selection: $featuredIndex) {
                ForEach(Array(highlights.enumerated()), id: \.offset) { index, item in
                    VStack(alignment: .leading, spacing: 0) {
                        ZStack(alignment: .bottomLeading) {
                            LinearGradient(colors: [item.tint.opacity(0.66), Color(red: 0.015, green: 0.08, blue: 0.22).opacity(0.96), Color.black.opacity(0.98)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            Circle().fill(Color.cyan.opacity(0.30)).frame(width: 160, height: 160).blur(radius: 30).offset(x: 100, y: -62)
                            Image(systemName: item.symbol).font(.system(size: 80, weight: .light)).foregroundStyle(.white.opacity(0.15)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(20)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("DESTACADO").font(.system(size: 9, weight: .heavy, design: .rounded)).tracking(2).foregroundStyle(Color.cyan)
                                Text(item.title).font(.system(size: 23, weight: .bold, design: .rounded)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.75)
                                Text(item.subtitle).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.72)).lineLimit(1)
                                Button { selectedPlatform = item.platform; selectedSection = .inicio } label: {
                                    HStack(spacing: 6) { Image(systemName: "play.fill"); Text("Explorar biblioteca") }
                                        .font(.system(size: 11, weight: .bold)).foregroundStyle(.white).padding(.horizontal, 13).padding(.vertical, 9)
                                        .background(LinearGradient(colors: [.blue, .cyan.opacity(0.78)], startPoint: .leading, endPoint: .trailing), in: Capsule())
                                }.buttonStyle(.plain).padding(.top, 3)
                            }.padding(18)
                        }
                        .frame(minHeight: 175)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(LinearGradient(colors: [.cyan.opacity(0.5), .white.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1) }
                        .shadow(color: .blue.opacity(0.25), radius: 18, y: 4)
                    }
                    .padding(.horizontal, 1)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 202)
            HStack(spacing: 6) {
                Spacer()
                ForEach(0..<4, id: \.self) { index in
                    Capsule().fill(index == featuredIndex ? Color.cyan : Color.white.opacity(0.30))
                        .frame(width: index == featuredIndex ? 17 : 5, height: 5)
                        .animation(.easeInOut(duration: 0.2), value: featuredIndex)
                }
            }
            .padding(.trailing, 5)
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
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
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
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    private func settingsContent(landscape: Bool) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Ajustes").font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Configura OmniStation Dock a tu manera.").font(.subheadline).foregroundStyle(.white.opacity(0.55))
                }
                settingsGroup("General", subtitle: "Controles, respuesta y orientación", symbol: "slider.horizontal.3") {
                    settingToggle("Mandos", subtitle: "Activar navegación con mando", symbol: "gamecontroller.fill", isOn: $controllerNavigation)
                    settingToggle("Vibración", subtitle: "Respuesta háptica en acciones compatibles", symbol: "waveform", isOn: $vibrationEnabled)
                    settingToggle("Sonido al pulsar", subtitle: "Sonidos de interfaz (preparado para integrar audio)", symbol: "speaker.wave.2.fill", isOn: $clickSoundEnabled)
                    settingToggle("Mantener Dock en horizontal", subtitle: "Preferencia de orientación apaisada", symbol: "rectangle.landscape", isOn: $forceLandscape)
                    settingToggle("Horizontal al conectar HDMI", subtitle: "Avisará antes de cambiar la orientación", symbol: "display", isOn: $hdmiLandscape)
                }
                settingsGroup("Apariencia", subtitle: "Personaliza el aspecto y la organización", symbol: "paintpalette.fill") {
                    settingToggle("Background personalizado", subtitle: "Activar fondo personalizado (selector avanzado próximamente)", symbol: "photo.fill", isOn: $customBackgroundEnabled)
                    HStack { settingLabel("Idioma", subtitle: "Idioma de la interfaz", symbol: "globe"); Spacer(); Picker("Idioma", selection: $appLanguage) { Text("Español").tag("Español"); Text("English").tag("English") }.labelsHidden().tint(.cyan).frame(maxWidth: 135) }
                    settingToggle("Cuadrícula completa", subtitle: "Distribución más densa de juegos", symbol: "square.grid.3x3.fill", isOn: $fullGrid)
                    settingToggle("Bienvenida animada", subtitle: "Mostrar la animación de inicio", symbol: "sparkles", isOn: $animatedWelcome)
                    settingToggle("Logo en cabecera", subtitle: "Mostrar el icono junto al título", symbol: "app.dashed", isOn: $headerLogo)
                    Button { showScanMessage = true } label: { settingLabel("Reorganizar plataformas", subtitle: "Orden y visibilidad se ampliarán en una próxima fase", symbol: "rectangle.3.group") }.buttonStyle(.plain)
                }
                settingsGroup("Juegos", subtitle: "Fuentes y accesos directos", symbol: "gamecontroller.fill") {
                    Button { showScanMessage = true } label: { settingLabel("Escaneo de juegos instalados", subtitle: "Iniciar comprobación de juegos disponibles", symbol: "arrow.clockwise.circle") }.buttonStyle(.plain)
                    Button { showFolderPicker = true } label: { settingLabel("Vincular carpeta contenedora", subtitle: selectedFolderName, symbol: "folder.badge.plus") }.buttonStyle(.plain)
                    Menu {
                        ForEach(platforms.map(\.name).filter { $0 != "Todos" }, id: \.self) { platform in
                            Button(platform) { shortcutPlatform = platform; showShortcutEditor = true }
                        }
                    } label: { settingLabel("Añadir URL de acceso directo", subtitle: "Plataforma: \(shortcutPlatform) · toca para elegir", symbol: "link.badge.plus") }
                    .buttonStyle(.plain)
                    ForEach(savedShortcuts, id: \.self) { shortcut in
                        settingLabel(shortcut, subtitle: "Acceso directo guardado en esta sesión", symbol: "link")
                    }
                }
                Text("Algunas opciones ya guardan su estado en el dispositivo. El acceso real a emuladores, detección HDMI y escaneo de juegos requiere integrar las API correspondientes.")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.42)).padding(.horizontal, 3)
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 100)
        }
        .alert("Escaneo de juegos", isPresented: $showScanMessage) {
            Button("Entendido", role: .cancel) { }
        } message: {
            Text("La interfaz de ajustes ya está preparada. El escaneo automático real y el acceso a contenedores de otras aplicaciones necesitan integración adicional de iOS y de cada emulador.")
        }
        .alert("Añadir acceso directo", isPresented: $showShortcutEditor) {
            TextField("Nombre del juego", text: $shortcutName)
            TextField("URL", text: $shortcutURL)
                .textInputAutocapitalization(.never).keyboardType(.URL)
            Button("Cancelar", role: .cancel) { }
            Button("Guardar") {
                let name = shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
                let url = shortcutURL.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty, URL(string: url)?.scheme != nil {
                    savedShortcuts.append("\(name) · \(shortcutPlatform)")
                }
                shortcutName = ""; shortcutURL = ""
            }
        } message: {
            Text("Introduce el nombre y la URL. La plataforma elegida se usará como etiqueta del acceso directo.")
        }
        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                selectedFolderName = url.lastPathComponent
            }
        }
    }

    private func settingsGroup<Content: View>(_ title: String, subtitle: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 11) {
                Image(systemName: symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(.cyan).frame(width: 42, height: 42).background(Color.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 3) { Text(title).font(.system(size: 17, weight: .bold, design: .rounded)); Text(subtitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)) }
            }
            VStack(spacing: 0) { content() }
                .padding(.horizontal, 12).padding(.vertical, 5).glassCard()
        }
    }

    private func settingLabel(_ title: String, subtitle: String, symbol: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.cyan).frame(width: 32, height: 32).background(Color.cyan.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) { Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white); Text(subtitle).font(.system(size: 10)).foregroundStyle(.white.opacity(0.48)).fixedSize(horizontal: false, vertical: true) }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.32))
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func settingToggle(_ title: String, subtitle: String, symbol: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.cyan).frame(width: 32, height: 32).background(Color.cyan.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) { Text(title).font(.system(size: 13, weight: .semibold)); Text(subtitle).font(.system(size: 10)).foregroundStyle(.white.opacity(0.48)).fixedSize(horizontal: false, vertical: true) }
            Spacer(minLength: 6)
            Toggle(title, isOn: isOn).labelsHidden().tint(.cyan).scaleEffect(0.88, anchor: .trailing)
        }
        .padding(.vertical, 8)
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
