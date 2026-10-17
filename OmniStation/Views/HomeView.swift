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
    case language, background, clearFavorites, clearLibrary, gameOptions
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
    // Selección explícita para la cruceta: no dependemos del focus automático de SwiftUI.
    @State private var controllerSelectedGameID: String?
    // Zona seleccionada por la cruceta: juegos, destacados o búsqueda.
    @State private var controllerSelectedArea = "games"
    @State private var controllerSelectedSettingIndex = 0
    @State private var controllerSelectedLetterIndex = 0
    @State private var controllerAlphabetSearchText = ""
    @FocusState private var controllerSearchFocused: Bool
    // Ventanas de selección: puente con el mando y fila marcada en los menús propios.
    @StateObject private var sheetPad = SheetPad()
    @State private var menuIndex = 0
    // Modo Dock: botón marcado entre los 4 iconos de opciones del juego.
    @State private var dockOptionIndex = 0
    // Plataforma a la que debe desplazarse la barra de filtros.
    @State private var platformScrollID: String?

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
    @AppStorage("dockModeEnabled") private var dockModeEnabled = true
    @AppStorage("clock24h") private var clock24h = true

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
    @State private var hdmiPending = false
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

    private var gamepadConnected: Bool {
        !controllers.controllers.isEmpty
    }

    private var isLandscapeNow: Bool {
        UIScreen.main.bounds.width > UIScreen.main.bounds.height
    }

    /// Modo Dock: carrusel en horizontal (con el ajuste activado) o forzado por una pantalla HDMI.
    private var dockActive: Bool {
        isLandscapeNow && (dockModeEnabled || hdmiForced)
    }

    private let controllerAlphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init) + ["⌫", "✕"]

    private var filteredGames: [Game] {
        games.filter {
            (selectedPlatform == "Todos" || $0.platform == selectedPlatform) &&
            (searchText.isEmpty || (gamepadConnected ? $0.name.range(of: searchText, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil : $0.name.localizedCaseInsensitiveContains(searchText)))
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
            rootView(size: geometry.size)
        }
    }

    // MARK: - Cuerpo por partes
    // El cuerpo se construye en funciones separadas para que el compilador compruebe
    // cada parte por su cuenta: con una sola expresión enorme se queda sin tiempo.

    private func rootView(size: CGSize) -> some View {
        let landscape: Bool = size.width > size.height
        let dock: Bool = landscape && (dockModeEnabled || hdmiForced)
        let layered = layeredContent(landscape: landscape, dock: dock)
        let decorated = withOverlays(layered, dock: dock)
        let presented = withPresentations(decorated)
        let observed = withSettingObservers(presented)
        return withNavigationObservers(observed)
            .onAppear { handleAppear() }
            .preferredColorScheme(.dark)
    }

    private func layeredContent(landscape: Bool, dock: Bool) -> some View {
        ZStack(alignment: .top) {
            background
            screenContent(landscape: landscape, dock: dock)
            topChrome(landscape: landscape, dock: dock)
            padMenuOverlay
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func screenContent(landscape: Bool, dock: Bool) -> some View {
        if dock && (selectedSection == .inicio || selectedSection == .favoritos) {
            dockHome()
        } else {
            switch selectedSection {
            case .inicio: homeContent(landscape: landscape)
            case .favoritos: favoritesContent(landscape: landscape)
            case .busqueda: searchContent(landscape: landscape)
            case .ajustes: settingsContent(landscape: landscape)
            }
        }
    }

    @ViewBuilder
    private func topChrome(landscape: Bool, dock: Bool) -> some View {
        if dock {
            dockTopBar()
        } else {
            topBar(compact: landscape)
        }
    }

    @ViewBuilder
    private func dockBottomOverlay(_ dock: Bool) -> some View {
        if dock {
            dockBottomBar
        }
    }

    private func withOverlays<V: View>(_ view: V, dock: Bool) -> some View {
        view
            .overlay(alignment: .bottom) { dockBottomOverlay(dock) }
            .overlay(alignment: .bottom) { toastOverlay }
            .onPreferenceChange(FramesKey.self) { frames = $0 }
    }

    private func withPresentations<V: View>(_ view: V) -> some View {
        view
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
            .fileImporter(isPresented: $showFolderImporter, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
                handleFolderPick(result)
            }
            .sheet(item: $sheet) { kind in
                sheetView(kind)
            }
    }

    @ViewBuilder
    private func sheetView(_ kind: HomeSheet) -> some View {
        switch kind {
        case .controllers:
            ControllersSheet(lang: appLanguage, monitor: controllers, navigationEnabled: $controllerNavigation, pad: sheetPad)
        case .platformOrder:
            PlatformOrderSheet(lang: appLanguage, orderRaw: $platformOrderRaw, pad: sheetPad)
        case .addShortcut:
            AddShortcutSheet(lang: appLanguage, pad: sheetPad) { item in
                addShortcut(item)
            }
        }
    }

    private func withSettingObservers<V: View>(_ view: V) -> some View {
        view
            .onChange(of: photoItem) { _, item in handlePhotoItem(item) }
            .onChange(of: showSampleGames) { _, _ in refreshLibrary() }
            .onChange(of: dialog) { _, _ in menuIndex = 0 }
            .onChange(of: showAbout) { _, _ in menuIndex = 0 }
            .onChange(of: controllerNavigation) { _, value in controllers.navigationEnabled = value }
            .onChange(of: keepLandscape) { _, value in handleKeepLandscapeChange(value) }
            .onChange(of: hdmi.isConnected) { _, connected in handleHDMI(connected) }
            .onChange(of: hdmiAutoLandscape) { _, enabled in handleHDMIAutoChange(enabled) }
    }

    private func withNavigationObservers<V: View>(_ view: V) -> some View {
        view
            .onChange(of: dockActive) { _, _ in resetControllerFocus() }
            .onChange(of: selectedSection) { _, section in handleSectionChange(section) }
            .onChange(of: selectedPlatform) { _, _ in handlePlatformChange() }
            .onChange(of: controllers.controllers.count) { _, count in handleControllerCountChange(count) }
            .onChange(of: searchText) { _, _ in handleSearchTextChange() }
    }

    // MARK: - Reacciones a cambios

    private func handlePhotoItem(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task { await applyBackground(from: item) }
    }

    private func handleKeepLandscapeChange(_ value: Bool) {
        OrientationController.apply(landscape: value || hdmiForced)
    }

    private func handleHDMIAutoChange(_ enabled: Bool) {
        if enabled {
            handleHDMI(hdmi.isConnected)
        } else {
            releaseHDMILandscape()
        }
    }

    private func handleSectionChange(_ section: DockSection) {
        if section == .inicio { refreshLibrary() }
        controllerSelectedGameID = controllerGames.first?.id
        controllerSearchFocused = false
        // En el Modo Dock, al cambiar de pestaña con el mando se queda en la barra de pestañas.
        let stayOnDockNav: Bool = dockActive && controllerSelectedArea == "dockNav"
        guard !stayOnDockNav else { return }
        switch section {
        case .inicio: controllerSelectedArea = "games"
        case .busqueda: controllerSelectedArea = gamepadConnected ? "search" : "games"
        case .favoritos: controllerSelectedArea = "games"
        case .ajustes:
            controllerSelectedArea = "settings"
            controllerSelectedSettingIndex = 0
        }
    }

    private func handlePlatformChange() {
        controllerSelectedGameID = controllerGames.first?.id
        if selectedSection == .inicio, selectedPlatform != "Todos", controllerSelectedArea == "featured" {
            controllerSelectedArea = "games"
        }
    }

    private func handleControllerCountChange(_ count: Int) {
        guard selectedSection == .busqueda else { return }
        controllerSelectedArea = count > 0 ? "search" : "games"
        controllerSearchFocused = false
    }

    private func handleSearchTextChange() {
        if let selected = controllerSelectedGameID, !controllerGames.contains(where: { $0.id == selected }) {
            controllerSelectedGameID = controllerGames.first?.id
        }
    }

    private func handleAppear() {
        controllers.navigationEnabled = controllerNavigation
        controllers.onShoulder = { step in handleShoulder(step) }
        controllers.onTrigger = { step in handleTrigger(step) }
        controllers.onCancel = { handleControllerCancel() }
        controllers.onDirection = { direction in handleDirection(direction) }
        controllers.onAccept = { handleAccept() }
        controllers.onOptions = { handleOptions() }
        if keepLandscape {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                OrientationController.apply(landscape: true)
            }
        }
        if hdmi.isConnected { handleHDMI(true) }
    }

    // MARK: - Botones del mando

    private func handleShoulder(_ step: Int) {
        // Con una ventana abierta, la interfaz de detrás no se mueve.
        guard !modalActive else { return }
        // En Ajustes y Favoritos los hombros no cambian de plataforma: no hay filtros visibles.
        guard selectedSection != .ajustes, selectedSection != .favoritos else { return }
        cyclePlatform(step)
    }

    private func handleTrigger(_ step: Int) {
        guard !modalActive else { return }
        cycleSection(step)
    }

    private func handleDirection(_ direction: ControllerMonitor.Direction) {
        if modalActive {
            routeModalDirection(direction)
        } else {
            moveControllerSelection(direction)
        }
    }

    private func handleAccept() {
        if modalActive {
            routeModalAccept()
        } else {
            activateControllerSelection()
        }
    }

    private func handleOptions() {
        guard !modalActive else { return }
        handleOptionsButton()
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
                    .buttonStyle(ControllerFocusableButtonStyle())
                    .focusable()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.bottom, dockActive ? 66 : 26)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Ventanas de selección (se manejan también con el mando)

    private struct PadMenuItem {
        enum Kind { case normal, destructive, cancel }
        let title: String
        var kind: Kind = .normal
        let action: () -> Void
    }

    private var systemPickerOpen: Bool { showPhotoPicker || showFolderImporter }

    /// Hay una ventana encima: la interfaz de detrás no debe recibir el mando.
    private var modalActive: Bool {
        dialog != nil || showAbout || sheet != nil || systemPickerOpen
    }

    private func closePadMenu() {
        dialog = nil
        showAbout = false
    }

    private var padMenu: (title: String, message: String?, items: [PadMenuItem])? {
        if showAbout {
            return (
                tr("OmniStation Dock"),
                tr("Versión %@", appVersion) + "\nBundle ID: " + (Bundle.main.bundleIdentifier ?? "—"),
                [PadMenuItem(title: tr("Cerrar"), kind: .cancel) { closePadMenu() }]
            )
        }
        guard let dialog else { return nil }
        let cancel = PadMenuItem(title: tr("Cancelar"), kind: .cancel) { closePadMenu() }
        switch dialog {
        case .language:
            return (tr("Idioma"), nil, [
                PadMenuItem(title: tr("Sistema")) { appLanguage = "system"; closePadMenu() },
                PadMenuItem(title: "Español") { appLanguage = "es"; closePadMenu() },
                PadMenuItem(title: "English") { appLanguage = "en"; closePadMenu() },
                cancel
            ])
        case .background:
            return (tr("Fondo personalizado"), nil, [
                PadMenuItem(title: tr("Elegir otra imagen")) {
                    closePadMenu()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showPhotoPicker = true }
                },
                PadMenuItem(title: tr("Restaurar fondo"), kind: .destructive) {
                    BackgroundStore.remove()
                    customBackground = nil
                    closePadMenu()
                    showToast(tr("Fondo restaurado"))
                },
                cancel
            ])
        case .clearFavorites:
            return (tr("¿Borrar todos los favoritos?"), nil, [
                PadMenuItem(title: tr("Borrar favoritos"), kind: .destructive) { favoritesRaw = ""; closePadMenu() },
                cancel
            ])
        case .clearLibrary:
            return (tr("¿Quitar los juegos añadidos?"), nil, [
                PadMenuItem(title: tr("Quitar juegos"), kind: .destructive) { setLibrary([]); closePadMenu() },
                cancel
            ])
        case .gameOptions:
            let optionsID: String? = dockSelectedID(in: controllerGames)
            guard let game = games.first(where: { $0.id == optionsID }) else { return nil }
            var items = [PadMenuItem(title: favoriteNames.contains(game.id) ? tr("Quitar de favoritos") : tr("Añadir a favoritos")) {
                toggleFavorite(game.id)
                closePadMenu()
            }]
            if game.isCustom {
                items.append(PadMenuItem(title: tr("Quitar de la biblioteca"), kind: .destructive) {
                    removeGame(game)
                    closePadMenu()
                })
            }
            items.append(cancel)
            return (game.name, game.platform, items)
        }
    }

    @ViewBuilder
    private var padMenuOverlay: some View {
        if let menu = padMenu {
            ZStack {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .onTapGesture { closePadMenu() }
                VStack(spacing: 14) {
                    Text(menu.title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    if let message = menu.message {
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                    VStack(spacing: 8) {
                        ForEach(menu.items.indices, id: \.self) { index in
                            padMenuButton(menu.items[index], selected: index == menuIndex)
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: 340)
                .glassCard(cornerRadius: 26)
                .padding(24)
            }
            .transition(.opacity)
        }
    }

    private func padMenuButton(_ item: PadMenuItem, selected: Bool) -> some View {
        let color: Color = item.kind == .destructive ? Color.red : (item.kind == .cancel ? Color.white.opacity(0.8) : Color.cyan)
        return Button {
            item.action()
        } label: {
            Text(item.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .liquidGlass(
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                    tint: selected ? Color.cyan : nil,
                    interactive: true
                )
                .padRing(selected, cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }

    private func routeModalDirection(_ direction: ControllerMonitor.Direction) {
        if let menu = padMenu {
            switch direction {
            case .up: menuIndex = max(0, menuIndex - 1)
            case .down: menuIndex = min(menu.items.count - 1, menuIndex + 1)
            default: break
            }
            feedback()
            return
        }
        if sheet != nil {
            switch direction {
            case .up: sheetPad.send(.up)
            case .down: sheetPad.send(.down)
            case .left: sheetPad.send(.left)
            case .right: sheetPad.send(.right)
            }
        }
        // Los selectores del sistema (fotos, carpetas) no se pueden mover con el mando.
    }

    private func routeModalAccept() {
        if let menu = padMenu {
            let index = min(max(menuIndex, 0), menu.items.count - 1)
            feedback()
            menu.items[index].action()
            return
        }
        if sheet != nil { sheetPad.send(.accept) }
    }

    // MARK: - HDMI y orientación

    private func handleHDMI(_ connected: Bool) {
        hdmiTask?.cancel()
        hdmiPending = false
        if connected {
            guard hdmiAutoLandscape, !hdmiForced else { return }
            hdmiPending = true
            showToast(tr("Pantalla HDMI detectada. Activando Modo Dock…"), seconds: 3, actionTitle: tr("Cancelar")) {
                hdmiTask?.cancel()
                hdmiPending = false
            }
            hdmiTask = Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                hdmiPending = false
                hdmiForced = true
                OrientationController.apply(landscape: true)
            }
        } else {
            releaseHDMILandscape()
        }
    }

    private func releaseHDMILandscape() {
        hdmiTask?.cancel()
        hdmiPending = false
        guard hdmiForced else { return }
        hdmiForced = false
        OrientationController.apply(landscape: keepLandscape)
    }

    /// Juegos que forman parte de la navegación interna de la pantalla actual.
    /// Los filtros y la navegación principal siguen reservados a L1/R1 y L2/R2.
    private var controllerGames: [Game] {
        switch selectedSection {
        case .inicio, .busqueda: return filteredGames
        case .favoritos: return favoriteGames
        case .ajustes: return []
        }
    }

    private func moveControllerSelection(_ direction: ControllerMonitor.Direction) {
        if dockActive, selectedSection == .inicio || selectedSection == .favoritos {
            moveDockSelection(direction)
            return
        }
        if selectedSection == .ajustes {
            moveSettingsSelection(direction)
            return
        }
        if selectedSection == .busqueda, controllerSelectedArea == "alphabet" {
            moveAlphabetSelection(direction)
            return
        }
        if selectedSection == .inicio, controllerSelectedArea == "featured" {
            switch direction {
            case .down:
                controllerSelectedArea = "games"
                controllerSelectedGameID = controllerGames.first?.id
            case .left:
                if !featured.isEmpty { featuredIndex = (featuredIndex - 1 + featured.count) % featured.count }
            case .right:
                if !featured.isEmpty { featuredIndex = (featuredIndex + 1) % featured.count }
            case .up: break
            }
            feedback()
            return
        }
        // Navegación geométrica: solo se cambia de zona al llegar al borde real
        // de la cuadrícula, nunca por pulsar arriba desde cualquier fila.
        if selectedSection == .busqueda, controllerSelectedArea == "search" {
            if direction == .down {
                controllerSelectedArea = "games"
                controllerSelectedGameID = controllerGames.first?.id
                controllerSearchFocused = false
                feedback()
            }
            return
        }

        let items = controllerGames
        guard !items.isEmpty else {
            if selectedSection == .inicio, !featured.isEmpty, direction == .down {
                controllerSelectedArea = "featured"
                controllerSelectedGameID = nil
                feedback()
            }
            return
        }
        let current = items.firstIndex { $0.id == controllerSelectedGameID } ?? 0
        let landscape = UIScreen.main.bounds.width > UIScreen.main.bounds.height
        let columns = landscape ? (selectedSection == .inicio ? 3 : 4) : (compactGrid ? 3 : 2)
        let isTopRow = current < columns
        var next = current

        switch direction {
        case .left:
            next = max(0, current - 1)
        case .right:
            next = min(items.count - 1, current + 1)
        case .up:
            if isTopRow {
                if selectedSection == .inicio, !featured.isEmpty {
                    controllerSelectedArea = "featured"
                    controllerSelectedGameID = nil
                    controllerSearchFocused = false
                    feedback()
                    return
                }
                if selectedSection == .busqueda {
                    controllerSelectedArea = "search"
                    controllerSearchFocused = false
                    controllerSelectedGameID = nil
                    feedback()
                    return
                }
            } else {
                next = max(0, current - columns)
            }
        case .down:
            if current + columns < items.count {
                next = current + columns
            }
        }

        controllerSelectedArea = "games"
        controllerSelectedGameID = items[next].id
        controllerSearchFocused = false
        feedback()
    }

    private func moveAlphabetSelection(_ direction: ControllerMonitor.Direction) {
        let count = controllerAlphabet.count
        let columns = 7
        let current = min(max(controllerSelectedLetterIndex, 0), count - 1)
        var next = current
        switch direction {
        case .left: next = current % columns == 0 ? current : current - 1
        case .right: next = current % columns == columns - 1 || current + 1 >= count ? current : current + 1
        case .up: next = max(0, current - columns)
        case .down: next = min(count - 1, current + columns)
        }
        controllerSelectedLetterIndex = next
        feedback()
    }

    private func activateAlphabetSelection() {
        guard controllerAlphabet.indices.contains(controllerSelectedLetterIndex) else { return }
        let key = controllerAlphabet[controllerSelectedLetterIndex]
        switch key {
        case "⌫":
            if !controllerAlphabetSearchText.isEmpty {
                controllerAlphabetSearchText.removeLast()
            }
        case "✕":
            controllerAlphabetSearchText = ""
        default:
            controllerAlphabetSearchText += key
        }
        searchText = controllerAlphabetSearchText
        feedback()
    }

    private func activateControllerSelection() {
        if dockActive, selectedSection == .inicio || selectedSection == .favoritos {
            activateDockSelection()
            return
        }
        if selectedSection == .ajustes {
            activateSelectedSetting()
            return
        }
        if selectedSection == .inicio, controllerSelectedArea == "featured", !featured.isEmpty {
            open(featured[min(max(featuredIndex, 0), featured.count - 1)])
            return
        }
        if selectedSection == .busqueda, controllerSelectedArea == "alphabet" {
            activateAlphabetSelection()
            return
        }
        if selectedSection == .busqueda, controllerSelectedArea == "search" {
            if gamepadConnected {
                controllerSelectedArea = "alphabet"
                controllerSelectedLetterIndex = 0
            } else {
                controllerSearchFocused = true
            }
            return
        }
        guard let id = controllerSelectedGameID,
              let game = controllerGames.first(where: { $0.id == id }) else { return }
        open(game)
    }

    private func cycleSection(_ step: Int) {
        let all = DockSection.allCases
        guard let index = all.firstIndex(of: selectedSection) else { return }
        let next = all[(index + step + all.count) % all.count]
        feedback()
        withAnimation(.easeInOut(duration: 0.2)) { selectedSection = next }
    }

    private func cyclePlatform(_ step: Int) {
        let names = platforms.map(\.name)
        guard !names.isEmpty, let index = names.firstIndex(of: selectedPlatform) else {
            selectedPlatform = platforms.first?.name ?? "Todos"
            return
        }
        let next = names[(index + step + names.count) % names.count]
        feedback()
        withAnimation(.easeInOut(duration: 0.18)) { selectedPlatform = next }
    }

    /// ○ / B: cancela lo que se esté haciendo, de lo más reciente a lo más antiguo.
    /// Solo vuelve a Inicio cuando ya no queda nada que cancelar.
    private func handleControllerCancel() {
        // 1) Ventanas abiertas (la de más arriba primero).
        if showPhotoPicker { showPhotoPicker = false; return }
        if showFolderImporter { showFolderImporter = false; return }
        if showAbout || dialog != nil { closePadMenu(); return }
        if sheet != nil {
            if !sheetPad.send(.cancel) { sheet = nil }
            return
        }
        // 2) Giro a horizontal por HDMI en cuenta atrás.
        if hdmiPending {
            hdmiTask?.cancel()
            hdmiPending = false
            showToast(tr("Giro a horizontal cancelado"))
            return
        }
        // 2b) Modo Dock: sale de las opciones, los filtros o las pestañas y vuelve al carrusel.
        if dockActive, ["dockOptions", "dockChips", "dockNav"].contains(controllerSelectedArea) {
            controllerSelectedArea = "games"
            feedback()
            return
        }
        // 3) Teclado del mando: sale del teclado y deja marcada la barra de búsqueda.
        if selectedSection == .busqueda, controllerSelectedArea == "alphabet" {
            controllerSelectedArea = "search"
            feedback()
            return
        }
        // 4) Búsqueda escrita.
        if selectedSection == .busqueda, !searchText.isEmpty {
            searchText = ""
            controllerAlphabetSearchText = ""
            feedback()
            return
        }
        // 5) Filtro de plataforma.
        if (selectedSection == .inicio || selectedSection == .busqueda), selectedPlatform != "Todos" {
            withAnimation(.easeInOut(duration: 0.18)) { selectedPlatform = "Todos" }
            feedback()
            return
        }
        // 6) Nada más que cancelar: vuelve a Inicio.
        if selectedSection != .inicio {
            feedback()
            withAnimation(.easeInOut(duration: 0.2)) { selectedSection = .inicio }
        }
    }

    // MARK: - Modo Dock (carrusel en horizontal)

    private func resetControllerFocus() {
        switch selectedSection {
        case .ajustes: controllerSelectedArea = "settings"
        case .busqueda: controllerSelectedArea = gamepadConnected ? "search" : "games"
        default: controllerSelectedArea = "games"
        }
        controllerSelectedGameID = controllerGames.first?.id
    }

    /// Cruceta en el Dock. Zonas: pestañas de arriba, filtros, carrusel y opciones del juego.
    private func moveDockSelection(_ direction: ControllerMonitor.Direction) {
        switch controllerSelectedArea {
        case "dockOptions":
            switch direction {
            case .left: dockOptionIndex = max(0, dockOptionIndex - 1)
            case .right: dockOptionIndex = min(3, dockOptionIndex + 1)
            case .up, .down: controllerSelectedArea = "games"
            }
            feedback()
        case "dockChips":
            switch direction {
            case .left: cyclePlatform(-1)
            case .right: cyclePlatform(1)
            case .down:
                controllerSelectedArea = "games"
                feedback()
            case .up:
                controllerSelectedArea = "dockNav"
                feedback()
            }
        case "dockNav":
            switch direction {
            case .left: cycleSection(-1)
            case .right: cycleSection(1)
            case .down:
                controllerSelectedArea = selectedSection == .inicio ? "dockChips" : "games"
                feedback()
            case .up: break
            }
        default:
            let items = controllerGames
            guard !items.isEmpty else {
                if direction == .up {
                    controllerSelectedArea = selectedSection == .inicio ? "dockChips" : "dockNav"
                }
                return
            }
            let selectedID: String? = dockSelectedID(in: items)
            let current: Int = items.firstIndex(where: { $0.id == selectedID }) ?? 0
            switch direction {
            case .left:
                controllerSelectedArea = "games"
                controllerSelectedGameID = items[max(0, current - 1)].id
            case .right:
                controllerSelectedArea = "games"
                controllerSelectedGameID = items[min(items.count - 1, current + 1)].id
            case .up:
                controllerSelectedArea = selectedSection == .inicio ? "dockChips" : "dockNav"
            case .down:
                break
            }
            feedback()
        }
    }

    private func activateDockSelection() {
        switch controllerSelectedArea {
        case "dockOptions":
            activateDockOption(dockOptionIndex)
        case "dockChips", "dockNav":
            controllerSelectedArea = "games"
            feedback()
        default:
            guard let id = dockSelectedID(in: controllerGames),
                  let game = controllerGames.first(where: { $0.id == id }) else { return }
            self.open(game)
        }
    }

    /// △ / Y: abre o cierra las opciones del juego seleccionado.
    private func handleOptionsButton() {
        guard dockActive, selectedSection == .inicio || selectedSection == .favoritos, !controllerGames.isEmpty else { return }
        if controllerSelectedArea == "dockOptions" {
            controllerSelectedArea = "games"
        } else {
            controllerSelectedArea = "dockOptions"
            dockOptionIndex = 0
        }
        feedback()
    }

    private func activateDockOption(_ index: Int) {
        guard let id = dockSelectedID(in: controllerGames),
              let game = controllerGames.first(where: { $0.id == id }) else { return }
        switch index {
        case 0: self.open(game)
        case 1: showToast(tr("%@: próximamente", tr("Mando")))
        case 2: showToast(tr("%@: próximamente", tr("Rendimiento")))
        default:
            feedback()
            dialog = .gameOptions
        }
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
                    .buttonStyle(ControllerFocusableButtonStyle())
                    .focusable()
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

    private func screen<Content: View>(topGap: CGFloat = 8, @ViewBuilder _ content: @escaping () -> Content) -> some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Punto de anclaje en el borde superior: para volver exactamente arriba.
                    Color.clear.frame(height: 0).id("screen-top")
                    content()
                        .padding(.horizontal, 16)
                        .padding(.top, headerHeight + topGap)
                        .padding(.bottom, dockActive ? 92 : 44)
                        .reportFrame("content")
                }
            }
            .onChange(of: controllerSelectedGameID) { _, _ in scrollToSelection(proxy) }
            .onChange(of: controllerSelectedArea) { _, _ in scrollToSelection(proxy) }
            .onChange(of: controllerSelectedSettingIndex) { _, _ in scrollToSelection(proxy) }
            .reportFrame("scroll")
            .edgeFade(clear: fadeClearHeight, fade: headerHeight, bottom: Self.bottomFadeHeight)
        }
    }

    /// Lleva la pantalla hasta lo seleccionado. Si la selección está en las primeras filas
    /// (o en la parte de arriba), la pantalla sube del todo para que la interfaz quede ajustada.
    private func scrollToSelection(_ proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.2)) {
            switch controllerSelectedArea {
            case "featured", "search", "alphabet":
                proxy.scrollTo("screen-top", anchor: .top)
            case "settings":
                if controllerSelectedSettingIndex < 6 {
                    proxy.scrollTo("screen-top", anchor: .top)
                } else {
                    proxy.scrollTo("setting-\(controllerSelectedSettingIndex)", anchor: .center)
                }
            default:
                guard let id = controllerSelectedGameID else { return }
                if gameFitsFromTop(id) {
                    proxy.scrollTo("screen-top", anchor: .top)
                } else {
                    proxy.scrollTo("game-\(id)", anchor: .center)
                }
            }
        }
    }

    /// ¿Se vería entera la fila de este juego con la pantalla arriba del todo?
    private func gameFitsFromTop(_ id: String) -> Bool {
        guard let index = controllerGames.firstIndex(where: { $0.id == id }) else { return false }
        let landscape = UIScreen.main.bounds.width > UIScreen.main.bounds.height
        let columns = landscape ? (selectedSection == .inicio ? 3 : 4) : (compactGrid ? 3 : 2)
        let row = index / columns
        guard let first = frames["firstTile"], let content = frames["content"],
              let header = frames["header"], let scroll = frames["scroll"] else { return row <= 1 }
        let spacing: CGFloat = (landscape || compactGrid) ? 10 : 13
        // Dónde estaría la primera fila si la pantalla estuviera arriba del todo.
        let firstTop = header.minY + (first.minY - content.minY)
        let rowBottom = firstTop + CGFloat(row + 1) * first.height + CGFloat(row) * spacing
        return rowBottom <= scroll.maxY - 56
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
                        if selectedPlatform == "Todos" {
                            featuredPanel
                                .frame(maxWidth: geometryWidthFraction(0.34))
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeading(tr("Juegos recientes"), detail: tr("%ld elementos", filteredGames.count))
                            gameGrid(filteredGames, columns: 3, compact: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    if selectedPlatform == "Todos" {
                        featuredPanel
                    }
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
            .overlay {
                if selectedSection == .inicio && controllerSelectedArea == "featured" {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.cyan.opacity(0.98), lineWidth: 2.5)
                        .shadow(color: Color.cyan.opacity(0.72), radius: 10)
                        .allowsHitTesting(false)
                }
            }
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
                .buttonStyle(ControllerFocusableButtonStyle())
                    .focusable()
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

    private func platformFilters(compact: Bool, dock: Bool = false) -> some View {
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
                        .padding(.vertical, dock ? 8 : (compact ? 11 : 13))
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
                    .buttonStyle(ControllerFocusableButtonStyle())
                    .focusable()
                    .contentShape(Capsule())
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 12)
            .padding(.vertical, dock ? 4 : 8)
        }
        // La barra sigue a la plataforma elegida (con el mando o con el dedo).
        .scrollPosition(id: $platformScrollID, anchor: .center)
        .onChange(of: selectedPlatform) { _, value in
            withAnimation(.easeInOut(duration: 0.25)) { platformScrollID = value }
        }
        .onAppear { platformScrollID = selectedPlatform }
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
                    isControllerSelected: controllerSelectedGameID == game.id,
                    favoriteLabel: isFavorite ? tr("Quitar de favoritos") : tr("Añadir a favoritos"),
                    removeLabel: tr("Quitar de la biblioteca"),
                    onToggleFavorite: { toggleFavorite(game.id) },
                    onOpen: { open(game) },
                    onRemove: remove
                )
                .id("game-\(game.id)")
                .reportFrame("firstTile", if: game.id == items.first?.id)
            }
        }
    }

    // MARK: - Búsqueda

    private func searchContent(landscape: Bool) -> some View {
        screen {
            VStack(alignment: .leading, spacing: 18) {
                screenTitle(tr("Búsqueda"), subtitle: tr("Encuentra un juego o filtra por plataforma."))
                if gamepadConnected {
                    controllerAlphabetBar
                } else {
                    searchBar
                }
                platformFilters(compact: landscape)
                sectionHeading(tr("Resultados"), detail: tr("%ld encontrados", filteredGames.count))
                gameGrid(filteredGames, columns: landscape ? 4 : (compactGrid ? 3 : 2), compact: landscape || compactGrid)
                if filteredGames.isEmpty { emptyResults }
            }
        }
    }

    private var controllerAlphabetBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.cyan)
                Text(controllerAlphabetSearchText.isEmpty ? tr("Selecciona letras con el mando") : controllerAlphabetSearchText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(controllerAlphabetSearchText.isEmpty ? .white.opacity(0.55) : .white)
                    .lineLimit(1)
                Spacer()
                Text(tr("A/X: elegir"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.cyan.opacity(0.9))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(Array(controllerAlphabet.enumerated()), id: \.offset) { index, letter in
                    Button {
                        controllerSelectedLetterIndex = index
                        controllerSelectedArea = "alphabet"
                        activateAlphabetSelection()
                    } label: {
                        Text(letter)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(index == controllerSelectedLetterIndex && controllerSelectedArea == "alphabet" ? Color.black : Color.white)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(
                                index == controllerSelectedLetterIndex && controllerSelectedArea == "alphabet" ? Color.cyan : Color.white.opacity(0.07),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .id("alphabet-\(index)")
                }
            }
        }
        .padding(12)
        .glassCard()
        .id("alphabet-bar")
        .padRing(selectedSection == .busqueda && (controllerSelectedArea == "search" || controllerSelectedArea == "alphabet"), cornerRadius: 18)
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

    // Orden de tarjetas de Ajustes: coincide con el orden visual de las tres cuadrículas.
    private var controllerSettingTitles: [String] {
        [tr("Mandos"), tr("Vibración"), tr("Sonido al pulsar"), tr("Modo Dock"), tr("Dock con HDMI"), tr("Bloquear horizontal"), tr("Reloj 24 horas"), tr("Acerca de"),
         tr("Fondo personalizado"), tr("Idioma"), tr("Reorganizar plataformas"), tr("Cuadrícula completa"), tr("Bienvenida animada"), tr("Logo en cabecera"),
         tr("Escaneo de juegos"), tr("Vincular carpeta"), tr("Acceso directo (URL)"), tr("Juegos de ejemplo"), tr("Borrar favoritos"), tr("Quitar añadidos")]
    }

    /// Primer índice de cada sección de Ajustes: General, Apariencia y Juegos.
    private static let settingSectionStarts: [Int] = [0, 8, 14]

    /// Mueve la selección por la cuadrícula de Ajustes respetando las secciones:
    /// cada sección empieza en fila nueva, también con 3 columnas en horizontal.
    private func moveSettingsSelection(_ direction: ControllerMonitor.Direction) {
        let count: Int = controllerSettingTitles.count
        guard count > 0 else { return }
        let columns: Int = UIScreen.main.bounds.width > UIScreen.main.bounds.height ? 3 : 2
        let current: Int = min(max(controllerSelectedSettingIndex, 0), count - 1)
        let starts: [Int] = Self.settingSectionStarts.filter { $0 < count }
        let section: Int = starts.lastIndex(where: { $0 <= current }) ?? 0
        let start: Int = starts[section]
        let end: Int = section + 1 < starts.count ? starts[section + 1] : count
        let local: Int = current - start
        let column: Int = local % columns
        let lastRow: Int = (end - start - 1) / columns
        var next: Int = current
        switch direction {
        case .left:
            if column > 0 { next = current - 1 }
        case .right:
            if column < columns - 1, current + 1 < end { next = current + 1 }
        case .up:
            if local >= columns {
                next = current - columns
            } else if section > 0 {
                // Última fila de la sección anterior, en la misma columna si existe.
                let previousStart: Int = starts[section - 1]
                let previousLastRowStart: Int = previousStart + ((start - previousStart - 1) / columns) * columns
                next = min(previousLastRowStart + column, start - 1)
            }
        case .down:
            if current + columns < end {
                next = current + columns
            } else if local / columns < lastRow {
                // La última fila de la sección está incompleta: va a su último elemento.
                next = end - 1
            } else if end < count {
                let nextEnd: Int = section + 2 < starts.count ? starts[section + 2] : count
                next = min(end + column, nextEnd - 1)
            }
        }
        controllerSelectedSettingIndex = next
        controllerSelectedArea = "settings"
        feedback()
    }

    private func activateSelectedSetting() {
        switch controllerSelectedSettingIndex {
        case 0: sheet = .controllers
        case 1: hapticsEnabled.toggle()
        case 2: clickSound.toggle()
        case 3: dockModeEnabled.toggle()
        case 4: hdmiAutoLandscape.toggle()
        case 5: keepLandscape.toggle()
        case 6: clock24h.toggle()
        case 7: showAbout = true
        case 8: if customBackground == nil { showPhotoPicker = true } else { dialog = .background }
        case 9: dialog = .language
        case 10: sheet = .platformOrder
        case 11: compactGrid.toggle()
        case 12: showWelcome.toggle()
        case 13: showHeaderLogo.toggle()
        case 14: scanLibrary()
        case 15: showFolderImporter = true
        case 16: sheet = .addShortcut
        case 17: showSampleGames.toggle()
        case 18: if !favoriteNames.isEmpty { dialog = .clearFavorites }
        case 19: if !libraryGames.isEmpty { dialog = .clearLibrary }
        default: break
        }
        feedback()
    }

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
                    settingToggleCard(tr("Modo Dock"), subtitle: tr("Carrusel al girar a horizontal"), symbol: "tv.fill", tint: Color(red: 0.18, green: 0.46, blue: 1.0), isOn: $dockModeEnabled)
                    settingToggleCard(tr("Dock con HDMI"), subtitle: tr("Activa Dock y horizontal al conectar HDMI"), symbol: "display", tint: Color(red: 0.16, green: 0.82, blue: 1.0), isOn: $hdmiAutoLandscape)
                    settingToggleCard(tr("Bloquear horizontal"), subtitle: tr("Mantener la app en horizontal"), symbol: "iphone.landscape", tint: Color(red: 0.30, green: 0.60, blue: 1.0), isOn: $keepLandscape)
                    settingToggleCard(tr("Reloj 24 horas"), subtitle: tr("Formato de la hora en Dock"), symbol: "clock.fill", tint: Color(red: 0.0, green: 0.72, blue: 1.0), isOn: $clock24h)
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
        .buttonStyle(ControllerFocusableButtonStyle())
        .focusable()
        .id("setting-\(controllerSettingTitles.firstIndex(of: title) ?? -1)")
        .overlay {
            if selectedSection == .ajustes,
               controllerSelectedArea == "settings",
               controllerSettingTitles.indices.contains(controllerSelectedSettingIndex),
               controllerSettingTitles[controllerSelectedSettingIndex] == title {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.cyan.opacity(0.98), lineWidth: 2.5)
                    .shadow(color: Color.cyan.opacity(0.65), radius: 9)
                    .allowsHitTesting(false)
            }
        }
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

    // MARK: - Modo Dock: pantallas y barras

    private static let dockOptionSymbols = ["flag.checkered", "gamecontroller.fill", "bolt.fill", "gearshape.fill"]

    private func dockTopBar() -> some View {
        ZStack {
            HStack {
                HStack(spacing: 5) {
                    Text("OmniStation")
                        .foregroundStyle(.white)
                    Text("Dock")
                        .foregroundStyle(Color(red: 0.08, green: 0.68, blue: 1.0))
                }
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .tracking(-0.4)
                .lineLimit(1)
                Spacer()
                DockClock(use24h: clock24h)
            }
            HStack(spacing: 4) {
                ForEach(DockSection.allCases, id: \.self) { section in
                    dockNavItem(section)
                }
            }
            .padRing(controllerSelectedArea == "dockNav", cornerRadius: 16)
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .reportFrame("header")
    }

    private func dockNavItem(_ section: DockSection) -> some View {
        let isSelected = selectedSection == section
        return Button {
            feedback()
            withAnimation(.easeInOut(duration: 0.2)) { selectedSection = section }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: section.symbol)
                    .font(.system(size: 19, weight: .semibold))
                Text(tr(section.rawValue))
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(isSelected ? Color.cyan : Color.white.opacity(0.72))
            .frame(width: 70, height: 42)
            .shadow(color: isSelected ? Color.cyan.opacity(0.5) : Color.clear, radius: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr(section.rawValue))
    }

    /// Inicio y Favoritos en el Modo Dock: filtros, título y carrusel de juegos.
    private func dockHome() -> some View {
        GeometryReader { geometry in
            let isHome: Bool = selectedSection == .inicio
            let list: [Game] = isHome ? filteredGames : favoriteGames
            // Cabecera + filtros + título + barra inferior + separaciones.
            let filtersHeight: CGFloat = isHome ? 41 : 0
            let reserved: CGFloat = headerHeight + filtersHeight + 100
            let carouselHeight: CGFloat = max(150, geometry.size.height - reserved)
            let cardWidth: CGFloat = min(max(carouselHeight * 0.62, 100), 190)
            VStack(spacing: 6) {
                Color.clear.frame(height: headerHeight)
                if isHome {
                    platformFilters(compact: true, dock: true)
                        .padRing(controllerSelectedArea == "dockChips", cornerRadius: 22)
                }
                sectionHeading(isHome ? tr("Tu biblioteca") : tr("Tus favoritos"), detail: tr("%ld elementos", list.count))
                    .padding(.horizontal, 22)
                DockCarousel(
                    games: list,
                    selectedID: Binding<String?>(
                        get: { dockSelectedID(in: list) },
                        set: { controllerSelectedGameID = $0 }
                    ),
                    focused: gamepadConnected && controllerSelectedArea == "games",
                    favorites: favoriteNames,
                    cardWidth: cardWidth,
                    playHint: tr("Presiona ✕ para jugar"),
                    emptyText: isHome ? tr("Sin juegos en esta plataforma") : tr("Aún no hay favoritos"),
                    onOpen: { game in self.open(game) }
                )
                .frame(height: carouselHeight)
                Spacer(minLength: 0)
            }
        }
    }

    /// Juego marcado en el carrusel: el seleccionado si está en la lista, si no el primero.
    private func dockSelectedID(in list: [Game]) -> String? {
        if let id = controllerSelectedGameID, list.contains(where: { $0.id == id }) {
            return id
        }
        return list.first?.id
    }

    private var dockBottomBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 14) {
                dockHint("L1/R1", tr("Plataforma"))
                dockHint("L2/R2", tr("Pestaña"))
                dockHint("✕", tr("Jugar"))
                dockHint("△", tr("Opciones"))
                dockHint("○", tr("Atrás"))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            if (selectedSection == .inicio || selectedSection == .favoritos), !controllerGames.isEmpty {
                HStack(spacing: 10) {
                    ForEach(0..<4, id: \.self) { index in
                        dockOptionButton(index)
                    }
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private func dockHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
                )
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
        }
    }

    private func dockOptionButton(_ index: Int) -> some View {
        let focused = controllerSelectedArea == "dockOptions" && dockOptionIndex == index
        return Button {
            activateDockOption(index)
        } label: {
            Image(systemName: Self.dockOptionSymbols[index])
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(focused ? Color.cyan : Color.cyan.opacity(0.8))
                .frame(width: 38, height: 38)
                .liquidGlass(in: Circle(), tint: focused ? Color.cyan : nil, interactive: true)
                .padRing(focused, cornerRadius: 19)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Piezas sueltas

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.cyan)
            TextField(tr("Buscar juegos y plataformas…"), text: $searchText)
                .font(.system(size: 14))
                .focused($controllerSearchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(ControllerFocusableButtonStyle())
                    .focusable()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .glassCard()
        .id("search-bar")
        .overlay {
            if selectedSection == .busqueda && controllerSelectedArea == "search" {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.cyan.opacity(0.98), lineWidth: 2.5)
                    .shadow(color: Color.cyan.opacity(0.72), radius: 10)
                    .allowsHitTesting(false)
            }
        }
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
    @Environment(\.isFocused) private var isFocused
    let game: Game
    var compact: Bool = false
    var isFavorite: Bool = false
    var isControllerSelected: Bool = false
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
                        .buttonStyle(ControllerFocusableButtonStyle())
                    .focusable()
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
        .overlay {
            if isControllerSelected {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.cyan.opacity(0.98), lineWidth: 2.5)
                    .shadow(color: Color.cyan.opacity(0.72), radius: 10)
                    .padding(-2)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .focusable()
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
