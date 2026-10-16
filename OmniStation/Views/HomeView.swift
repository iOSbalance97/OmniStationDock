import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

private enum DockSection: String, CaseIterable {
    case inicio = "Inicio"
    case favoritos = "Favoritos"
    case busqueda = "Búsqueda"
    case ajustes = "Ajustes"

    var symbol: String {
        switch self {
        case .inicio: return "house.fill"
        case .favoritos: return "star.fill"
        case .busqueda: return "magnifyingglass"
        case .ajustes: return "gearshape.fill"
        }
    }
}

private enum HomeSheet: Identifiable {
    case controllers, platformOrder, addShortcut
    var id: Int { hashValue }
}

private enum SettingsDialog {
    case language, background, clearFavorites, clearLibrary
}

private struct Toast: Identifiable {
    let id = UUID()
    let text: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
}

struct HomeView: View {
    @State private var searchText = ""
    @State private var selectedPlatform = "Todos"
    @State private var selectedSection: DockSection = .inicio
    // Posiciones medidas en pantalla: "header", "scroll" (zona de scroll) y "content" (contenido).
    @State private var frames: [String: CGRect] = [:]
    @State private var featuredIndex = 0

    // Ajustes (se guardan en el dispositivo).
    @AppStorage("favoriteGames") private var favoritesRaw = ""
    @AppStorage("compactGrid") private var compactGrid = false
    @AppStorage("showWelcome") private var showWelcome = true
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("clickSound") private var clickSound = false
    @AppStorage("showHeaderLogo") private var showHeaderLogo = false
    @AppStorage("keepLandscape") private var keepLandscape = false
    @AppStorage("hdmiAutoLandscape") private var hdmiAutoLandscape = false
    @AppStorage("controllerNavigation") private var controllerNavigation = true
    @AppStorage("appLanguage") private var appLanguage = "system"
    @AppStorage("platformOrder") private var platformOrderRaw = ""
    @AppStorage("showSampleGames") private var showSampleGames = true
    @AppStorage("libraryFolderBookmark") private var folderBookmark = Data()
    @AppStorage("libraryFolderName") private var folderName = ""

    // Dispositivos
    @StateObject private var controllers = ControllerMonitor()
    @StateObject private var hdmi = HDMIMonitor()

    // Biblioteca
    @State private var libraryGames: [LibraryGame] = []
    @State private var games: [Game] = []
    @State private var featured: [Game] = []
    @State private var playCounts: [String: Int] = [:]
    @State private var isScanning = false

    // Fondo
    @State private var customBackground: UIImage?
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?

    // Varios
    @State private var showFolderImporter = false
    @State private var showAbout = false
    @State private var sheet: HomeSheet?
    @State private var dialog: SettingsDialog?
    @State private var toast: Toast?
    @State private var hdmiForced = false
    @State private var hdmiTask: Task<Void, Never>?

    init() {
        let library = LibraryStore.load()
        let counts = (UserDefaults.standard.dictionary(forKey: "playCounts") as? [String: Int]) ?? [:]
        let samples = UserDefaults.standard.object(forKey: "showSampleGames") as? Bool ?? true
        let built = Self.makeLibrary(library: library, samples: samples, counts: counts)
        _libraryGames = State(initialValue: library)
        _playCounts = State(initialValue: counts)
        _games = State(initialValue: built.games)
        _featured = State(initialValue: built.featured)
        _customBackground = State(initialValue: BackgroundStore.load())
    }

    // MARK: - Datos derivados

    private static func makeLibrary(library: [LibraryGame], samples: Bool, counts: [String: Int]) -> (games: [Game], featured: [Game]) {
        let all = (samples ? Game.samples : []) + library.map(\.asGame)
        let ranked = all.enumerated().sorted { a, b in
            let countA = counts[a.element.id] ?? 0
            let countB = counts[b.element.id] ?? 0
            return countA != countB ? countA > countB : a.offset < b.offset
        }
        return (all, ranked.prefix(4).map(\.element))
    }

    private func refreshLibrary() {
        let built = Self.makeLibrary(library: libraryGames, samples: showSampleGames, counts: playCounts)
        games = built.games
        featured = built.featured
        featuredIndex = 0
    }

    private func setLibrary(_ list: [LibraryGame]) {
        libraryGames = list
        LibraryStore.save(list)
        refreshLibrary()
    }

    private func tr(_ key: String, _ args: CVarArg...) -> String {
        let base = L10n.tr(key, appLanguage)
        return args.isEmpty ? base : String(format: base, arguments: args)
    }

    private func feedback() {
        Feedback.tap(haptics: hapticsEnabled, sound: clickSound)
    }

    private var platforms: [(name: String, symbol: String)] {
        [Platforms.all[0]] + Platforms.ordered(platformOrderRaw).map { (name: $0, symbol: Platforms.symbol(for: $0)) }
    }

    private func platformLabel(_ name: String) -> String {
        name == "Todos" ? tr("Todos") : name
    }

    private var filteredGames: [Game] {
        games.filter {
            (selectedPlatform == "Todos" || $0.platform == selectedPlatform) &&
            (searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText))
        }
    }

    private var favoriteNames: Set<String> {
        Set(favoritesRaw.split(separator: "|").map(String.init))
    }

    private var favoriteGames: [Game] {
        let names = favoriteNames
        return games.filter { names.contains($0.id) }
    }

    private var scannedCount: Int {
        libraryGames.filter { $0.source == "scan" }.count
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    // MARK: - Medidas de la cabecera

    // Puntos de scroll en los que el título termina de desvanecerse (menos = más rápido).
    private static let titleCollapseDistance: CGFloat = 36
    // Altura de la barra superior mientras no se ha medido.
    private static let defaultHeaderHeight: CGFloat = 57
    // Altura del desvanecimiento inferior.
    private static let bottomFadeHeight: CGFloat = 64

    private var headerHeight: CGFloat {
        frames["header"]?.height ?? Self.defaultHeaderHeight
    }

    /// Cuánto ha subido el contenido respecto a su posición de reposo (0 sin deslizar).
    private var scrollOffset: CGFloat {
        guard let header = frames["header"], let content = frames["content"] else { return 0 }
        return max(0, header.minY - content.minY)
    }

    /// 0 = título visible, 1 = oculto del todo.
    private var titleHidden: CGFloat {
        min(1, scrollOffset / Self.titleCollapseDistance)
    }

    /// Zona por encima de la barra (p. ej. bajo la barra de estado) donde el contenido no se ve.
    private var fadeClearHeight: CGFloat {
        guard let header = frames["header"], let scroll = frames["scroll"] else { return 0 }
        return max(0, header.minY - scroll.minY)
    }

    // MARK: - Cuerpo

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            ZStack(alignment: .top) {
                background
                Group {
                    switch selectedSection {
                    case .inicio: homeContent(landscape: landscape)
                    case .favoritos: favoritesContent(landscape: landscape)
                    case .busqueda: searchContent(landscape: landscape)
                    case .ajustes: settingsContent(landscape: landscape)
                    }
                }
                topBar(compact: landscape)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) { toastOverlay }
            .onPreferenceChange(FramesKey.self) { frames = $0 }
            .alert(tr("OmniStation Dock"), isPresented: $showAbout) {
                Button(tr("Cerrar"), role: .cancel) {}
            } message: {
                Text(tr("Versión %@", appVersion) + "\nBundle ID: " + (Bundle.main.bundleIdentifier ?? "—"))
            }
            .confirmationDialog(dialogTitle, isPresented: dialogBinding, titleVisibility: .visible) {
                dialogButtons
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
            .fileImporter(isPresented: $showFolderImporter, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
                handleFolderPick(result)
            }
            .sheet(item: $sheet) { kind in
                switch kind {
                case .controllers:
                    ControllersSheet(lang: appLanguage, monitor: controllers, navigationEnabled: $controllerNavigation)
                case .platformOrder:
                    PlatformOrderSheet(lang: appLanguage, orderRaw: $platformOrderRaw)
                case .addShortcut:
                    AddShortcutSheet(lang: appLanguage) { addShortcut($0) }
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { await applyBackground(from: item) }
            }
            .onChange(of: showSampleGames) { _, _ in refreshLibrary() }
            .onChange(of: selectedSection) { _, section in
                if section == .inicio { refreshLibrary() }
            }
            .onChange(of: controllerNavigation) { _, value in controllers.navigationEnabled = value }
            .onChange(of: keepLandscape) { _, value in
                OrientationController.apply(landscape: value || hdmiForced)
            }
            .onChange(of: hdmi.isConnected) { _, connected in handleHDMI(connected) }
            .onChange(of: hdmiAutoLandscape) { _, enabled in
                if enabled { handleHDMI(hdmi.isConnected) } else { releaseHDMILandscape() }
            }
            .onAppear {
                controllers.navigationEnabled = controllerNavigation
                controllers.onPlatformShoulder = { step in cyclePlatform(step) }
                controllers.onSectionTrigger = { step in cycleSection(step) }
                controllers.onDirection = { direction in
                    switch direction {
                    case .left: cyclePlatform(-1)
                    case .right: cyclePlatform(1)
                    case .up: cycleSection(-1)
                    case .down: cycleSection(1)
                    }
                }
                controllers.onAccept = {
                    if selectedSection == .inicio, let game = featured.indices.contains(featuredIndex) ? featured[featuredIndex] : filteredGames.first {
                        open(game)
                    } else if selectedSection == .favoritos, let game = favoriteGames.first {
                        open(game)
                    }
                }
                controllers.onCancel = {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedSection = .inicio }
                    searchText = ""
                }
                if keepLandscape {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        OrientationController.apply(landscape: true)
                    }
                }
                if hdmi.isConnected { handleHDMI(true) }
            }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Fondo

    private var background: some View {
        GeometryReader { geometry in
            ZStack {
                Group {
                    if let customBackground {
                        Image(uiImage: customBackground)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image("SpaceBackground")
                            .resizable()
                            .scaledToFill()
                    }
                }
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
        }
        .ignoresSafeArea()
    }

    private func applyBackground(from item: PhotosPickerItem) async {
        if let data = try? await item.loadTransferable(type: Data.self), BackgroundStore.save(data) {
            customBackground = BackgroundStore.load()
            showToast(tr("Fondo actualizado"))
        } else {
            showToast(tr("No se pudo usar esa imagen"))
        }
        photoItem = nil
    }

    // MARK: - Avisos (toast)

    private func showToast(_ text: String, seconds: Double = 2.8, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        let item = Toast(text: text, actionTitle: actionTitle, action: action)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { toast = item }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if toast?.id == item.id {
                withAnimation(.easeInOut(duration: 0.25)) { toast = nil }
            }
        }
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast {
            HStack(spacing: 14) {
                Text(toast.text)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                if let title = toast.actionTitle, let action = toast.action {
                    Button(title) {
                        action()
                        withAnimation(.easeInOut(duration: 0.25)) { self.toast = nil }
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.cyan)
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.bottom, 26)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Diálogos de ajustes

    private var dialogBinding: Binding<Bool> {
        Binding(get: { dialog != nil }, set: { if !$0 { dialog = nil } })
    }

    private var dialogTitle: String {
        switch dialog {
        case .language: return tr("Idioma")
        case .background: return tr("Fondo personalizado")
        case .clearFavorites: return tr("¿Borrar todos los favoritos?")
        case .clearLibrary: return tr("¿Quitar los juegos añadidos?")
        case nil: return ""
        }
    }

    @ViewBuilder
    private var dialogButtons: some View {
        switch dialog {
        case .language:
            Button(tr("Sistema")) { appLanguage = "system" }
            Button("Español") { appLanguage = "es" }
            Button("English") { appLanguage = "en" }
        case .background:
            Button(tr("Elegir otra imagen")) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showPhotoPicker = true }
            }
            Button(tr("Restaurar fondo"), role: .destructive) {
                BackgroundStore.remove()
                customBackground = nil
                showToast(tr("Fondo restaurado"))
            }
        case .clearFavorites:
            Button(tr("Borrar favoritos"), role: .destructive) { favoritesRaw = "" }
        case .clearLibrary:
            Button(tr("Quitar juegos"), role: .destructive) { setLibrary([]) }
        case nil:
            EmptyView()
        }
        Button(tr("Cancelar"), role: .cancel) {}
    }

    // MARK: - HDMI y orientación

    private func handleHDMI(_ connected: Bool) {
        hdmiTask?.cancel()
        if connected {
            guard hdmiAutoLandscape, !hdmiForced else { return }
            showToast(tr("Pantalla HDMI detectada. Cambiando a horizontal…"), seconds: 3, actionTitle: tr("Cancelar")) {
                hdmiTask?.cancel()
            }
            hdmiTask = Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                hdmiForced = true
                OrientationController.apply(landscape: true)
            }
        } else {
            releaseHDMILandscape()
        }
    }

    private func releaseHDMILandscape() {
        hdmiTask?.cancel()
        guard hdmiForced else { return }
        hdmiForced = false
        OrientationController.apply(landscape: keepLandscape)
    }

    private func cyclePlatform(_ step: Int) {
        let names = platforms.map(\\.name)
        guard !names.isEmpty else { return }
        let current = names.firstIndex(of: selectedPlatform) ?? 0
        selectedPlatform = names[(current + step + names.count) % names.count]
        feedback()
    }

    private func cycleSection(_ step: Int) {
        let all = DockSection.allCases
        guard let index = all.firstIndex(of: selectedSection) else { return }
        let next = all[(index + step + all.count) % all.count]
        feedback()
        withAnimation(.easeInOut(duration: 0.2)) { selectedSection = next }
    }

    // MARK: - Biblioteca: abrir, favoritos, escaneo

    private func open(_ game: Game) {
        feedback()
        playCounts[game.id, default: 0] += 1
        UserDefaults.standard.set(playCounts, forKey: "playCounts")
        guard let text = game.launchURL, let url = URL(string: text) else {
            showToast(tr("Este juego aún no tiene acceso directo"))
            return
        }
        UIApplication.shared.open(url) { success in
            if !success {
                DispatchQueue.main.async { showToast(tr("No se pudo abrir el enlace")) }
            }
        }
    }

    private func toggleFavorite(_ id: String) {
        var names = favoriteNames
        if names.contains(id) { names.remove(id) } else { names.insert(id) }
        favoritesRaw = names.sorted().joined(separator: "|")
        feedback()
    }

    private func removeGame(_ game: Game) {
        setLibrary(libraryGames.filter { $0.id != game.id })
    }

    private func addShortcut(_ item: LibraryGame) {
        var list = libraryGames.filter { $0.id != item.id }
        list.append(item)
        setLibrary(list)
        showToast(tr("Acceso directo añadido"))
    }

    private func handleFolderPick(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            folderBookmark = try LibraryFolder.bookmark(for: url)
            folderName = url.lastPathComponent
            showToast(tr("Carpeta vinculada: %@", folderName))
            scanLibrary()
        } catch {
            showToast(tr("No se pudo vincular la carpeta"))
        }
    }

    private func scanLibrary() {
        guard !folderBookmark.isEmpty, let url = LibraryFolder.resolve(folderBookmark) else {
            showToast(tr("Primero vincula una carpeta de juegos"))
            showFolderImporter = true
            return
        }
        guard !isScanning else { return }
        isScanning = true
        showToast(tr("Escaneando…"), seconds: 1.5)
        Task {
            let found = await Task.detached(priority: .userInitiated) { () -> [LibraryGame] in
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                return LibraryScanner.scan(folder: url)
            }.value
            // Sustituye los escaneados y conserva los accesos directos.
            setLibrary(libraryGames.filter { $0.source != "scan" } + found)
            isScanning = false
            showToast(found.isEmpty ? tr("No se encontraron juegos en la carpeta") : tr("Escaneo completo: %ld juegos", found.count), seconds: 3.2)
        }
    }

    // MARK: - Barra superior

    private func topBar(compact: Bool) -> some View {
        HStack(spacing: 0) {
            // Título (y logo, si se activa): se desvanecen y suben un poco mientras se desliza.
            HStack(spacing: compact ? 10 : 12) {
                if showHeaderLogo {
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
                .font(.system(size: compact ? (showHeaderLogo ? 18 : 22) : (showHeaderLogo ? 20 : 25), weight: .bold, design: .rounded))
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

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                ForEach(DockSection.allCases, id: \.self) { section in
                    Button {
                        feedback()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedSection = section
                        }
                    } label: {
                        Image(systemName: section.symbol)
                            .font(.system(size: compact ? 15 : 17, weight: .semibold))
                            .foregroundStyle(selectedSection == section ? Color.cyan : .white.opacity(0.76))
                            .frame(width: compact ? 36 : 40, height: compact ? 36 : 40)
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
                    .accessibilityLabel(tr(section.rawValue))
                }
            }
            .layoutPriority(2)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 7)
        .reportFrame("header")
    }

    // MARK: - Estructura común de pantallas con scroll

    private func screen<Content: View>(topGap: CGFloat = 8, @ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(showsIndicators: false) {
            content()
                .padding(.horizontal, 16)
                .padding(.top, headerHeight + topGap)
                .padding(.bottom, 44)
                .reportFrame("content")
        }
        .reportFrame("scroll")
        .edgeFade(clear: fadeClearHeight, fade: headerHeight, bottom: Self.bottomFadeHeight)
    }

    private func screenTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    // MARK: - Inicio

    private func homeContent(landscape: Bool) -> some View {
        screen(topGap: 5) {
            VStack(alignment: .leading, spacing: landscape ? 15 : 20) {
                platformFilters(compact: landscape)

                if landscape {
                    HStack(alignment: .top, spacing: 16) {
                        featuredPanel
                            .frame(maxWidth: geometryWidthFraction(0.34))
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeading(tr("Juegos recientes"), detail: tr("%ld elementos", filteredGames.count))
                            gameGrid(filteredGames, columns: 3, compact: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    featuredPanel
                    sectionHeading(tr("Tu biblioteca"), detail: tr("%ld elementos", filteredGames.count))
                    gameGrid(filteredGames, columns: compactGrid ? 3 : 2, compact: compactGrid)
                }

                if filteredGames.isEmpty {
                    emptyResults
                }

                if showSampleGames && libraryGames.isEmpty {
                    notice
                }
            }
        }
    }

    private func geometryWidthFraction(_ fraction: CGFloat) -> CGFloat {
        // Width is constrained by the parent stack; this is a safe preferred width.
        UIScreen.main.bounds.width * fraction
    }

    // Tarjeta destacada: 4 juegos (los más usados) que se deslizan, con puntos abajo a la derecha.
    @ViewBuilder
    private var featuredPanel: some View {
        if featured.isEmpty {
            emptyFeatured
        } else {
            TabView(selection: $featuredIndex) {
                ForEach(Array(featured.enumerated()), id: \.element.id) { index, game in
                    featuredCard(game)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 190)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .glassRim(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(alignment: .bottomTrailing) { featuredDots }
            .shadow(color: .blue.opacity(0.28), radius: 20, y: 5)
        }
    }

    private var featuredDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<featured.count, id: \.self) { index in
                Capsule()
                    .fill(index == featuredIndex ? Color.cyan : Color.white.opacity(0.35))
                    .frame(width: index == featuredIndex ? 16 : 6, height: 6)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: featuredIndex)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(14)
        .allowsHitTesting(false)
    }

    private func featuredCard(_ game: Game) -> some View {
        let plays = playCounts[game.id] ?? 0
        return ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    game.tint.opacity(0.62),
                    Color(red: 0.015, green: 0.08, blue: 0.22).opacity(0.94),
                    Color(red: 0.002, green: 0.009, blue: 0.03).opacity(0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.cyan.opacity(0.34))
                .frame(width: 170, height: 170)
                .blur(radius: 30)
                .offset(x: 95, y: -70)
            Image(systemName: game.symbol)
                .font(.system(size: 82, weight: .light))
                .foregroundStyle(.white.opacity(0.15))
                .rotationEffect(.degrees(-14))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(20)
            VStack(alignment: .leading, spacing: 8) {
                Text(plays > 0 ? tr("MÁS JUGADO") : tr("DESTACADO"))
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(Color.cyan)
                Text(game.name)
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(plays > 0 ? tr("%@ · %ld veces", game.platform, plays) : game.platform)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
                Button {
                    open(game)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                        Text(tr("Jugar"))
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(LinearGradient(colors: [.blue, .cyan.opacity(0.78)], startPoint: .leading, endPoint: .trailing), in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 3)
            }
            .padding(18)
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyFeatured: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Color.cyan)
            Text(tr("Tu biblioteca está vacía"))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Text(tr("Vincula una carpeta o añade un acceso directo en Ajustes → Juegos."))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .glassCard(cornerRadius: 22)
    }

    private func platformFilters(compact: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(platforms, id: \.name) { platform in
                    let isSelected = selectedPlatform == platform.name
                    Button {
                        feedback()
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectedPlatform = platform.name
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: platform.symbol)
                                .font(.system(size: 13, weight: .semibold))
                            Text(platformLabel(platform.name))
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

    private func gameGrid(_ items: [Game], columns: Int, compact: Bool) -> some View {
        let gridColumns = Array(repeating: GridItem(.flexible(), spacing: compact ? 10 : 12), count: columns)
        return LazyVGrid(columns: gridColumns, alignment: .leading, spacing: compact ? 10 : 13) {
            ForEach(items) { game in
                let isFavorite = favoriteNames.contains(game.id)
                let remove: (() -> Void)? = game.isCustom ? { removeGame(game) } : nil
                GameTile(
                    game: game,
                    compact: compact,
                    isFavorite: isFavorite,
                    favoriteLabel: isFavorite ? tr("Quitar de favoritos") : tr("Añadir a favoritos"),
                    removeLabel: tr("Quitar de la biblioteca"),
                    onToggleFavorite: { toggleFavorite(game.id) },
                    onOpen: { open(game) },
                    onRemove: remove
                )
            }
        }
    }

    // MARK: - Búsqueda

    private func searchContent(landscape: Bool) -> some View {
        screen {
            VStack(alignment: .leading, spacing: 18) {
                screenTitle(tr("Búsqueda"), subtitle: tr("Encuentra un juego o filtra por plataforma."))
                searchBar
                platformFilters(compact: landscape)
                sectionHeading(tr("Resultados"), detail: tr("%ld encontrados", filteredGames.count))
                gameGrid(filteredGames, columns: landscape ? 4 : (compactGrid ? 3 : 2), compact: landscape || compactGrid)
                if filteredGames.isEmpty { emptyResults }
            }
        }
    }

    // MARK: - Favoritos

    private func favoritesContent(landscape: Bool) -> some View {
        screen {
            VStack(alignment: .leading, spacing: 18) {
                screenTitle(tr("Favoritos"), subtitle: tr("Tus juegos marcados con estrella."))

                if favoriteGames.isEmpty {
                    emptyFavorites
                } else {
                    sectionHeading(tr("Tus favoritos"), detail: tr("%ld elementos", favoriteGames.count))
                    gameGrid(favoriteGames, columns: landscape ? 4 : (compactGrid ? 3 : 2), compact: landscape || compactGrid)
                }
            }
        }
    }

    private var emptyFavorites: some View {
        ContentUnavailableView(
            tr("Aún no hay favoritos"),
            systemImage: "star",
            description: Text(tr("Toca la estrella de un juego para guardarlo aquí."))
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .glassCard()
    }

    // MARK: - Ajustes

    private func settingsContent(landscape: Bool) -> some View {
        screen {
            VStack(alignment: .leading, spacing: 14) {
                screenTitle(tr("Ajustes"), subtitle: tr("Personaliza tu experiencia."))
                    .padding(.bottom, 4)

                settingsHeader(tr("General"))
                settingsGrid(landscape: landscape) {
                    settingCard(tr("Mandos"), subtitle: controllersSubtitle, symbol: "gamecontroller.fill", tint: Color(red: 0.0, green: 0.72, blue: 1.0), action: {
                        feedback()
                        sheet = .controllers
                    }) {
                        settingBadge("\(controllers.controllers.count)", tint: controllers.controllers.isEmpty ? Color.gray : Color.green)
                    }
                    settingToggleCard(tr("Vibración"), subtitle: tr("Respuesta háptica al tocar"), symbol: "iphone.radiowaves.left.and.right", tint: Color(red: 0.0, green: 0.72, blue: 1.0), isOn: $hapticsEnabled)
                    settingToggleCard(tr("Sonido al pulsar"), subtitle: tr("Clic al tocar botones"), symbol: "speaker.wave.2.fill", tint: Color(red: 0.30, green: 0.60, blue: 1.0), isOn: $clickSound)
                    settingToggleCard(tr("Dock en horizontal"), subtitle: tr("Mantener la app en horizontal"), symbol: "iphone.landscape", tint: Color(red: 0.18, green: 0.46, blue: 1.0), isOn: $keepLandscape)
                    settingToggleCard(tr("Horizontal con HDMI"), subtitle: tr("Avisa y gira al conectar HDMI"), symbol: "tv.fill", tint: Color(red: 0.16, green: 0.82, blue: 1.0), isOn: $hdmiAutoLandscape)
                    settingCard(tr("Acerca de"), subtitle: tr("Versión %@", appVersion), symbol: "info.circle.fill", tint: Color.cyan, action: {
                        feedback()
                        showAbout = true
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.38))
                    }
                }

                settingsHeader(tr("Apariencia"))
                settingsGrid(landscape: landscape) {
                    settingCard(tr("Fondo personalizado"), subtitle: customBackground == nil ? tr("Predeterminado") : tr("Imagen propia"), symbol: "photo.on.rectangle", tint: Color(red: 0.18, green: 0.46, blue: 1.0), action: {
                        feedback()
                        if customBackground == nil { showPhotoPicker = true } else { dialog = .background }
                    }) {
                        if customBackground != nil { settingBadge("ON") }
                    }
                    settingCard(tr("Idioma"), subtitle: languageLabel, symbol: "globe", tint: Color(red: 0.0, green: 0.72, blue: 1.0), action: {
                        feedback()
                        dialog = .language
                    }) {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.38))
                    }
                    settingCard(tr("Reorganizar plataformas"), subtitle: tr("Orden de los filtros"), symbol: "arrow.up.arrow.down", tint: Color(red: 0.30, green: 0.60, blue: 1.0), action: {
                        feedback()
                        sheet = .platformOrder
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.38))
                    }
                    settingToggleCard(tr("Cuadrícula completa"), subtitle: tr("Más juegos por pantalla"), symbol: "square.grid.3x3.fill", tint: Color.cyan, isOn: $compactGrid)
                    settingToggleCard(tr("Bienvenida animada"), subtitle: tr("Pantalla de inicio al abrir"), symbol: "sparkles", tint: Color(red: 0.30, green: 0.60, blue: 1.0), isOn: $showWelcome)
                    settingToggleCard(tr("Logo en cabecera"), subtitle: tr("Icono junto al nombre"), symbol: "photo.fill", tint: Color(red: 0.18, green: 0.46, blue: 1.0), isOn: $showHeaderLogo)
                }

                settingsHeader(tr("Juegos"))
                settingsGrid(landscape: landscape) {
                    settingCard(tr("Escaneo de juegos"), subtitle: folderName.isEmpty ? tr("Vincula una carpeta primero") : tr("Buscar en «%@»", folderName), symbol: "arrow.triangle.2.circlepath", tint: Color(red: 0.0, green: 0.72, blue: 1.0), action: {
                        feedback()
                        scanLibrary()
                    }) {
                        if isScanning {
                            ProgressView().tint(Color.cyan)
                        } else {
                            settingBadge("\(scannedCount)")
                        }
                    }
                    settingCard(tr("Vincular carpeta"), subtitle: folderName.isEmpty ? tr("Carpeta contenedora") : folderName, symbol: "folder.badge.plus", tint: Color(red: 0.30, green: 0.60, blue: 1.0), action: {
                        feedback()
                        showFolderImporter = true
                    }) {
                        if !folderName.isEmpty { settingBadge("OK", tint: Color.green) }
                    }
                    settingCard(tr("Acceso directo (URL)"), subtitle: tr("Abre un emulador con un enlace"), symbol: "link.badge.plus", tint: Color(red: 0.18, green: 0.46, blue: 1.0), action: {
                        feedback()
                        sheet = .addShortcut
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                    settingToggleCard(tr("Juegos de ejemplo"), subtitle: tr("Mostrar los de demostración"), symbol: "square.stack.3d.up.fill", tint: Color(red: 0.16, green: 0.82, blue: 1.0), isOn: $showSampleGames)
                    settingCard(tr("Borrar favoritos"), subtitle: tr("Quita todos los marcados"), symbol: "star.slash.fill", tint: Color.orange, action: {
                        feedback()
                        if !favoriteNames.isEmpty { dialog = .clearFavorites }
                    }) {
                        settingBadge("\(favoriteNames.count)", tint: Color.orange)
                    }
                    settingCard(tr("Quitar añadidos"), subtitle: tr("Escaneados y accesos directos"), symbol: "trash.fill", tint: Color.orange, action: {
                        feedback()
                        if !libraryGames.isEmpty { dialog = .clearLibrary }
                    }) {
                        settingBadge("\(libraryGames.count)", tint: Color.orange)
                    }
                }
            }
        }
    }

    private var controllersSubtitle: String {
        switch controllers.controllers.count {
        case 0: return tr("Ninguno conectado")
        case 1: return controllers.controllers[0].name
        default: return tr("%ld conectados", controllers.controllers.count)
        }
    }

    private var languageLabel: String {
        switch appLanguage {
        case "es": return "Español"
        case "en": return "English"
        default: return tr("Sistema")
        }
    }

    private func settingsHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .tracking(1.6)
            .foregroundStyle(Color.cyan.opacity(0.85))
            .padding(.top, 8)
            .padding(.leading, 2)
    }

    private func settingsGrid<Content: View>(landscape: Bool, @ViewBuilder content: () -> Content) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: landscape ? 3 : 2),
            spacing: 12
        ) {
            content()
        }
    }

    /// Tarjeta de ajuste: icono arriba, control a la derecha (interruptor, etiqueta...) y texto debajo.
    private func settingCard<Trailing: View>(
        _ title: String,
        subtitle: String,
        symbol: String,
        tint: Color,
        action: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        let trailingView = trailing()
        return Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 40, height: 40)
                        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Spacer(minLength: 4)
                    trailingView
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .glassCard(interactive: true)
        }
        .buttonStyle(.plain)
    }

    private func settingToggleCard(_ title: String, subtitle: String, symbol: String, tint: Color, isOn: Binding<Bool>) -> some View {
        settingCard(title, subtitle: subtitle, symbol: symbol, tint: tint, action: {
            isOn.wrappedValue.toggle()
            feedback()
        }) {
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .tint(Color.cyan)
                .fixedSize()
                .allowsHitTesting(false)
        }
    }

    private func settingBadge(_ text: String, tint: Color = Color.cyan) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .tracking(0.6)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.14), in: Capsule())
    }

    // MARK: - Piezas sueltas

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.cyan)
            TextField(tr("Buscar juegos y plataformas…"), text: $searchText)
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
            tr("Sin resultados"),
            systemImage: "magnifyingglass",
            description: Text(tr("Prueba otro nombre o plataforma."))
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
                Text(tr("Tu universo está tomando forma"))
                    .font(.system(size: 13, weight: .semibold))
                Text(tr("Estos son juegos de ejemplo. Vincula una carpeta o añade accesos directos en Ajustes → Juegos."))
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
    let game: Game
    var compact: Bool = false
    var isFavorite: Bool = false
    var favoriteLabel: String = ""
    var removeLabel: String = ""
    var onToggleFavorite: () -> Void = {}
    var onOpen: () -> Void = {}
    var onRemove: (() -> Void)? = nil

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
                        Button(action: onToggleFavorite) {
                            Image(systemName: isFavorite ? "star.fill" : "star")
                                .font(.system(size: compact ? 11 : 13, weight: .bold))
                                .foregroundStyle(isFavorite ? Color.yellow : Color.white.opacity(0.85))
                                .frame(width: compact ? 24 : 28, height: compact ? 24 : 28)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(favoriteLabel)
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
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .contextMenu {
            Button(action: onToggleFavorite) {
                Label(favoriteLabel, systemImage: isFavorite ? "star.slash" : "star")
            }
            if let onRemove {
                Button(role: .destructive, action: onRemove) {
                    Label(removeLabel, systemImage: "trash")
                }
            }
        }
    }
}

#Preview {
    HomeView()
}
