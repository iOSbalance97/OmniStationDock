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
    case renameGame, achievements, buttonMap, retroAccount, libraryList, platformManager, sounds
    case installMethod, pairing, bundleID
    case jitSetup, installedApps, textEntry
    var id: Int { hashValue }
}

/// Para qué se elige una app instalada (lista de apps con JIT).
private enum AppPickerTarget: Equatable {
    case game(String)
    case armsx2
}

/// Qué texto se escribe en la ventana de texto genérica.
private enum TextEntryTarget {
    case armsx2Folder
    case armsx2Bundle
}

/// Para qué se abre el selector de fotos.
private enum PhotoPurpose: Equatable {
    case staticBackground
    case videoBackground
    case cover(String)
}

private enum SettingsDialog {
    case language, staticBackground, videoBackground, clearFavorites, clearLibrary, gameOptions
    case assignPlatform, externalFolder
    case jitEnabler, jitScript, armsx2Location, armsx2Bundle, armsx2Update
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
    // Medidas de la cabecera y del scroll: solo repintan cuando cambian de verdad.
    @StateObject private var metrics = LayoutMetrics()
    // Desplazamiento vertical: lo observa solo el título (con @State no repinta esta vista).
    @State private var scrollProgress = ScrollProgress()
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
    @AppStorage("keepLandscape") private var keepLandscape = false
    @AppStorage("hdmiAutoLandscape") private var hdmiAutoLandscape = false
    @AppStorage("appLanguage") private var appLanguage = "system"
    @AppStorage("platformOrder") private var platformOrderRaw = ""
    @AppStorage("showSampleGames") private var showSampleGames = true
    @AppStorage("libraryFolderBookmark") private var folderBookmark = Data()
    @AppStorage("libraryFolderName") private var folderName = ""
    @AppStorage("dockModeEnabled") private var dockModeEnabled = true
    @AppStorage("clock24h") private var clock24h = true
    @AppStorage("dockFullWidth") private var dockFullWidth = true
    @AppStorage("customPlatforms") private var customPlatformsRaw = ""
    @AppStorage("volumeNavigate") private var volumeNavigate = 0.5
    @AppStorage("volumeSelect") private var volumeSelect = 0.7
    @AppStorage("volumeAmbient") private var volumeAmbient = 0.3
    @AppStorage("backgroundMode") private var backgroundMode = "default"
    @AppStorage(InstallMethod.storageKey) private var installMethodRaw = ""
    @AppStorage(JITLauncher.defaultKey) private var jitByDefault = false
    @AppStorage(JITEnabler.storageKey) private var jitEnablerRaw = JITEnabler.builtIn.rawValue
    @AppStorage(ARMSX2.enabledKey) private var armsx2Enabled = true
    @AppStorage(ARMSX2.locationKey) private var armsx2LocationRaw = ""
    @AppStorage(ARMSX2.lcNameKey) private var armsx2Folder = ""
    @AppStorage(ARMSX2.bundleIDKey) private var armsx2Bundle = ""
    @AppStorage(ARMSX2.installedKey) private var armsx2Installed = ""
    @AppStorage(ARMSX2.autoCheckKey) private var armsx2AutoCheck = true
    @AppStorage(ARMSX2.autoInstallKey) private var armsx2AutoInstall = false
    @AppStorage(ARMSX2.latestTagKey) private var armsx2LatestTag = ""
    @AppStorage(ARMSX2.latestURLKey) private var armsx2LatestURL = ""

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
    // Estado de JIT en esta app (se comprueba al abrir Ajustes y al volver a la app).
    @State private var jitEnabled = false
    // Datos propios de cada juego (nombre, plataforma, logros, botones).
    @State private var gameMeta: [String: GameMeta] = [:]
    // Cambia al guardar o quitar una carátula para repintar las tarjetas.
    @State private var coverVersion = 0
    // Juego sobre el que actúan las opciones (cambiar nombre, carátula, logros…).
    @State private var editingGameID: String?
    // JIT integrado: para qué se elige una app, qué texto se escribe y avisos al volver a la app.
    @State private var appPickerTarget: AppPickerTarget = .armsx2
    @State private var textTarget: TextEntryTarget = .armsx2Folder
    @State private var jitLaunching = false
    @State private var pendingReturnMessage: String?
    @State private var armsx2Checking = false
    @State private var photoPurpose: PhotoPurpose = .staticBackground
    @State private var backgroundVideo: URL?
    // Modo Dock: rueda de opciones desplegada (con △).
    @State private var optionsExpanded = false
    // Tipo de enlace con el que se abre «Añadir acceso directo» (0 URL, 1 app iOS, 2 LiveContainer).
    @State private var shortcutMode = 0

    init() {
        let library = LibraryStore.load()
        let counts = (UserDefaults.standard.dictionary(forKey: "playCounts") as? [String: Int]) ?? [:]
        let samples = UserDefaults.standard.object(forKey: "showSampleGames") as? Bool ?? true
        let meta = GameMetaStore.load()
        let built = Self.makeLibrary(library: library, samples: samples, counts: counts, meta: meta)
        _gameMeta = State(initialValue: meta)
        _backgroundVideo = State(initialValue: BackgroundStore.videoURL)
        _libraryGames = State(initialValue: library)
        _playCounts = State(initialValue: counts)
        _games = State(initialValue: built.games)
        _featured = State(initialValue: built.featured)
        _customBackground = State(initialValue: BackgroundStore.load())
    }

    // MARK: - Datos derivados

    private static func makeLibrary(library: [LibraryGame], samples: Bool, counts: [String: Int], meta: [String: GameMeta]) -> (games: [Game], featured: [Game]) {
        let base: [Game] = (samples ? Game.samples : []) + library.map(\.asGame)
        // Los cambios del usuario (nombre, plataforma) se aplican aquí; el id no cambia nunca.
        let all: [Game] = base.map { game in GameMetaStore.apply(meta[game.id], to: game) }
        let ranked = all.enumerated().sorted { a, b in
            let countA = counts[a.element.id] ?? 0
            let countB = counts[b.element.id] ?? 0
            return countA != countB ? countA > countB : a.offset < b.offset
        }
        return (all, ranked.prefix(4).map(\.element))
    }

    private func refreshLibrary() {
        let built = Self.makeLibrary(library: libraryGames, samples: showSampleGames, counts: playCounts, meta: gameMeta)
        games = built.games
        featured = built.featured
        featuredIndex = 0
    }

    private func setLibrary(_ list: [LibraryGame]) {
        libraryGames = list
        LibraryStore.save(list)
        refreshLibrary()
    }

    /// Cambia los datos propios de un juego y repinta la biblioteca.
    private func updateMeta(_ id: String, _ change: (inout GameMeta) -> Void) {
        var meta: GameMeta = gameMeta[id] ?? GameMeta()
        change(&meta)
        if meta == GameMeta() {
            gameMeta[id] = nil
        } else {
            gameMeta[id] = meta
        }
        GameMetaStore.save(gameMeta)
        refreshLibrary()
    }

    private var editingGame: Game? {
        guard let id = editingGameID else { return nil }
        return games.first { $0.id == id }
    }

    private var editingMeta: GameMeta {
        guard let id = editingGameID else { return GameMeta() }
        return gameMeta[id] ?? GameMeta()
    }

    private func cover(for id: String) -> UIImage? {
        // Leer coverVersion hace que SwiftUI repinte cuando cambia una carátula.
        _ = coverVersion
        return CoverStore.shared.image(for: id)
    }

    private func tr(_ key: String, _ args: CVarArg...) -> String {
        let base = L10n.tr(key, appLanguage)
        return args.isEmpty ? base : String(format: base, arguments: args)
    }

    /// Vibración y sonido: `.navigate` al moverse por los menús, `.select` al elegir.
    private func feedback(_ kind: SoundKind = .select) {
        if hapticsEnabled {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        guard clickSound else { return }
        let volume: Double = kind == .navigate ? volumeNavigate : volumeSelect
        SoundManager.shared.play(kind, volume: volume)
    }

    /// Filtros de la barra: las plataformas fijas, las tuyas y, de las que reconoce la
    /// carpeta externa, solo las que tienen algún juego.
    private var platforms: [(name: String, symbol: String)] {
        let present: Set<String> = Set(games.map { $0.platform })
        let ordered: [String] = Platforms.ordered(platformOrderRaw, customRaw: customPlatformsRaw)
        let names: [String] = ordered.filter { name in
            !Platforms.isExtended(name) || present.contains(name)
        }
        let entries: [(name: String, symbol: String)] = names.map { name in
            (name: name, symbol: Platforms.symbol(for: name))
        }
        return [Platforms.todos] + entries
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

    private let controllerAlphabet: [String] = PadKeys.search

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

    // Altura del desvanecimiento inferior.
    private static let bottomFadeHeight: CGFloat = 64

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
        // En el Dock la interfaz puede ocupar todo el ancho (ajuste «Dock a pantalla completa»).
        let stretch: Edge.Set = (dock && dockFullWidth) ? .horizontal : []
        return ZStack(alignment: .top) {
            background
            screenContent(landscape: landscape, dock: dock)
            topChrome(landscape: landscape, dock: dock)
            padMenuOverlay
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: stretch)
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

    /// Con la rueda de opciones abierta, tocar en cualquier otro sitio la cierra.
    @ViewBuilder
    private func optionsDismissLayer(_ dock: Bool) -> some View {
        if dock && optionsExpanded {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture { collapseOptions() }
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
            .overlay { optionsDismissLayer(dock) }
            .overlay(alignment: .bottom) { dockBottomOverlay(dock) }
            .overlay(alignment: .bottom) { toastOverlay }
            .onPreferenceChange(FramesKey.self) { value in handleFrames(value) }
    }

    private func withPresentations<V: View>(_ view: V) -> some View {
        view
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: pickerFilter)
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
            ControllersSheet(lang: appLanguage, monitor: controllers, pad: sheetPad)
        case .platformOrder:
            PlatformOrderSheet(lang: appLanguage, orderRaw: $platformOrderRaw, pad: sheetPad)
        case .addShortcut:
            addShortcutSheet()
        case .renameGame:
            renameSheet()
        case .achievements:
            achievementsSheet()
        case .buttonMap:
            buttonMapSheet()
        case .retroAccount:
            RetroAccountSheet(lang: appLanguage, pad: sheetPad) { user in
                showToast(tr("Sesión iniciada como %@", user))
            }
        case .libraryList:
            libraryListSheet()
        case .platformManager:
            PlatformManagerSheet(lang: appLanguage, pad: sheetPad)
        case .sounds:
            SoundsSheet(lang: appLanguage, pad: sheetPad)
        case .installMethod:
            installMethodSheet()
        case .pairing:
            PairingFileSheet(lang: appLanguage, pad: sheetPad) { text in
                showToast(text)
            }
        case .bundleID:
            bundleIDSheet()
        case .jitSetup:
            JITSetupSheet(lang: appLanguage, pad: sheetPad) {
                sheet = .pairing
            }
        case .installedApps:
            installedAppsSheet()
        case .textEntry:
            textEntrySheet()
        }
    }

    private func installedAppsSheet() -> some View {
        let target: AppPickerTarget = appPickerTarget
        return InstalledAppsSheet(lang: appLanguage, pad: sheetPad, title: tr("Apps instaladas")) { app in
            pickedApp(app, for: target)
        }
    }

    private func pickedApp(_ app: DebuggableApp, for target: AppPickerTarget) {
        switch target {
        case .game(let id):
            updateMeta(id) { meta in meta.bundleID = app.bundleID }
        case .armsx2:
            armsx2Bundle = app.bundleID
        }
        showToast(tr("Bundle ID: %@", app.bundleID))
    }

    private func textEntrySheet() -> some View {
        let target: TextEntryTarget = textTarget
        let folder: Bool = target == .armsx2Folder
        let initial: String = folder ? armsx2FolderName : armsx2BundleID
        let title: String = folder ? "Carpeta en LiveContainer" : "Bundle ID de ARMSX2"
        let placeholder: String = folder ? ARMSX2.defaultLCName : ARMSX2.defaultBundleID
        return RenameGameSheet(lang: appLanguage, pad: sheetPad, initialName: initial, title: title, placeholder: placeholder, bundleMode: true) { value in
            if folder {
                armsx2Folder = value
            } else {
                armsx2Bundle = value
            }
        }
    }

    private func installMethodSheet() -> some View {
        let firstTime: Bool = installMethodRaw.isEmpty
        let current: InstallMethod? = InstallMethod(rawValue: installMethodRaw)
        return InstallMethodSheet(lang: appLanguage, pad: sheetPad, firstTime: firstTime, current: current) { method in
            chooseInstallMethod(method, firstTime: firstTime)
        }
    }

    private func chooseInstallMethod(_ method: InstallMethod, firstTime: Bool) {
        installMethodRaw = method.rawValue
        showToast(tr("Método de instalación: %@", installMethodTitle(method)))
        // Con SideStore/AltStore, la primera vez se ofrece importar el archivo de emparejamiento.
        guard firstTime, method == .sideStore, !PairingFile.exists else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            if sheet == nil { sheet = .pairing }
        }
    }

    private func installMethodTitle(_ method: InstallMethod?) -> String {
        switch method {
        case .liveContainer: return "LiveContainer"
        case .sideStore: return "SideStore / AltStore"
        case .none: return tr("Sin elegir")
        }
    }

    private func bundleIDSheet() -> some View {
        let id: String = editingGameID ?? ""
        let initial: String = editingMeta.bundleID ?? JITLauncher.bundleID(fromLink: editingGame?.launchURL) ?? ""
        return RenameGameSheet(lang: appLanguage, pad: sheetPad, initialName: initial, title: "Bundle ID para JIT", placeholder: "com.ejemplo.juego", bundleMode: true) { value in
            updateMeta(id) { meta in meta.bundleID = value.isEmpty ? nil : value }
            showToast(value.isEmpty ? tr("Bundle ID quitado") : tr("Bundle ID guardado"))
        }
    }

    private func addShortcutSheet() -> some View {
        AddShortcutSheet(lang: appLanguage, pad: sheetPad, initialMode: shortcutMode) { item, coverData in
            addShortcut(item, cover: coverData)
        }
    }

    private func renameSheet() -> some View {
        let id: String = editingGameID ?? ""
        return RenameGameSheet(lang: appLanguage, pad: sheetPad, initialName: editingGame?.name ?? "") { newName in
            updateMeta(id) { meta in meta.name = newName }
        }
    }

    private func achievementsSheet() -> some View {
        let id: String = editingGameID ?? ""
        return GameAchievementsSheet(lang: appLanguage, pad: sheetPad, gameName: editingGame?.name ?? "", platform: editingGame?.platform ?? "", initialGameID: editingMeta.raGameID) { gameID in
            updateMeta(id) { meta in meta.raGameID = gameID }
        }
    }

    private func buttonMapSheet() -> some View {
        let id: String = editingGameID ?? ""
        return ButtonMapSheet(lang: appLanguage, pad: sheetPad, gameName: editingGame?.name ?? "", initialMap: editingMeta.buttonMap ?? [:]) { map in
            updateMeta(id) { meta in meta.buttonMap = map.isEmpty ? nil : map }
        }
    }

    private func libraryListSheet() -> some View {
        LibraryListSheet(
            lang: appLanguage,
            pad: sheetPad,
            games: libraryGames,
            onRemove: { item in removeLibraryItem(item) },
            onRemoveAll: { setLibrary([]) }
        )
    }

    private func withSettingObservers<V: View>(_ view: V) -> some View {
        view
            .onChange(of: photoItem) { _, item in handlePhotoItem(item) }
            .onChange(of: showSampleGames) { _, _ in refreshLibrary() }
            .onChange(of: dialog) { _, _ in menuIndex = 0 }
            .onChange(of: showAbout) { _, _ in menuIndex = 0 }
            .onChange(of: keepLandscape) { _, value in handleKeepLandscapeChange(value) }
            .onChange(of: hdmi.isConnected) { _, connected in handleHDMI(connected) }
            .onChange(of: hdmiAutoLandscape) { _, enabled in handleHDMIAutoChange(enabled) }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                refreshJITStatus(announce: false)
                showPendingReturnMessage()
            }
    }

    private func withNavigationObservers<V: View>(_ view: V) -> some View {
        view
            .onChange(of: dockActive) { _, _ in resetControllerFocus() }
            .onChange(of: selectedSection) { _, section in handleSectionChange(section) }
            .onChange(of: selectedPlatform) { _, _ in handlePlatformChange() }
            .onChange(of: controllers.controllers.count) { _, count in handleControllerCountChange(count) }
            .onChange(of: searchText) { _, _ in handleSearchTextChange() }
            .onChange(of: volumeAmbient) { _, value in SoundManager.shared.updateAmbient(volume: value) }
    }

    // MARK: - Reacciones a cambios

    /// Medidas de pantalla: se guardan sin repintar; en iOS 17 también dan el desplazamiento.
    private func handleFrames(_ value: [String: CGRect]) {
        // Cada pantalla publica su contenido con su nombre: solo cuenta el de la activa.
        var frames: [String: CGRect] = value
        frames["content"] = value["content-" + selectedSection.rawValue]
        let offset: CGFloat? = metrics.update(frames)
        if !ScrollSupport.hasScrollGeometry, let offset {
            scrollProgress.set(offset)
        }
    }

    private func refreshJITStatus(announce: Bool) {
        jitEnabled = DebugSupport.isJITEnabled
        if announce {
            showToast(jitEnabled ? tr("JIT activo en esta app") : tr("JIT no activo en esta app"))
        }
    }

    /// Abre otra app (StikDebug, LiveContainer…) y avisa si no se puede.
    private func openExternal(_ url: URL?, failure: String) {
        guard let url else { return }
        UIApplication.shared.open(url) { success in
            if !success {
                DispatchQueue.main.async { showToast(failure) }
            }
        }
    }

    private func handlePhotoItem(_ item: PhotosPickerItem?) {
        guard let item else { return }
        let purpose: PhotoPurpose = photoPurpose
        Task { await applyPicked(item, purpose: purpose) }
    }

    /// Abre el selector de fotos para un fondo o una carátula.
    private func pickPhoto(_ purpose: PhotoPurpose) {
        photoPurpose = purpose
        showPhotoPicker = true
    }

    private var pickerFilter: PHPickerFilter {
        photoPurpose == .videoBackground ? .videos : .images
    }

    private func applyPicked(_ item: PhotosPickerItem, purpose: PhotoPurpose) async {
        switch purpose {
        case .staticBackground:
            await applyBackground(from: item)
        case .videoBackground:
            await applyVideoBackground(from: item)
        case .cover(let id):
            await applyCover(from: item, id: id)
        }
        photoItem = nil
    }

    private func applyVideoBackground(from item: PhotosPickerItem) async {
        let ext: String = item.supportedContentTypes.first?.preferredFilenameExtension ?? "mov"
        guard let data = try? await item.loadTransferable(type: Data.self),
              let url = BackgroundStore.saveVideo(data, fileExtension: ext) else {
            showToast(tr("No se pudo usar ese vídeo"))
            return
        }
        backgroundVideo = url
        backgroundMode = "video"
        showToast(tr("Fondo animado actualizado"))
    }

    private func applyCover(from item: PhotosPickerItem, id: String) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              CoverStore.shared.save(data, for: id) else {
            showToast(tr("No se pudo usar esa imagen"))
            return
        }
        coverVersion += 1
        showToast(tr("Carátula actualizada"))
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
        // La pantalla nueva empieza arriba: el título debe verse entero.
        scrollProgress.activate(section.rawValue)
        optionsExpanded = false
        if section == .inicio { refreshLibrary() }
        if section == .ajustes { refreshJITStatus(announce: false) }
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
        sheetPad.gamepadConnected = count > 0
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
        // El mando siempre maneja la interfaz.
        controllers.navigationEnabled = true
        sheetPad.gamepadConnected = gamepadConnected
        refreshJITStatus(announce: false)
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
        SoundManager.shared.updateAmbient(volume: volumeAmbient)
        askInstallMethodIfNeeded()
        if armsx2Enabled && armsx2AutoCheck && ARMSX2Updater.shouldCheck {
            checkARMSX2Update(manual: false)
        }
    }

    /// La primera vez se pregunta cómo se instaló la app (decide cómo se activa el JIT).
    private func askInstallMethodIfNeeded() {
        guard installMethodRaw.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if installMethodRaw.isEmpty && sheet == nil { sheet = .installMethod }
        }
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
                    if let activeVideo {
                        LoopingVideoBackground(url: activeVideo)
                    } else if let activeImage {
                        Image(uiImage: activeImage)
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
            backgroundMode = "static"
            showToast(tr("Fondo actualizado"))
        } else {
            showToast(tr("No se pudo usar esa imagen"))
        }
    }

    /// Vídeo de fondo en uso (si el modo animado está activo y el vídeo existe).
    private var activeVideo: URL? {
        switch backgroundMode {
        case "video": return backgroundVideo
        case "static", "original": return nil
        default: return BackgroundStore.defaultVideoURL
        }
    }

    /// Imagen propia de fondo en uso. Sin vídeo ni imagen propia se ve el original estático.
    private var activeImage: UIImage? {
        backgroundMode == "static" ? customBackground : nil
    }

    private func removeStaticBackground() {
        BackgroundStore.remove()
        customBackground = nil
        if backgroundMode == "static" { backgroundMode = "default" }
        showToast(tr("Imagen propia quitada"))
    }

    private func removeVideoBackground() {
        BackgroundStore.removeVideo()
        backgroundVideo = nil
        if backgroundMode == "video" { backgroundMode = "default" }
        showToast(tr("Vídeo propio quitado"))
    }

    private func setBackgroundMode(_ mode: String) {
        backgroundMode = mode
        closePadMenu()
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
                    .font(AppFont.text(13, .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                if let title = toast.actionTitle, let action = toast.action {
                    Button(title) {
                        action()
                        withAnimation(.easeInOut(duration: 0.25)) { self.toast = nil }
                    }
                    .font(AppFont.text(13, .bold))
                    .foregroundStyle(Color.cyan)
                    .buttonStyle(ControllerFocusableButtonStyle())
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
        case .staticBackground:
            return staticBackgroundMenu(cancel)
        case .videoBackground:
            return videoBackgroundMenu(cancel)
        case .externalFolder:
            return externalFolderMenu(cancel)
        case .assignPlatform:
            return assignPlatformMenu(cancel)
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
            return gameOptionsMenu(cancel)
        case .jitEnabler:
            return jitEnablerMenu(cancel)
        case .jitScript:
            return jitScriptMenu(cancel)
        case .armsx2Location:
            return armsx2LocationMenu(cancel)
        case .armsx2Bundle:
            return armsx2BundleMenu(cancel)
        case .armsx2Update:
            return armsx2UpdateMenu(cancel)
        }
    }

    private func jitEnablerMenu(_ cancel: PadMenuItem) -> PadMenuContent {
        let current: JITEnabler = JITEnabler(rawValue: jitEnablerRaw) ?? .builtIn
        var items: [PadMenuItem] = []
        items.append(PadMenuItem(title: checked(tr("JIT integrado (StikJIT)"), current == .builtIn)) {
            jitEnablerRaw = JITEnabler.builtIn.rawValue
            closePadMenu()
        })
        items.append(PadMenuItem(title: checked(tr("App StikDebug"), current == .stikDebug)) {
            jitEnablerRaw = JITEnabler.stikDebug.rawValue
            closePadMenu()
        })
        items.append(cancel)
        return (tr("Activador de JIT"), tr("El integrado no necesita otras apps: solo la VPN LocalDevVPN y tu archivo de emparejamiento."), items)
    }

    private func jitScriptMenu(_ cancel: PadMenuItem) -> PadMenuContent? {
        guard let game = editingGame else { return nil }
        let id: String = game.id
        let current: JITScriptChoice = JITScriptChoice(stored: gameMeta[id]?.jitScript)
        var items: [PadMenuItem] = []
        for choice in JITScriptChoice.allCases {
            items.append(PadMenuItem(title: checked(jitScriptTitle(choice), choice == current)) {
                updateMeta(id) { meta in meta.jitScript = choice == .automatic ? nil : choice.rawValue }
                closePadMenu()
            })
        }
        items.append(cancel)
        return (tr("Script JIT"), tr("Solo cuenta en iPhone con TXM (iOS 26). Automático usa el que necesita cada emulador conocido."), items)
    }

    private func jitScriptTitle(_ choice: JITScriptChoice) -> String {
        switch choice {
        case .automatic: return tr("Automático")
        case .universal: return "Universal"
        case .legacy: return "Legacy"
        case .noScript: return tr("Sin script")
        }
    }

    private func armsx2LocationMenu(_ cancel: PadMenuItem) -> PadMenuContent {
        let current: ARMSX2.Location = armsx2Location
        var items: [PadMenuItem] = []
        items.append(PadMenuItem(title: checked("LiveContainer", current == .liveContainer)) {
            armsx2LocationRaw = ARMSX2.Location.liveContainer.rawValue
            closePadMenu()
        })
        items.append(PadMenuItem(title: checked(tr("SideStore / AltStore"), current == .native)) {
            armsx2LocationRaw = ARMSX2.Location.native.rawValue
            closePadMenu()
        })
        items.append(cancel)
        return (tr("ARMSX2 instalado en"), nil, items)
    }

    private func armsx2BundleMenu(_ cancel: PadMenuItem) -> PadMenuContent {
        var items: [PadMenuItem] = []
        if usesBuiltInJIT {
            items.append(PadMenuItem(title: tr("Elegir app instalada")) {
                closePadMenu()
                appPickerTarget = .armsx2
                sheet = .installedApps
            })
        }
        items.append(PadMenuItem(title: tr("Escribir Bundle ID")) {
            closePadMenu()
            textTarget = .armsx2Bundle
            sheet = .textEntry
        })
        items.append(cancel)
        return (tr("Bundle ID de ARMSX2"), armsx2BundleID, items)
    }

    private func armsx2UpdateMenu(_ cancel: PadMenuItem) -> PadMenuContent {
        let installed: String = armsx2Installed.isEmpty ? tr("sin marcar") : ARMSX2Updater.shortName(armsx2Installed)
        let latest: String = armsx2LatestTag.isEmpty ? tr("sin comprobar") : ARMSX2Updater.shortName(armsx2LatestTag)
        let message: String = tr("Instalada: %@", installed) + "\n" + tr("Última: %@", latest)
        var items: [PadMenuItem] = []
        if !armsx2LatestURL.isEmpty {
            let title: String = armsx2LatestTag == armsx2Installed ? tr("Reinstalar") : tr("Instalar %@", latest)
            items.append(PadMenuItem(title: title) {
                closePadMenu()
                installARMSX2()
            })
        }
        items.append(PadMenuItem(title: tr("Buscar actualizaciones")) {
            closePadMenu()
            checkARMSX2Update(manual: true)
        })
        if !armsx2LatestTag.isEmpty && armsx2LatestTag != armsx2Installed {
            items.append(PadMenuItem(title: tr("Ya la tengo: marcar como instalada")) {
                armsx2Installed = armsx2LatestTag
                closePadMenu()
            })
        }
        items.append(cancel)
        return ("ARMSX2", message, items)
    }

    private typealias PadMenuContent = (title: String, message: String?, items: [PadMenuItem])

    /// Marca la opción en uso con ✓.
    private func checked(_ title: String, _ active: Bool) -> String {
        active ? "✓ " + title : title
    }

    private func staticBackgroundMenu(_ cancel: PadMenuItem) -> PadMenuContent {
        var items: [PadMenuItem] = []
        items.append(PadMenuItem(title: checked(tr("Original estático"), backgroundMode == "original")) {
            setBackgroundMode("original")
        })
        if customBackground != nil {
            items.append(PadMenuItem(title: checked(tr("Imagen propia"), backgroundMode == "static")) {
                setBackgroundMode("static")
            })
        }
        items.append(PadMenuItem(title: customBackground == nil ? tr("Elegir imagen propia") : tr("Cambiar imagen propia")) {
            closePadMenu()
            pickPhoto(.staticBackground)
        })
        if customBackground != nil {
            items.append(PadMenuItem(title: tr("Quitar imagen propia"), kind: .destructive) {
                closePadMenu()
                removeStaticBackground()
            })
        }
        items.append(cancel)
        return (tr("Fondo estático"), nil, items)
    }

    private func videoBackgroundMenu(_ cancel: PadMenuItem) -> PadMenuContent {
        let hasDefault: Bool = BackgroundStore.defaultVideoURL != nil
        let defaultTitle: String = hasDefault ? tr("Animado predeterminado") : tr("Animado predeterminado (no incluido)")
        var items: [PadMenuItem] = []
        items.append(PadMenuItem(title: checked(defaultTitle, backgroundMode == "default")) {
            setBackgroundMode("default")
        })
        if backgroundVideo != nil {
            items.append(PadMenuItem(title: checked(tr("Vídeo propio"), backgroundMode == "video")) {
                setBackgroundMode("video")
            })
        }
        items.append(PadMenuItem(title: backgroundVideo == nil ? tr("Elegir vídeo propio") : tr("Cambiar vídeo propio")) {
            closePadMenu()
            pickPhoto(.videoBackground)
        })
        if backgroundVideo != nil {
            items.append(PadMenuItem(title: tr("Quitar vídeo propio"), kind: .destructive) {
                closePadMenu()
                removeVideoBackground()
            })
        }
        items.append(cancel)
        return (tr("Fondo animado"), nil, items)
    }

    private func externalFolderMenu(_ cancel: PadMenuItem) -> PadMenuContent {
        var items: [PadMenuItem] = []
        items.append(PadMenuItem(title: tr("Volver a escanear")) {
            closePadMenu()
            scanLibrary()
        })
        items.append(PadMenuItem(title: tr("Cambiar carpeta")) {
            closePadMenu()
            showFolderImporter = true
        })
        items.append(PadMenuItem(title: tr("Desvincular carpeta"), kind: .destructive) {
            closePadMenu()
            unlinkExternalFolder()
        })
        items.append(cancel)
        return (tr("Carpeta externa"), folderName, items)
    }

    private func gameOptionsMenu(_ cancel: PadMenuItem) -> PadMenuContent? {
        guard let game = editingGame else { return nil }
        let id: String = game.id
        let isFavorite: Bool = favoriteNames.contains(id)
        var items: [PadMenuItem] = []
        items.append(PadMenuItem(title: tr("Cambiar nombre")) {
            closePadMenu()
            sheet = .renameGame
        })
        items.append(PadMenuItem(title: tr("Cambiar carátula")) {
            closePadMenu()
            pickPhoto(.cover(id))
        })
        if cover(for: id) != nil {
            items.append(PadMenuItem(title: tr("Quitar carátula"), kind: .destructive) {
                CoverStore.shared.remove(for: id)
                coverVersion += 1
                closePadMenu()
            })
        }
        items.append(PadMenuItem(title: tr("Asignar plataforma")) {
            dialog = .assignPlatform
        })
        items.append(PadMenuItem(title: isFavorite ? tr("Quitar de favoritos") : tr("Añadir a favoritos")) {
            toggleFavorite(id)
            closePadMenu()
        })
        let jitOn: Bool = wantsJIT(game)
        let jitTitle: String = jitOn ? "✓ " + tr("Abrir con JIT") : tr("Abrir con JIT")
        items.append(PadMenuItem(title: jitTitle) {
            updateMeta(id) { meta in meta.useJIT = !jitOn }
            closePadMenu()
            showToast(jitOn ? tr("Se abrirá sin JIT") : tr("Se abrirá con JIT"))
        })
        items.append(PadMenuItem(title: tr("Bundle ID para JIT")) {
            closePadMenu()
            sheet = .bundleID
        })
        if installMethodRaw == InstallMethod.sideStore.rawValue {
            if usesBuiltInJIT {
                items.append(PadMenuItem(title: tr("Elegir app instalada")) {
                    closePadMenu()
                    appPickerTarget = .game(id)
                    sheet = .installedApps
                })
            }
            let script: JITScriptChoice = JITScriptChoice(stored: gameMeta[id]?.jitScript)
            items.append(PadMenuItem(title: tr("Script JIT: %@", jitScriptTitle(script))) {
                dialog = .jitScript
            })
        }
        if game.isCustom {
            items.append(PadMenuItem(title: tr("Quitar de la biblioteca"), kind: .destructive) {
                removeGame(game)
                closePadMenu()
            })
        }
        items.append(cancel)
        return (game.name, game.platform, items)
    }

    private func assignPlatformMenu(_ cancel: PadMenuItem) -> PadMenuContent? {
        guard let game = editingGame else { return nil }
        let id: String = game.id
        var items: [PadMenuItem] = []
        for name in Platforms.movableNames(customRaw: customPlatformsRaw) {
            let title: String = name == game.platform ? "✓ " + name : name
            items.append(PadMenuItem(title: title) {
                updateMeta(id) { meta in meta.platform = name }
                closePadMenu()
            })
        }
        items.append(PadMenuItem(title: tr("Plataforma original")) {
            updateMeta(id) { meta in meta.platform = nil }
            closePadMenu()
        })
        items.append(cancel)
        return (tr("Asignar plataforma"), game.name, items)
    }

    /// Abre las opciones (cambiar nombre, carátula, plataforma, favoritos) de un juego.
    private func openGameOptions(_ id: String) {
        editingGameID = id
        feedback()
        dialog = .gameOptions
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
                        .font(AppFont.text(17, .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    if let message = menu.message {
                        Text(message)
                            .font(AppFont.text(12))
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                    padMenuList(menu.items)
                }
                .padding(18)
                .frame(maxWidth: 340)
                .glassCard(cornerRadius: 26)
                .padding(24)
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private func padMenuList(_ items: [PadMenuItem]) -> some View {
        if items.count > 7 {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    padMenuButtons(items)
                }
                .frame(height: 360)
                .onChange(of: menuIndex) { _, value in
                    withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(value, anchor: .center) }
                }
            }
        } else {
            padMenuButtons(items)
        }
    }

    private func padMenuButtons(_ items: [PadMenuItem]) -> some View {
        VStack(spacing: 8) {
            ForEach(items.indices, id: \.self) { index in
                padMenuButton(items[index], selected: index == menuIndex)
                    .id(index)
            }
        }
    }

    private func padMenuButton(_ item: PadMenuItem, selected rawSelected: Bool) -> some View {
        let selected: Bool = rawSelected && gamepadConnected
        let color: Color = item.kind == .destructive ? Color.red : (item.kind == .cancel ? Color.white.opacity(0.8) : Color.cyan)
        return Button {
            item.action()
        } label: {
            Text(item.title)
                .font(AppFont.text(15, .semibold))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .liquidGlass(
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                    tint: selected ? Color.cyan : nil,
                    interactive: true
                )
                .padRing(selected, cornerRadius: 14)
        }
        .buttonStyle(ControllerFocusableButtonStyle())
    }

    private func routeModalDirection(_ direction: ControllerMonitor.Direction) {
        if let menu = padMenu {
            switch direction {
            case .up: menuIndex = max(0, menuIndex - 1)
            case .down: menuIndex = min(menu.items.count - 1, menuIndex + 1)
            default: break
            }
            feedback(.navigate)
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
                if !featured.isEmpty {
                    let previousFeatured: Int = (featuredIndex - 1 + featured.count) % featured.count
                    withAnimation(.easeInOut(duration: 0.3)) { featuredIndex = previousFeatured }
                }
            case .right:
                if !featured.isEmpty {
                    let nextFeatured: Int = (featuredIndex + 1) % featured.count
                    withAnimation(.easeInOut(duration: 0.3)) { featuredIndex = nextFeatured }
                }
            case .up: break
            }
            feedback(.navigate)
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
        feedback(.navigate)
    }

    private func moveAlphabetSelection(_ direction: ControllerMonitor.Direction) {
        let count = controllerAlphabet.count
        let columns = PadKeys.columns
        let current = min(max(controllerSelectedLetterIndex, 0), count - 1)
        var next = current
        switch direction {
        case .left: next = current % columns == 0 ? current : current - 1
        case .right: next = current % columns == columns - 1 || current + 1 >= count ? current : current + 1
        case .up: next = max(0, current - columns)
        case .down: next = min(count - 1, current + columns)
        }
        controllerSelectedLetterIndex = next
        feedback(.navigate)
    }

    private func activateAlphabetSelection() {
        guard controllerAlphabet.indices.contains(controllerSelectedLetterIndex) else { return }
        let key: String = controllerAlphabet[controllerSelectedLetterIndex]
        var shift: Bool = false
        PadKeys.apply(key, to: &controllerAlphabetSearchText, shift: &shift, autoCapitalize: false)
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
        feedback(.navigate)
        withAnimation(.easeInOut(duration: 0.2)) { selectedSection = next }
    }

    private func cyclePlatform(_ step: Int) {
        let names = platforms.map(\.name)
        guard !names.isEmpty, let index = names.firstIndex(of: selectedPlatform) else {
            selectedPlatform = platforms.first?.name ?? "Todos"
            return
        }
        let next = names[(index + step + names.count) % names.count]
        feedback(.navigate)
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
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { optionsExpanded = false }
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

    /// Cruceta en el Dock: carrusel y rueda de opciones. Las plataformas y las pestañas
    /// solo cambian con sus botones (L1/R1 y L2/R2), nunca con la cruceta.
    private func moveDockSelection(_ direction: ControllerMonitor.Direction) {
        if controllerSelectedArea == "dockOptions" {
            switch direction {
            case .left: dockOptionIndex = max(0, dockOptionIndex - 1)
            case .right: dockOptionIndex = min(3, dockOptionIndex + 1)
            case .up, .down: collapseOptions()
            }
            feedback(.navigate)
            return
        }
        let items: [Game] = controllerGames
        guard !items.isEmpty else { return }
        let selectedID: String? = dockSelectedID(in: items)
        let current: Int = items.firstIndex(where: { $0.id == selectedID }) ?? 0
        switch direction {
        case .left:
            controllerSelectedGameID = items[max(0, current - 1)].id
        case .right:
            controllerSelectedGameID = items[min(items.count - 1, current + 1)].id
        case .up, .down:
            return
        }
        controllerSelectedArea = "games"
        feedback(.navigate)
    }

    private func activateDockSelection() {
        if controllerSelectedArea == "dockOptions" {
            activateDockOption(dockOptionIndex)
            return
        }
        guard let id = dockSelectedID(in: controllerGames),
              let game = controllerGames.first(where: { $0.id == id }) else { return }
        self.open(game)
    }

    /// △ / Y: en el carrusel del Dock despliega (o recoge) la rueda de opciones; en las
    /// cuadrículas (Búsqueda y modo normal) abre directamente las opciones del juego marcado.
    private func handleOptionsButton() {
        let carousel: Bool = dockActive && (selectedSection == .inicio || selectedSection == .favoritos)
        guard carousel else {
            openOptionsForSelectedGame()
            return
        }
        guard !controllerGames.isEmpty else { return }
        if optionsExpanded {
            collapseOptions()
        } else {
            controllerSelectedArea = "dockOptions"
            // Empieza en la rueda (la de la derecha) y se recorre hacia la izquierda.
            dockOptionIndex = 3
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { optionsExpanded = true }
        }
        feedback()
    }

    private func openOptionsForSelectedGame() {
        guard selectedSection != .ajustes, controllerSelectedArea == "games",
              let id = controllerSelectedGameID,
              controllerGames.contains(where: { $0.id == id }) else { return }
        openGameOptions(id)
    }

    private func collapseOptions() {
        controllerSelectedArea = "games"
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { optionsExpanded = false }
    }

    /// Bandera: logros. Mando: mapear botones. Rayo: próximamente. Rueda: opciones del juego.
    private func activateDockOption(_ index: Int) {
        guard let id = dockSelectedID(in: controllerGames) else { return }
        editingGameID = id
        switch index {
        case 0:
            feedback()
            sheet = .achievements
        case 1:
            feedback()
            sheet = .buttonMap
        case 2:
            showToast(tr("%@: próximamente", tr("Rendimiento")))
        default:
            if optionsExpanded {
                openGameOptions(id)
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { optionsExpanded = true }
            }
        }
    }

    // MARK: - Biblioteca: abrir, favoritos, escaneo

    private func open(_ game: Game) {
        feedback()
        playCounts[game.id, default: 0] += 1
        UserDefaults.standard.set(playCounts, forKey: "playCounts")
        if isARMSX2Game(game) {
            openInARMSX2(game)
            return
        }
        if wantsJIT(game) {
            openWithJIT(game)
            return
        }
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

    /// ¿Este juego se abre con JIT? Su propio ajuste manda; si no tiene, el ajuste general.
    private func wantsJIT(_ game: Game) -> Bool {
        gameMeta[game.id]?.useJIT ?? jitByDefault
    }

    private func openWithJIT(_ game: Game) {
        // Juego de LiveContainer: su enlace con jit=true (LiveContainer se lo pide a StikDebug).
        if let liveContainerURL = JITLauncher.liveContainerJITURL(game.launchURL) {
            showToast(tr("Abriendo con JIT…"))
            openExternal(liveContainerURL, failure: tr("No se pudo abrir LiveContainer. ¿Está instalado?"))
            return
        }
        guard let bundle = jitBundleID(game) else {
            showToast(tr("Para abrirlo con JIT, añade su Bundle ID en las opciones del juego"))
            return
        }
        if usesBuiltInJIT {
            let script: JITScriptChoice = JITScriptChoice(stored: gameMeta[game.id]?.jitScript)
            startBuiltInJIT(bundleID: bundle, script: script, name: game.name, afterMessage: nil)
            return
        }
        guard let url = JITLauncher.stikDebugJITURL(bundleID: bundle) else { return }
        if installMethodRaw == InstallMethod.sideStore.rawValue && !PairingFile.exists {
            showToast(tr("Recuerda: StikDebug necesita tu archivo de emparejamiento"))
        } else {
            showToast(tr("Abriendo con JIT…"))
        }
        openExternal(url, failure: tr("No se pudo abrir StikDebug. ¿Está instalado?"))
    }

    private func jitBundleID(_ game: Game) -> String? {
        gameMeta[game.id]?.bundleID ?? JITLauncher.bundleID(fromLink: game.launchURL)
    }

    /// SideStore/AltStore con el activador integrado (StikJIT), si este iPhone lo admite.
    private var usesBuiltInJIT: Bool {
        guard installMethodRaw == InstallMethod.sideStore.rawValue else { return false }
        let enabler: JITEnabler = JITEnabler(rawValue: jitEnablerRaw) ?? .builtIn
        return enabler == .builtIn && BuiltInJIT.isAvailable
    }

    /// Abre una app con el JIT integrado. El aviso final se ve al volver a OmniStation.
    private func startBuiltInJIT(bundleID: String, script: JITScriptChoice, name: String, afterMessage: String?) {
        if let problem = BuiltInJIT.preflightProblem(lang: appLanguage) {
            showToast(problem, seconds: 4.5)
            return
        }
        guard !jitLaunching else { return }
        jitLaunching = true
        showToast(tr("Activando JIT para %@…", name), seconds: 8)
        BuiltInJIT.launch(bundleID: bundleID, script: script, progress: { _ in }, completion: { result in
            jitLaunching = false
            switch result {
            case .success:
                pendingReturnMessage = afterMessage ?? tr("JIT activado en %@", name)
            case .failure(let error):
                let text: String = tr("No se pudo activar el JIT: %@", BuiltInJIT.message(for: error))
                pendingReturnMessage = nil
                showToast(text, seconds: 7)
            }
        })
    }

    private func showPendingReturnMessage() {
        guard let text = pendingReturnMessage else { return }
        pendingReturnMessage = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            showToast(text, seconds: 5)
        }
    }

    // MARK: - ARMSX2 (PS2)

    private var armsx2Location: ARMSX2.Location {
        if let location = ARMSX2.Location(rawValue: armsx2LocationRaw) { return location }
        return installMethodRaw == InstallMethod.sideStore.rawValue ? .native : .liveContainer
    }

    private var armsx2FolderName: String {
        armsx2Folder.isEmpty ? ARMSX2.defaultLCName : armsx2Folder
    }

    private var armsx2BundleID: String {
        armsx2Bundle.isEmpty ? ARMSX2.defaultBundleID : armsx2Bundle
    }

    /// Juegos de PS2 escaneados (sin acceso directo propio): se abren en ARMSX2.
    private func isARMSX2Game(_ game: Game) -> Bool {
        armsx2Enabled && game.platform == ARMSX2.platform && game.launchURL == nil && game.isCustom
    }

    private func openInARMSX2(_ game: Game) {
        guard let file = libraryGames.first(where: { $0.id == game.id })?.fileName else {
            showToast(tr("Vuelve a escanear la carpeta para abrir este juego en ARMSX2"), seconds: 4)
            return
        }
        switch armsx2Location {
        case .liveContainer:
            showToast(tr("Abriendo en ARMSX2 con JIT…"))
            openExternal(ARMSX2.liveContainerURL(appFolder: armsx2FolderName, fileName: file), failure: tr("No se pudo abrir LiveContainer. ¿Está instalado?"))
        case .native:
            openARMSX2Natively(file: file, name: game.name)
        }
    }

    private func openARMSX2Natively(file: String, name: String) {
        let link: URL? = URL(string: ARMSX2.gameURL(fileName: file))
        let failure: String = tr("No se pudo abrir ARMSX2. ¿Está instalado?")
        // Con StikDebug, ARMSX2 pide el JIT por su cuenta cuando no lo tiene.
        guard usesBuiltInJIT else {
            openExternal(link, failure: failure)
            return
        }
        let bundle: String = armsx2BundleID
        BuiltInJIT.isStillRunningWithJIT(bundleID: bundle) { running in
            if running {
                openExternal(link, failure: failure)
            } else {
                let after: String = tr("ARMSX2 ya tiene JIT. Vuelve aquí y pulsa %@ otra vez para arrancarlo.", name)
                startBuiltInJIT(bundleID: bundle, script: .automatic, name: "ARMSX2", afterMessage: after)
            }
        }
    }

    private func checkARMSX2Update(manual: Bool) {
        guard !armsx2Checking else { return }
        armsx2Checking = true
        Task {
            var found: ARMSX2Release? = nil
            var failed: Bool = false
            do {
                found = try await ARMSX2Updater.latest()
            } catch {
                failed = true
            }
            armsx2Checking = false
            if failed {
                if manual { showToast(tr("No se pudo consultar GitHub. ¿Hay conexión?")) }
                return
            }
            guard let release = found else {
                if manual { showToast(tr("No hay versiones de iOS publicadas")) }
                return
            }
            ARMSX2Updater.remember(release)
            armsx2LatestTag = release.tag
            armsx2LatestURL = release.ipaURL
            handleARMSX2Release(release, manual: manual)
        }
    }

    private func handleARMSX2Release(_ release: ARMSX2Release, manual: Bool) {
        let short: String = ARMSX2Updater.shortName(release.tag)
        if armsx2Installed.isEmpty {
            if manual { dialog = .armsx2Update }
            return
        }
        guard release.tag != armsx2Installed else {
            if manual { showToast(tr("ARMSX2 está al día (%@)", short)) }
            return
        }
        if armsx2AutoInstall && !manual {
            installARMSX2()
            return
        }
        if sheet == nil && dialog == nil {
            dialog = .armsx2Update
        } else {
            showToast(tr("ARMSX2 %@ disponible", short), seconds: 4)
        }
    }

    /// Manda la IPA de ARMSX2 a LiveContainer o a SideStore/AltStore para instalarla.
    private func installARMSX2() {
        guard !armsx2LatestURL.isEmpty else {
            checkARMSX2Update(manual: true)
            return
        }
        let urls: [URL] = ARMSX2.installURLs(ipa: armsx2LatestURL, location: armsx2Location)
        let tag: String = armsx2LatestTag
        openFirst(urls) { success in
            if success {
                armsx2Installed = tag
            } else {
                showToast(tr("No se pudo abrir el instalador. ¿Está instalado LiveContainer o SideStore?"), seconds: 4)
            }
        }
    }

    /// Prueba los enlaces en orden hasta que uno se abra.
    private func openFirst(_ urls: [URL], completion: @escaping (Bool) -> Void) {
        guard let first = urls.first else {
            completion(false)
            return
        }
        let rest: [URL] = Array(urls.dropFirst())
        UIApplication.shared.open(first) { success in
            DispatchQueue.main.async {
                if success {
                    completion(true)
                } else {
                    openFirst(rest, completion: completion)
                }
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

    private func addShortcut(_ item: LibraryGame, cover: Data?) {
        if let cover, CoverStore.shared.save(cover, for: item.id) {
            coverVersion += 1
        }
        addShortcut(item)
    }

    private func removeLibraryItem(_ item: LibraryGame) {
        setLibrary(libraryGames.filter { $0.id != item.id })
    }

    /// Busca los juegos iOS conocidos que hay instalados y los pone en «Juegos iOS».
    private func scanIOSGames() {
        let found: [LibraryGame] = IOSGameCatalog.installed()
        setLibrary(libraryGames.filter { $0.source != "ios" } + found)
        if found.isEmpty {
            showToast(tr("No se encontraron juegos iOS conocidos"), seconds: 3.2)
        } else {
            showToast(tr("Juegos iOS encontrados: %ld", found.count), seconds: 3.2)
        }
    }

    private func unlinkExternalFolder() {
        folderBookmark = Data()
        folderName = ""
        setLibrary(libraryGames.filter { $0.source != "scan" })
        showToast(tr("Carpeta desvinculada"))
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
            // El título y el planeta se desvanecen al deslizar; solo ellos se repintan.
            HeaderTitle(progress: scrollProgress, size: 20)
            Spacer(minLength: 6)
            HeaderPlanet(progress: scrollProgress, size: compact ? 30 : 34)
            Spacer(minLength: 6)
            tabButtons(compact: compact)
                .layoutPriority(2)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 7)
        .reportFrame("header")
    }

    /// Botones de las pestañas principales (los mismos en vertical y en el Modo Dock).
    private func tabButtons(compact: Bool) -> some View {
        HStack(spacing: 6) {
            ForEach(DockSection.allCases, id: \.self) { section in
                tabButton(section, compact: compact)
            }
        }
    }

    private func tabButton(_ section: DockSection, compact: Bool) -> some View {
        let isSelected: Bool = selectedSection == section
        let side: CGFloat = compact ? 36 : 40
        let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)
        let tint: Color? = isSelected ? Color.cyan : nil
        return Button {
            feedback()
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedSection = section
            }
        } label: {
            Image(systemName: section.symbol)
                .font(.system(size: compact ? 15 : 17, weight: .semibold))
                .foregroundStyle(isSelected ? Color.cyan : Color.white.opacity(0.76))
                .frame(width: side, height: side)
                // Todo el cuadrado recibe el toque, no solo el dibujo del icono.
                .contentShape(shape)
                .liquidGlass(in: shape, tint: tint, interactive: true)
                .overlay {
                    if isSelected {
                        shape.strokeBorder(Color.cyan.opacity(0.9), lineWidth: 1.2)
                    }
                }
                .shadow(color: isSelected ? Color.cyan.opacity(0.42) : Color.clear, radius: 12, y: 0)
        }
        .buttonStyle(ControllerFocusableButtonStyle())
        .accessibilityLabel(tr(section.rawValue))
    }

    // MARK: - Estructura común de pantallas con scroll

    private func screen<Content: View>(topGap: CGFloat = 8, @ViewBuilder _ content: @escaping () -> Content) -> some View {
        ScrollViewReader { proxy in
            followSelection(scrollBody(topGap: topGap, content), proxy: proxy)
                .reportFrame("scroll")
                .edgeFade(clear: metrics.fadeClear, fade: metrics.headerHeight, bottom: Self.bottomFadeHeight)
        }
    }

    private func scrollBody<Content: View>(topGap: CGFloat, _ content: @escaping () -> Content) -> some View {
        let owner: String = selectedSection.rawValue
        let topPadding: CGFloat = metrics.headerHeight + topGap
        let bottomPadding: CGFloat = dockActive ? 92 : 44
        return ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Punto de anclaje en el borde superior: para volver exactamente arriba.
                Color.clear.frame(height: 0).id("screen-top")
                content()
                    .padding(.horizontal, 16)
                    .padding(.top, topPadding)
                    .padding(.bottom, bottomPadding)
                    .reportFrame("content-" + owner)
                // Punto de anclaje en el borde inferior: para llegar exactamente al final.
                Color.clear.frame(height: 1).id("screen-bottom")
            }
        }
        .modifier(ScrollOffsetReader(progress: scrollProgress, owner: owner))
    }

    /// Cuando el mando cambia la selección, la pantalla se desplaza para enseñarla.
    private func followSelection<V: View>(_ view: V, proxy: ScrollViewProxy) -> some View {
        view
            .onChange(of: controllerSelectedGameID) { _, _ in scrollToSelection(proxy) }
            .onChange(of: controllerSelectedArea) { _, _ in scrollToSelection(proxy) }
            .onChange(of: controllerSelectedSettingIndex) { _, _ in scrollToSelection(proxy) }
            .onChange(of: controllerSelectedLetterIndex) { _, _ in scrollToSelection(proxy) }
    }

    /// Lleva la pantalla hasta lo seleccionado con el mando. Si está en las primeras filas
    /// (o en la parte de arriba), la pantalla sube del todo para que la interfaz quede ajustada.
    /// Sin mando no mueve nada: el dedo manda.
    private func scrollToSelection(_ proxy: ScrollViewProxy) {
        guard gamepadConnected else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            switch controllerSelectedArea {
            case "featured", "search":
                scrollToTop(proxy)
            case "alphabet":
                scrollToLetter(proxy)
            case "settings":
                scrollToSetting(proxy)
            default:
                scrollToGame(proxy)
            }
        }
    }

    /// En horizontal el teclado del mando no cabe entero: se sigue la tecla marcada.
    private func scrollToLetter(_ proxy: ScrollViewProxy) {
        if isLandscapeNow {
            proxy.scrollTo("alphabet-\(controllerSelectedLetterIndex)", anchor: .center)
        } else {
            scrollToTop(proxy)
        }
    }

    /// La fila de la tarjeta marcada siempre queda a la vista: la primera fila sube hasta
    /// arriba del todo y la última baja hasta el final.
    private func scrollToSetting(_ proxy: ScrollViewProxy) {
        let columns: Int = isLandscapeNow ? 3 : 2
        let index: Int = controllerSelectedSettingIndex
        if index < columns {
            scrollToTop(proxy)
        } else if isLastSettingRow(index, columns: columns) {
            proxy.scrollTo("screen-bottom", anchor: .bottom)
        } else {
            proxy.scrollTo("setting-\(index)", anchor: .center)
        }
    }

    private func isLastSettingRow(_ index: Int, columns: Int) -> Bool {
        let groups: [SettingGroup] = settingGroups
        guard let last = groups.last else { return false }
        let starts: [Int] = settingStarts(groups)
        let lastStart: Int = starts.last ?? 0
        let lastRowStart: Int = lastStart + ((last.items.count - 1) / columns) * columns
        return index >= lastRowStart
    }

    /// Los juegos se buscan por su identidad (la de la lista), que existe aunque la tarjeta
    /// aún no se haya dibujado: así la pantalla sigue a la selección también hacia abajo.
    private func scrollToGame(_ proxy: ScrollViewProxy) {
        guard let id = controllerSelectedGameID else { return }
        let items: [Game] = controllerGames
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let columns: Int = gameColumns
        let lastRow: Int = (items.count - 1) / columns
        let row: Int = index / columns
        // La primera fila siempre sube del todo (antes se centraba y tapaba título y plataformas).
        if row == 0 || gameFitsFromTop(id) {
            scrollToTop(proxy)
        } else if row == lastRow {
            proxy.scrollTo("screen-bottom", anchor: .bottom)
        } else {
            proxy.scrollTo(id, anchor: .center)
        }
    }

    /// Sube hasta arriba del todo. Se repite un instante después porque, con listas largas,
    /// la primera vez la posición de las filas aún es aproximada.
    private func scrollToTop(_ proxy: ScrollViewProxy) {
        proxy.scrollTo("screen-top", anchor: .top)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            guard selectionWantsTop else { return }
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo("screen-top", anchor: .top)
            }
        }
    }

    /// ¿La selección actual del mando debe ver la pantalla desde arriba?
    private var selectionWantsTop: Bool {
        switch controllerSelectedArea {
        case "featured", "search":
            return true
        case "alphabet":
            return !isLandscapeNow
        case "settings":
            return controllerSelectedSettingIndex < (isLandscapeNow ? 3 : 2)
        default:
            guard let id = controllerSelectedGameID,
                  let index = controllerGames.firstIndex(where: { $0.id == id }) else { return false }
            return index < gameColumns
        }
    }

    /// Columnas de la cuadrícula de juegos en la pantalla actual.
    private var gameColumns: Int {
        if isLandscapeNow { return selectedSection == .inicio ? 3 : 4 }
        return compactGrid ? 3 : 2
    }

    /// ¿Se vería entera la fila de este juego con la pantalla arriba del todo?
    private func gameFitsFromTop(_ id: String) -> Bool {
        guard let index = controllerGames.firstIndex(where: { $0.id == id }) else { return false }
        let landscape: Bool = isLandscapeNow
        let columns: Int = landscape ? (selectedSection == .inicio ? 3 : 4) : (compactGrid ? 3 : 2)
        let row: Int = index / columns
        let frames: [String: CGRect] = metrics.frames
        guard let first = frames["firstTile"], let content = frames["content"],
              let header = frames["header"], let scroll = frames["scroll"] else { return row <= 1 }
        let spacing: CGFloat = (landscape || compactGrid) ? 10 : 13
        // Dónde estaría la primera fila si la pantalla estuviera arriba del todo.
        let firstTop: CGFloat = header.minY + (first.minY - content.minY)
        let rowBottom: CGFloat = firstTop + CGFloat(row + 1) * first.height + CGFloat(row) * spacing
        // En el Modo Dock la barra inferior tapa más pantalla.
        let bottomMargin: CGFloat = dockActive ? 110 : 56
        return rowBottom <= scroll.maxY - bottomMargin
    }

    private func screenTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(AppFont.text(28, .bold))
            Text(subtitle)
                .font(AppFont.text(15))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    // MARK: - Inicio

    private func homeContent(landscape: Bool) -> some View {
        // Se calcula una vez por pintado (antes se recalculaba en cada uso).
        let list: [Game] = filteredGames
        let showFeatured: Bool = selectedPlatform == "Todos"
        return screen(topGap: 5) {
            VStack(alignment: .leading, spacing: landscape ? 15 : 20) {
                platformFilters(compact: landscape)

                if landscape {
                    HStack(alignment: .top, spacing: 16) {
                        if showFeatured {
                            featuredPanel
                                .frame(maxWidth: geometryWidthFraction(0.34))
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeading(tr("Juegos recientes"), detail: tr("%ld elementos", list.count))
                            gameGrid(list, columns: 3, compact: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    if showFeatured {
                        featuredPanel
                    }
                    sectionHeading(tr("Tu biblioteca"), detail: tr("%ld elementos", list.count))
                    gameGrid(list, columns: compactGrid ? 3 : 2, compact: compactGrid)
                }

                if list.isEmpty {
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
            featuredPager
                .frame(height: 190)
                .overlay(alignment: .bottomTrailing) { featuredDots }
                .padRing(featuredRingVisible, cornerRadius: 22)
        }
    }

    private var featuredRingVisible: Bool {
        gamepadConnected && selectedSection == .inicio && controllerSelectedArea == "featured"
    }

    /// Cada tarjeta es una página con sus esquinas y un hueco entre ellas; al pasar de una a otra
    /// la que sale se encoge y se desvanece, así no se ve el corte entre tarjetas.
    private var featuredPager: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 14) {
                ForEach(0..<featured.count, id: \.self) { index in
                    featuredCard(featured[index])
                        .clipShape(shape)
                        .glassRim(in: shape)
                        .containerRelativeFrame(.horizontal)
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content
                                .opacity(1 - abs(phase.value) * 0.6)
                                .scaleEffect(1 - CGFloat(abs(phase.value)) * 0.08)
                        }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
        .scrollPosition(id: featuredScrollID)
    }

    private var featuredScrollID: Binding<Int?> {
        Binding<Int?>(
            get: { featuredIndex },
            set: { newValue in
                if let newValue { featuredIndex = newValue }
            }
        )
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
        .background(Color.black.opacity(0.35), in: Capsule())
        .padding(14)
        .allowsHitTesting(false)
    }

    private func featuredCard(_ game: Game) -> some View {
        let plays: Int = playCounts[game.id] ?? 0
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
            RadialGradient(
                colors: [Color.cyan.opacity(0.32), Color.clear],
                center: .topTrailing,
                startRadius: 4,
                endRadius: 190
            )
            featuredArt(game)
            featuredText(game, plays: plays)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Con carátula: la imagen de fondo con un degradado para que el texto se lea.
    /// Sin carátula: el icono grande de la plataforma.
    @ViewBuilder
    private func featuredArt(_ game: Game) -> some View {
        if let image = cover(for: game.id) {
            Color.clear
                .overlay {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
            LinearGradient(
                colors: [Color.black.opacity(0.05), Color.black.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            Image(systemName: game.symbol)
                .font(.system(size: 82, weight: .light))
                .foregroundStyle(.white.opacity(0.15))
                .rotationEffect(.degrees(-14))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(20)
        }
    }

    private func featuredText(_ game: Game, plays: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(plays > 0 ? tr("MÁS JUGADO") : tr("DESTACADO"))
                .font(AppFont.text(9, .bold))
                .tracking(2)
                .foregroundStyle(Color.cyan)
            Text(game.name)
                .font(AppFont.text(23, .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(plays > 0 ? tr("%@ · %ld veces", game.platform, plays) : game.platform)
                .font(AppFont.text(12, .medium))
                .foregroundStyle(.white.opacity(0.68))
            Button {
                self.open(game)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                    Text(tr("Jugar"))
                }
                .font(AppFont.text(11, .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(LinearGradient(colors: [Color.blue, Color.cyan.opacity(0.78)], startPoint: .leading, endPoint: .trailing), in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(ControllerFocusableButtonStyle())
            .padding(.top, 3)
        }
        .padding(18)
        .padding(.bottom, 4)
    }

    private var emptyFeatured: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Color.cyan)
            Text(tr("Tu biblioteca está vacía"))
                .font(AppFont.text(15, .semibold))
            Text(tr("Vincula una carpeta o añade un acceso directo en Ajustes → Juegos."))
                .font(AppFont.text(12))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .glassCard(cornerRadius: 22)
    }

    /// `display`: solo enseña la plataforma `highlight` (Favoritos); no se puede tocar ni filtra nada.
    private func platformFilters(compact: Bool, dock: Bool = false, display: Bool = false, highlight: String? = nil) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(platforms, id: \.name) { platform in
                    platformChip(platform.name, symbol: platform.symbol, compact: compact, dock: dock, display: display, highlight: highlight)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 12)
            // Espacio para el brillo de la plataforma marcada (si no, se corta arriba y abajo).
            .padding(.vertical, dock ? 11 : 15)
        }
        .modifier(PlatformBarFollow(
            scrollID: $platformScrollID,
            selected: selectedPlatform,
            display: display,
            highlight: highlight
        ))
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
        // Se recupera el espacio extra: la barra ocupa lo mismo que antes.
        .padding(.vertical, -7)
    }

    private func platformChip(_ name: String, symbol: String, compact: Bool, dock: Bool, display: Bool, highlight: String?) -> some View {
        let isSelected: Bool = display ? (name == highlight) : (selectedPlatform == name)
        let tint: Color? = isSelected ? Color(red: 0.05, green: 0.45, blue: 1.0) : nil
        let verticalPadding: CGFloat = dock ? 8 : (compact ? 11 : 13)
        return Button {
            feedback()
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedPlatform = name
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                Text(platformLabel(name))
                    .font(AppFont.brand(12, .semibold))
            }
            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.78))
            .padding(.horizontal, compact ? 15 : 17)
            .padding(.vertical, verticalPadding)
            .contentShape(Capsule())
            .liquidGlass(in: Capsule(), tint: tint, interactive: true)
            .overlay {
                if isSelected {
                    Capsule().strokeBorder(Color.cyan.opacity(0.7), lineWidth: 1)
                }
            }
            .shadow(color: isSelected ? Color.cyan.opacity(0.30) : Color.clear, radius: 8)
        }
        .buttonStyle(ControllerFocusableButtonStyle())
    }

    private func sectionHeading(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(AppFont.text(21, .bold))
                .foregroundStyle(.white)
            Spacer()
            Text(detail)
                .font(AppFont.text(11, .medium))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private func gameGrid(_ items: [Game], columns: Int, compact: Bool) -> some View {
        let gridColumns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: compact ? 10 : 12), count: columns)
        // Se leen una sola vez por cuadrícula, no una vez por tarjeta.
        let favorites: Set<String> = favoriteNames
        let padSelection: String? = padSelectedGameID
        let firstID: String? = items.first?.id
        return LazyVGrid(columns: gridColumns, alignment: .leading, spacing: compact ? 10 : 13) {
            ForEach(items) { game in
                gameTile(game, compact: compact, isFavorite: favorites.contains(game.id), selected: padSelection == game.id)
                    .reportFrame("firstTile", if: game.id == firstID)
            }
        }
    }

    /// Juego marcado por el mando (sin mando no se marca ninguno).
    private var padSelectedGameID: String? {
        guard gamepadConnected, controllerSelectedArea == "games" else { return nil }
        return controllerSelectedGameID
    }

    private func gameTile(_ game: Game, compact: Bool, isFavorite: Bool, selected: Bool) -> some View {
        let remove: (() -> Void)? = game.isCustom ? { removeGame(game) } : nil
        return GameTile(
            game: game,
            compact: compact,
            isFavorite: isFavorite,
            isControllerSelected: selected,
            coverImage: cover(for: game.id),
            favoriteLabel: isFavorite ? tr("Quitar de favoritos") : tr("Añadir a favoritos"),
            removeLabel: tr("Quitar de la biblioteca"),
            optionsLabel: tr("Opciones del juego"),
            onToggleFavorite: { toggleFavorite(game.id) },
            onOpen: { self.open(game) },
            onOptions: { openGameOptions(game.id) },
            onRemove: remove
        )
    }

    // MARK: - Búsqueda

    private func searchContent(landscape: Bool) -> some View {
        let list: [Game] = filteredGames
        let columns: Int = landscape ? 4 : (compactGrid ? 3 : 2)
        return screen {
            VStack(alignment: .leading, spacing: 18) {
                screenTitle(tr("Búsqueda"), subtitle: tr("Encuentra un juego o filtra por plataforma."))
                searchInput(landscape: landscape)
                platformFilters(compact: landscape)
                sectionHeading(tr("Resultados"), detail: tr("%ld encontrados", list.count))
                gameGrid(list, columns: columns, compact: landscape || compactGrid)
                if list.isEmpty { emptyResults }
            }
        }
    }

    /// Sin mando: campo de texto normal. Con mando: teclado propio. En horizontal el teclado
    /// se queda plegado hasta pulsar ✕ (no cabe en pantalla y no debe abrirse solo al conectar).
    @ViewBuilder
    private func searchInput(landscape: Bool) -> some View {
        if !gamepadConnected {
            searchBar
        } else if landscape && controllerSelectedArea != "alphabet" {
            controllerSearchField
        } else {
            controllerAlphabetBar
        }
    }

    private var controllerSearchField: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let empty: Bool = controllerAlphabetSearchText.isEmpty
        return Button {
            controllerSelectedArea = "alphabet"
            controllerSelectedLetterIndex = 0
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.cyan)
                Text(empty ? tr("Selecciona letras con el mando") : controllerAlphabetSearchText)
                    .font(AppFont.text(14, .medium))
                    .foregroundStyle(empty ? Color.white.opacity(0.55) : Color.white)
                    .lineLimit(1)
                Spacer()
                Text(tr("✕: escribir"))
                    .font(AppFont.text(10, .semibold))
                    .foregroundStyle(Color.cyan.opacity(0.9))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(shape)
            .glassCard()
        }
        .buttonStyle(ControllerFocusableButtonStyle())
        .id("search-bar")
        .padRing(searchRingVisible, cornerRadius: 18)
    }

    private var controllerAlphabetBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.cyan)
                Text(controllerAlphabetSearchText.isEmpty ? tr("Selecciona letras con el mando") : controllerAlphabetSearchText)
                    .font(AppFont.text(14, .medium))
                    .foregroundStyle(controllerAlphabetSearchText.isEmpty ? .white.opacity(0.55) : .white)
                    .lineLimit(1)
                Spacer()
                Text(tr("A/X: elegir"))
                    .font(AppFont.text(10, .semibold))
                    .foregroundStyle(.cyan.opacity(0.9))
            }
            // Mismo teclado QWERTY (10 columnas) que recorre el mando.
            PadKeyboardView(
                keys: controllerAlphabet,
                selectedIndex: controllerSelectedArea == "alphabet" ? controllerSelectedLetterIndex : nil,
                idPrefix: "alphabet-",
                onKey: { index in
                    controllerSelectedLetterIndex = index
                    controllerSelectedArea = "alphabet"
                    activateAlphabetSelection()
                }
            )
        }
        .padding(12)
        .glassCard()
        .id("alphabet-bar")
        .padRing(alphabetRingVisible, cornerRadius: 18)
    }

    private var alphabetRingVisible: Bool {
        guard gamepadConnected, selectedSection == .busqueda else { return false }
        return controllerSelectedArea == "search" || controllerSelectedArea == "alphabet"
    }

    private var searchRingVisible: Bool {
        gamepadConnected && selectedSection == .busqueda && controllerSelectedArea == "search"
    }

    // MARK: - Favoritos

    /// En Favoritos la barra de plataformas marca la del juego seleccionado (solo a la vista).
    private var favoritesHighlight: String? {
        let list: [Game] = favoriteGames
        let id: String? = dockActive ? dockSelectedID(in: list) : padSelectedGameID
        guard let id else { return nil }
        return list.first { $0.id == id }?.platform
    }

    private func favoritesContent(landscape: Bool) -> some View {
        let list: [Game] = favoriteGames
        let columns: Int = landscape ? 4 : (compactGrid ? 3 : 2)
        let highlight: String? = favoritesHighlight
        return screen {
            VStack(alignment: .leading, spacing: 18) {
                screenTitle(tr("Favoritos"), subtitle: tr("Tus juegos marcados con estrella."))
                platformFilters(compact: landscape, display: true, highlight: highlight)

                if list.isEmpty {
                    emptyFavorites
                } else {
                    sectionHeading(tr("Tus favoritos"), detail: tr("%ld elementos", list.count))
                    gameGrid(list, columns: columns, compact: landscape || compactGrid)
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

    // MARK: - Ajustes (generados desde una lista)
    // Las tarjetas, el orden del mando y lo que hace cada una salen de la misma lista:
    // así no pueden desincronizarse al añadir o quitar ajustes.

    private var settingGroups: [SettingGroup] {
        [generalSettings, appearanceSettings, gameSettings, armsx2Settings, debugSettings, liveContainerSettings]
    }

    private var allSettingItems: [SettingItem] {
        settingGroups.flatMap { $0.items }
    }

    /// Posición (en la lista completa) de la primera tarjeta de cada grupo.
    private func settingStarts(_ groups: [SettingGroup]) -> [Int] {
        var starts: [Int] = []
        var next: Int = 0
        for group in groups {
            starts.append(next)
            next += group.items.count
        }
        return starts
    }

    private func toggleSetting(_ id: String, _ title: String, _ subtitle: String, _ symbol: String, _ tint: Color, _ binding: Binding<Bool>) -> SettingItem {
        SettingItem(id: id, title: title, subtitle: subtitle, symbol: symbol, tint: tint, control: .toggle(binding.wrappedValue), action: {
            binding.wrappedValue.toggle()
        })
    }

    private var generalSettings: SettingGroup {
        let count: Int = controllers.controllers.count
        let countColor: Color = count == 0 ? Color.gray : Color.green
        var items: [SettingItem] = []
        items.append(SettingItem(id: "controllers", title: tr("Mandos"), subtitle: controllersSubtitle, symbol: "gamecontroller.fill", tint: SettingTint.sky, control: .badge("\(count)", countColor), action: {
            sheet = .controllers
        }))
        items.append(toggleSetting("haptics", tr("Vibración"), tr("Respuesta háptica al tocar"), "iphone.radiowaves.left.and.right", SettingTint.sky, $hapticsEnabled))
        items.append(toggleSetting("sound", tr("Sonido al pulsar"), tr("Sonidos de navegación y selección"), "speaker.wave.2.fill", SettingTint.periwinkle, $clickSound))
        items.append(toggleSetting("dock", tr("Modo Dock"), tr("Carrusel al girar a horizontal"), "tv.fill", SettingTint.blue, $dockModeEnabled))
        items.append(toggleSetting("hdmi", tr("Dock con HDMI"), tr("Activa Dock y horizontal al conectar HDMI"), "display", SettingTint.aqua, $hdmiAutoLandscape))
        items.append(toggleSetting("dockFull", tr("Dock a pantalla completa"), tr("Usa todo el ancho en horizontal"), "arrow.left.and.right", SettingTint.sky, $dockFullWidth))
        items.append(toggleSetting("landscape", tr("Bloquear horizontal"), tr("Mantener la app en horizontal"), "iphone.landscape", SettingTint.periwinkle, $keepLandscape))
        items.append(toggleSetting("clock", tr("Reloj 24 horas"), tr("Formato de la hora en Dock"), "clock.fill", SettingTint.sky, $clock24h))
        items.append(SettingItem(id: "about", title: tr("Acerca de"), subtitle: tr("Versión %@", appVersion), symbol: "info.circle.fill", tint: Color.cyan, control: .symbol("chevron.right"), action: {
            showAbout = true
        }))
        return SettingGroup(id: "general", title: tr("General"), items: items)
    }

    private var appearanceSettings: SettingGroup {
        let staticActive: Bool = backgroundMode == "original" || backgroundMode == "static"
        let videoActive: Bool = !staticActive
        let imageControl: SettingControl = staticActive ? SettingControl.badge("ON", Color.cyan) : SettingControl.plain
        let videoControl: SettingControl = videoActive ? SettingControl.badge("ON", Color.cyan) : SettingControl.plain
        let staticSubtitle: String = backgroundMode == "static" ? tr("Imagen propia") : tr("Original estático")
        let videoSubtitle: String = backgroundMode == "video" ? tr("Vídeo propio") : tr("Predeterminado")
        var items: [SettingItem] = []
        items.append(SettingItem(id: "videoBackground", title: tr("Fondo animado"), subtitle: videoSubtitle, symbol: "play.rectangle.fill", tint: SettingTint.violet, control: videoControl, action: {
            dialog = .videoBackground
        }))
        items.append(SettingItem(id: "staticBackground", title: tr("Fondo estático"), subtitle: staticSubtitle, symbol: "photo.on.rectangle", tint: SettingTint.blue, control: imageControl, action: {
            dialog = .staticBackground
        }))
        items.append(SettingItem(id: "sounds", title: tr("Sonidos"), subtitle: tr("Volumen e importación"), symbol: "speaker.wave.3.fill", tint: SettingTint.aqua, control: .symbol("chevron.right"), action: {
            sheet = .sounds
        }))
        items.append(SettingItem(id: "language", title: tr("Idioma"), subtitle: languageLabel, symbol: "globe", tint: SettingTint.sky, control: .symbol("chevron.up.chevron.down"), action: {
            dialog = .language
        }))
        items.append(SettingItem(id: "platformOrder", title: tr("Reorganizar plataformas"), subtitle: tr("Orden de los filtros"), symbol: "arrow.up.arrow.down", tint: SettingTint.periwinkle, control: .symbol("chevron.right"), action: {
            sheet = .platformOrder
        }))
        items.append(SettingItem(id: "platforms", title: tr("Añadir plataforma"), subtitle: tr("Crea tus propias plataformas"), symbol: "plus.square.on.square", tint: SettingTint.aqua, control: .symbol("plus"), action: {
            sheet = .platformManager
        }))
        items.append(toggleSetting("grid", tr("Cuadrícula completa"), tr("Más juegos por pantalla"), "square.grid.3x3.fill", Color.cyan, $compactGrid))
        items.append(toggleSetting("welcome", tr("Bienvenida animada"), tr("Pantalla de inicio al abrir"), "sparkles", SettingTint.periwinkle, $showWelcome))
        return SettingGroup(id: "appearance", title: tr("Apariencia"), items: items)
    }

    private var gameSettings: SettingGroup {
        let linked: Bool = !folderName.isEmpty
        let iosCount: Int = libraryGames.filter { $0.source == "ios" }.count
        let favoriteCount: Int = favoriteNames.count
        let libraryCount: Int = libraryGames.count
        let raConfigured: Bool = RetroAchievements.isLoggedIn
        let raSubtitle: String = raConfigured ? tr("Sesión: %@", RetroAchievements.username) : tr("Iniciar sesión")
        let raControl: SettingControl = raConfigured ? SettingControl.badge("ON", Color.green) : SettingControl.symbol("chevron.right")
        let folderControl: SettingControl = folderSettingControl(linked: linked)
        var items: [SettingItem] = []
        items.append(SettingItem(id: "scanIOS", title: tr("Escaneo de juegos"), subtitle: tr("Juegos instalados en el iPhone"), symbol: "apps.iphone", tint: SettingTint.sky, control: .badge("\(iosCount)", Color.cyan), action: {
            scanIOSGames()
        }))
        items.append(SettingItem(id: "folder", title: tr("Carpeta externa"), subtitle: linked ? folderName : tr("ROMs de todas las plataformas"), symbol: "externaldrive.fill", tint: SettingTint.periwinkle, control: folderControl, action: {
            if folderName.isEmpty { showFolderImporter = true } else { dialog = .externalFolder }
        }))
        items.append(SettingItem(id: "shortcut", title: tr("Acceso directo (URL)"), subtitle: tr("Abre un juego, app o emulador"), symbol: "link.badge.plus", tint: SettingTint.blue, control: .symbol("plus"), action: {
            shortcutMode = 0
            sheet = .addShortcut
        }))
        items.append(SettingItem(id: "achievements", title: tr("Logros"), subtitle: raSubtitle, symbol: "trophy.fill", tint: Color.yellow, control: raControl, action: {
            sheet = .retroAccount
        }))
        items.append(toggleSetting("samples", tr("Juegos de ejemplo"), tr("Mostrar los de demostración"), "square.stack.3d.up.fill", SettingTint.aqua, $showSampleGames))
        items.append(SettingItem(id: "clearFavorites", title: tr("Borrar favoritos"), subtitle: tr("Quita todos los marcados"), symbol: "star.slash.fill", tint: Color.orange, control: .badge("\(favoriteCount)", Color.orange), action: {
            if !favoriteNames.isEmpty { dialog = .clearFavorites }
        }))
        items.append(SettingItem(id: "library", title: tr("Juegos añadidos"), subtitle: tr("Ver y quitar uno a uno"), symbol: "list.bullet.rectangle.fill", tint: Color.orange, control: .badge("\(libraryCount)", Color.orange), action: {
            sheet = .libraryList
        }))
        return SettingGroup(id: "games", title: tr("Juegos"), items: items)
    }

    private func folderSettingControl(linked: Bool) -> SettingControl {
        if isScanning { return SettingControl.progress }
        if linked { return SettingControl.badge("\(scannedCount)", Color.green) }
        return SettingControl.plain
    }

    private var armsx2Settings: SettingGroup {
        let location: ARMSX2.Location = armsx2Location
        let hasUpdate: Bool = !armsx2LatestTag.isEmpty && armsx2LatestTag != armsx2Installed && !armsx2Installed.isEmpty
        var items: [SettingItem] = []
        items.append(toggleSetting("armsx2On", tr("PS2 con ARMSX2"), tr("Abre los juegos de PS2 escaneados"), "playstation.logo", SettingTint.blue, $armsx2Enabled))
        let whereText: String = location == .liveContainer ? "LiveContainer" : tr("SideStore / AltStore")
        items.append(SettingItem(id: "armsx2Where", title: tr("ARMSX2 instalado en"), subtitle: whereText, symbol: "shippingbox.fill", tint: SettingTint.blue, control: .symbol("chevron.right"), action: {
            dialog = .armsx2Location
        }))
        if location == .liveContainer {
            items.append(SettingItem(id: "armsx2Folder", title: tr("Carpeta en LiveContainer"), subtitle: armsx2FolderName, symbol: "folder.fill", tint: SettingTint.blue, control: .symbol("pencil"), action: {
                textTarget = .armsx2Folder
                sheet = .textEntry
            }))
        } else {
            items.append(SettingItem(id: "armsx2Bundle", title: tr("Bundle ID de ARMSX2"), subtitle: armsx2BundleID, symbol: "number", tint: SettingTint.blue, control: .symbol("pencil"), action: {
                dialog = .armsx2Bundle
            }))
        }
        items.append(SettingItem(id: "armsx2Version", title: tr("Versión de ARMSX2"), subtitle: armsx2VersionSubtitle, symbol: "arrow.triangle.2.circlepath", tint: SettingTint.blue, control: armsx2VersionControl(hasUpdate), action: {
            dialog = .armsx2Update
        }))
        items.append(toggleSetting("armsx2Check", tr("Buscar versiones nuevas"), tr("Al abrir la app"), "bell.badge.fill", SettingTint.blue, $armsx2AutoCheck))
        items.append(toggleSetting("armsx2AutoInstall", tr("Instalar sin preguntar"), tr("Abre el instalador al detectarla"), "square.and.arrow.down.fill", SettingTint.blue, $armsx2AutoInstall))
        return SettingGroup(id: "armsx2", title: "ARMSX2 (PS2)", isSubsection: true, items: items)
    }

    private var armsx2VersionSubtitle: String {
        if armsx2LatestTag.isEmpty { return tr("Sin comprobar") }
        let latest: String = ARMSX2Updater.shortName(armsx2LatestTag)
        if armsx2Installed.isEmpty { return tr("Última: %@", latest) }
        if armsx2Installed == armsx2LatestTag { return tr("Al día: %@", latest) }
        return tr("Nueva: %@", latest)
    }

    private func armsx2VersionControl(_ hasUpdate: Bool) -> SettingControl {
        if armsx2Checking { return SettingControl.progress }
        if hasUpdate { return SettingControl.badge(tr("NUEVA"), Color.green) }
        return SettingControl.symbol("chevron.right")
    }

    private var debugSettings: SettingGroup {
        let method: InstallMethod? = InstallMethod(rawValue: installMethodRaw)
        let jitControl: SettingControl = jitEnabled ? .badge("ON", Color.green) : .badge("OFF", Color.gray)
        let stikFailure: String = tr("No se pudo abrir StikDebug. ¿Está instalado?")
        var items: [SettingItem] = []
        items.append(SettingItem(id: "installMethod", title: tr("Método de instalación"), subtitle: installMethodTitle(method), symbol: method?.symbol ?? "questionmark.app.fill", tint: SettingTint.violet, control: .symbol("chevron.right"), action: {
            sheet = .installMethod
        }))
        items.append(toggleSetting("jitDefault", tr("JIT al abrir juegos"), tr("Para los juegos sin ajuste propio"), "bolt.circle.fill", SettingTint.violet, $jitByDefault))
        if method == .sideStore {
            items.append(jitEnablerSettingItem())
            if usesBuiltInJIT {
                items.append(SettingItem(id: "jitSetup", title: tr("JIT integrado"), subtitle: tr("Preparar y comprobar"), symbol: "bolt.shield.fill", tint: SettingTint.violet, control: .symbol("chevron.right"), action: {
                    sheet = .jitSetup
                }))
            }
            items.append(pairingSettingItem())
        }
        items.append(SettingItem(id: "jitStatus", title: tr("Estado JIT"), subtitle: jitEnabled ? tr("Activo en esta app") : tr("No activo en esta app"), symbol: "cpu", tint: SettingTint.violet, control: jitControl, action: {
            refreshJITStatus(announce: true)
        }))
        items.append(SettingItem(id: "enableJIT", title: tr("Activar JIT"), subtitle: tr("Con StikDebug, en esta app"), symbol: "bolt.fill", tint: SettingTint.violet, control: .symbol("arrow.up.forward"), action: {
            openExternal(DebugSupport.enableJITURL, failure: stikFailure)
        }))
        items.append(SettingItem(id: "openStik", title: tr("Abrir StikDebug"), subtitle: tr("Emparejamiento y scripts JIT"), symbol: "ladybug.fill", tint: SettingTint.violet, control: .symbol("arrow.up.forward"), action: {
            openExternal(DebugSupport.stikDebugURL, failure: stikFailure)
        }))
        items.append(SettingItem(id: "copyBundle", title: tr("Copiar Bundle ID"), subtitle: DebugSupport.bundleID, symbol: "doc.on.doc.fill", tint: SettingTint.violet, control: .plain, action: {
            UIPasteboard.general.string = DebugSupport.bundleID
            showToast(tr("Bundle ID copiado"))
        }))
        return SettingGroup(id: "debug", title: tr("Depuración"), items: items)
    }

    private func jitEnablerSettingItem() -> SettingItem {
        let current: JITEnabler = JITEnabler(rawValue: jitEnablerRaw) ?? .builtIn
        let subtitle: String = current == .builtIn ? tr("JIT integrado (StikJIT)") : tr("App StikDebug")
        let unavailable: Bool = current == .builtIn && !BuiltInJIT.isAvailable
        let control: SettingControl = unavailable ? .badge(tr("NO"), Color.orange) : .symbol("chevron.right")
        return SettingItem(id: "jitEnabler", title: tr("Activador de JIT"), subtitle: subtitle, symbol: "bolt.horizontal.fill", tint: SettingTint.violet, control: control, action: {
            dialog = .jitEnabler
        })
    }

    private func pairingSettingItem() -> SettingItem {
        let ready: Bool = PairingFile.exists
        let control: SettingControl = ready ? .badge("OK", Color.green) : .badge(tr("FALTA"), Color.orange)
        let subtitle: String = ready ? tr("Importado") : tr("Importar para SideStore/AltStore")
        return SettingItem(id: "pairing", title: tr("Archivo de emparejamiento"), subtitle: subtitle, symbol: "key.fill", tint: SettingTint.violet, control: control, action: {
            sheet = .pairing
        })
    }

    private var liveContainerSettings: SettingGroup {
        let inside: Bool = DebugSupport.isInsideLiveContainer
        let statusText: String = inside ? tr("Dentro de LiveContainer") : tr("Fuera de LiveContainer")
        let statusControl: SettingControl = inside ? .badge(tr("SÍ"), Color.green) : .badge(tr("NO"), Color.gray)
        var items: [SettingItem] = []
        items.append(SettingItem(id: "lcStatus", title: tr("Estado"), subtitle: statusText, symbol: "shippingbox.fill", tint: SettingTint.aqua, control: statusControl, action: {
            showToast(statusText)
        }))
        items.append(SettingItem(id: "lcOpen", title: tr("Abrir LiveContainer"), subtitle: tr("Abre la app de LiveContainer"), symbol: "square.stack.3d.up.fill", tint: SettingTint.aqua, control: .symbol("arrow.up.forward"), action: {
            openExternal(DebugSupport.liveContainerURL, failure: tr("No se pudo abrir LiveContainer. ¿Está instalado?"))
        }))
        items.append(SettingItem(id: "lcGame", title: tr("Juego de LiveContainer"), subtitle: tr("Acceso directo a una app de LiveContainer"), symbol: "plus.app.fill", tint: SettingTint.aqua, control: .symbol("plus"), action: {
            shortcutMode = 2
            sheet = .addShortcut
        }))
        return SettingGroup(id: "livecontainer", title: "LiveContainer", isSubsection: true, items: items)
    }

    /// Mueve la selección por la cuadrícula de Ajustes respetando los grupos:
    /// cada grupo empieza en fila nueva, también con 3 columnas en horizontal.
    private func moveSettingsSelection(_ direction: ControllerMonitor.Direction) {
        let groups: [SettingGroup] = settingGroups
        let starts: [Int] = settingStarts(groups)
        let count: Int = groups.reduce(0) { total, group in total + group.items.count }
        guard count > 0, !starts.isEmpty else { return }
        let columns: Int = isLandscapeNow ? 3 : 2
        let current: Int = min(max(controllerSelectedSettingIndex, 0), count - 1)
        let section: Int = starts.lastIndex(where: { $0 <= current }) ?? 0
        let start: Int = starts[section]
        let end: Int = section + 1 < starts.count ? starts[section + 1] : count
        let local: Int = current - start
        let column: Int = local % columns
        let lastRow: Int = (end - start - 1) / columns
        var target: Int = current
        switch direction {
        case .left:
            if column > 0 { target = current - 1 }
        case .right:
            if column < columns - 1, current + 1 < end { target = current + 1 }
        case .up:
            if local >= columns {
                target = current - columns
            } else if section > 0 {
                // Última fila del grupo anterior, en la misma columna si existe.
                let previousStart: Int = starts[section - 1]
                let previousLastRowStart: Int = previousStart + ((start - previousStart - 1) / columns) * columns
                target = min(previousLastRowStart + column, start - 1)
            }
        case .down:
            if current + columns < end {
                target = current + columns
            } else if local / columns < lastRow {
                // La última fila del grupo está incompleta: va a su último elemento.
                target = end - 1
            } else if end < count {
                let nextEnd: Int = section + 2 < starts.count ? starts[section + 2] : count
                target = min(end + column, nextEnd - 1)
            }
        }
        controllerSelectedSettingIndex = target
        controllerSelectedArea = "settings"
        feedback(.navigate)
    }

    private func activateSelectedSetting() {
        let items: [SettingItem] = allSettingItems
        guard items.indices.contains(controllerSelectedSettingIndex) else { return }
        runSetting(items[controllerSelectedSettingIndex])
    }

    private func runSetting(_ item: SettingItem) {
        feedback()
        item.action()
    }

    private func settingsContent(landscape: Bool) -> some View {
        let groups: [SettingGroup] = settingGroups
        let starts: [Int] = settingStarts(groups)
        return screen {
            VStack(alignment: .leading, spacing: 14) {
                screenTitle(tr("Ajustes"), subtitle: tr("Personaliza tu experiencia."))
                    .padding(.bottom, 4)
                ForEach(groups.indices, id: \.self) { groupIndex in
                    settingsSection(groups[groupIndex], start: starts[groupIndex], landscape: landscape)
                }
            }
        }
    }

    private func settingsSection(_ group: SettingGroup, start: Int, landscape: Bool) -> some View {
        let columns: Int = landscape ? 3 : 2
        let rows: [[Int]] = settingRows(count: group.items.count, columns: columns)
        return VStack(alignment: .leading, spacing: 12) {
            settingsHeader(group.title, subsection: group.isSubsection)
            ForEach(rows.indices, id: \.self) { rowIndex in
                settingsRow(group, offsets: rows[rowIndex], start: start, columns: columns)
            }
        }
    }

    /// Filas de tarjetas (índices dentro del grupo).
    private func settingRows(count: Int, columns: Int) -> [[Int]] {
        stride(from: 0, to: count, by: columns).map { first in
            Array(first..<min(first + columns, count))
        }
    }

    private func settingsRow(_ group: SettingGroup, offsets: [Int], start: Int, columns: Int) -> some View {
        let empty: Int = max(0, columns - offsets.count)
        return HStack(alignment: .top, spacing: 12) {
            ForEach(offsets, id: \.self) { offset in
                settingCard(group.items[offset], index: start + offset)
            }
            ForEach(0..<empty, id: \.self) { _ in
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: 1)
            }
        }
    }

    private func isSettingSelected(_ index: Int) -> Bool {
        guard gamepadConnected, selectedSection == .ajustes, controllerSelectedArea == "settings" else { return false }
        return controllerSelectedSettingIndex == index
    }

    private func settingCard(_ item: SettingItem, index: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return Button {
            runSetting(item)
        } label: {
            settingCardLabel(item)
                .contentShape(shape)
        }
        .buttonStyle(TapHighlightButtonStyle(cornerRadius: 18))
        .id("setting-\(index)")
        .padRing(isSettingSelected(index), cornerRadius: 18)
    }

    /// Tarjeta de ajuste: icono arriba, control a la derecha (interruptor, etiqueta...) y texto debajo.
    private func settingCardLabel(_ item: SettingItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Image(systemName: item.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(item.tint)
                    .frame(width: 40, height: 40)
                    .background(item.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Spacer(minLength: 4)
                settingControl(item.control)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(AppFont.text(14, .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(item.subtitle)
                    .font(AppFont.text(11))
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

    @ViewBuilder
    private func settingControl(_ control: SettingControl) -> some View {
        switch control {
        case .toggle(let isOn):
            Toggle("", isOn: .constant(isOn))
                .labelsHidden()
                .tint(Color.cyan)
                .fixedSize()
                .allowsHitTesting(false)
        case .badge(let text, let color):
            settingBadge(text, tint: color)
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.45))
        case .progress:
            ProgressView()
                .tint(Color.cyan)
        case .plain:
            EmptyView()
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

    private func settingsHeader(_ title: String, subsection: Bool = false) -> some View {
        Text(title.uppercased())
            .font(AppFont.text(subsection ? 11 : 12, .bold))
            .tracking(1.6)
            .foregroundStyle(Color.cyan.opacity(subsection ? 0.6 : 0.85))
            .padding(.top, subsection ? 2 : 8)
            .padding(.leading, 2)
    }

    private func settingBadge(_ text: String, tint: Color = Color.cyan) -> some View {
        Text(text)
            .font(AppFont.text(9, .bold))
            .tracking(0.6)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.14), in: Capsule())
    }

    // MARK: - Modo Dock: pantallas y barras

    private static let dockOptionSymbols = ["flag.checkered", "gamecontroller.fill", "bolt.fill", "gearshape.fill"]

    private func dockTopBar() -> some View {
        // Los dos lados ocupan lo mismo: las pestañas quedan centradas y el nombre
        // se ajusta a su mitad sin montarse encima de ellas en pantallas más estrechas.
        HStack(spacing: 12) {
            BrandTitle(size: 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            // Las mismas pestañas que en vertical.
            tabButtons(compact: false)
                .padding(5)
                .padRing(gamepadConnected && controllerSelectedArea == "dockNav", cornerRadius: 18)
                .fixedSize()
            DockStatus(use24h: clock24h)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, dockFullWidth ? 34 : 22)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .reportFrame("header")
    }

    /// Inicio y Favoritos en el Modo Dock: filtros, título y carrusel de juegos.
    /// Las dos pantallas reservan el mismo hueco para los filtros, así las tarjetas miden lo mismo.
    private func dockHome() -> some View {
        GeometryReader { geometry in
            let isHome: Bool = selectedSection == .inicio
            let list: [Game] = isHome ? filteredGames : favoriteGames
            let header: CGFloat = metrics.headerHeight
            // Cabecera + filtros + título de sección + barra inferior.
            let reserved: CGFloat = header + 40 + 30 + 62
            let carouselHeight: CGFloat = max(150, geometry.size.height - reserved)
            // La portada ocupa todo el alto que dejan el nombre y la indicación de debajo.
            let coverHeight: CGFloat = carouselHeight - DockCarousel.textHeight
            let cardWidth: CGFloat = min(max(coverHeight / DockCarousel.coverRatio, 90), 230)
            VStack(spacing: 0) {
                Color.clear.frame(height: header)
                dockFilters(isHome: isHome)
                    .frame(height: 40)
                sectionHeading(isHome ? tr("Tu biblioteca") : tr("Tus favoritos"), detail: tr("%ld elementos", list.count))
                    .padding(.horizontal, 22)
                    .frame(height: 30)
                dockCarousel(list, isHome: isHome, cardWidth: cardWidth)
                    .frame(height: carouselHeight)
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private func dockFilters(isHome: Bool) -> some View {
        if isHome {
            platformFilters(compact: true, dock: true)
        } else {
            platformFilters(compact: true, dock: true, display: true, highlight: favoritesHighlight)
        }
    }

    private func dockCarousel(_ list: [Game], isHome: Bool, cardWidth: CGFloat) -> some View {
        let carouselKey: String = isHome ? "inicio|" + selectedPlatform : "favoritos"
        return DockCarousel(
            games: list,
            selectedID: Binding<String?>(
                get: { dockSelectedID(in: list) },
                set: { controllerSelectedGameID = $0 }
            ),
            focused: gamepadConnected && controllerSelectedArea == "games",
            favorites: favoriteNames,
            cardWidth: cardWidth,
            coverVersion: coverVersion,
            playHint: tr("Presiona ✕ para jugar"),
            emptyText: isHome ? tr("Sin juegos en esta plataforma") : tr("Aún no hay favoritos"),
            favoriteLabel: tr("Añadir a favoritos"),
            onOpen: { game in self.open(game) },
            onToggleFavorite: { game in toggleFavorite(game.id) },
            onSwipe: { feedback(.navigate) }
        )
        // Un carrusel nuevo por pestaña y plataforma: siempre empieza centrado.
        .id(carouselKey)
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
                dockOptionsWheel
            }
        }
        .padding(.horizontal, dockFullWidth ? 34 : 22)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background { dockBarBackground }
    }

    /// Sombra de la barra inferior: sube desde abajo y se desvanece por los dos lados
    /// (antes terminaba en seco a izquierda y derecha).
    private var dockBarBackground: some View {
        LinearGradient(
            colors: [Color.black.opacity(0), Color.black.opacity(0.6)],
            startPoint: .top,
            endPoint: .bottom
        )
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.12),
                    .init(color: .black, location: 0.88),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .ignoresSafeArea(edges: [.bottom, .horizontal])
    }

    private func dockHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 6) {
            Text(key)
                .font(AppFont.text(10, .bold))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
                )
            Text(label)
                .font(AppFont.text(12, .medium))
                .foregroundStyle(.white.opacity(0.75))
        }
    }

    /// Recogida: solo la rueda. Con △ (o tocándola) se despliega hacia la izquierda.
    private var dockOptionsWheel: some View {
        HStack(spacing: 10) {
            if optionsExpanded {
                ForEach(0..<3, id: \.self) { index in
                    dockOptionButton(index)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            dockOptionButton(3)
                .rotationEffect(.degrees(optionsExpanded ? 90 : 0))
        }
    }

    private func dockOptionButton(_ index: Int) -> some View {
        let focused: Bool = gamepadConnected && controllerSelectedArea == "dockOptions" && dockOptionIndex == index
        return Button {
            activateDockOption(index)
        } label: {
            Image(systemName: Self.dockOptionSymbols[index])
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(focused ? Color.cyan : Color.cyan.opacity(0.8))
                .frame(width: 38, height: 38)
                .contentShape(Circle())
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
                .font(AppFont.text(14))
                .focused($controllerSearchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(ControllerFocusableButtonStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .glassCard()
        .id("search-bar")
        .padRing(searchRingVisible, cornerRadius: 18)
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
                    .font(AppFont.text(13, .semibold))
                Text(tr("Estos son juegos de ejemplo. Vincula una carpeta o añade accesos directos en Ajustes → Juegos."))
                    .font(AppFont.text(11))
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
    var isControllerSelected: Bool = false
    var coverImage: UIImage? = nil
    var favoriteLabel: String = ""
    var removeLabel: String = ""
    var optionsLabel: String = ""
    var onToggleFavorite: () -> Void = {}
    var onOpen: () -> Void = {}
    var onOptions: () -> Void = {}
    var onRemove: (() -> Void)? = nil

    private static let tileShape = RoundedRectangle(cornerRadius: 18, style: .continuous)
    private static let coverShape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    var body: some View {
        // Un botón de verdad: se remarca al tocar y no necesita el foco de iOS.
        Button(action: onOpen) {
            tileContent
        }
        .buttonStyle(TapHighlightButtonStyle(cornerRadius: 18))
        .padRing(isControllerSelected, cornerRadius: 18)
        .contextMenu {
            Button(action: onOptions) {
                Label(optionsLabel, systemImage: "slider.horizontal.3")
            }
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

    private var tileContent: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            cover
            Text(game.name)
                .font(AppFont.text(compact ? 11 : 12, .semibold))
                .tracking(0.1)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.white.opacity(0.95))
                .frame(maxWidth: .infinity, minHeight: compact ? 28 : 30, alignment: .topLeading)
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { tileBackground }
        .glassRim(in: Self.tileShape)
        .contentShape(Self.tileShape)
    }

    /// Cristal ligero: relleno translúcido y borde de luz, sin desenfoques
    /// (con muchas tarjetas, el desenfoque de cada una hacía que deslizar fuera a tirones).
    private var tileBackground: some View {
        Self.tileShape.fill(
            LinearGradient(
                colors: [Color.white.opacity(0.10), Color.blue.opacity(0.05), Color.black.opacity(0.22)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var cover: some View {
        ZStack {
            coverArt
            coverBadges
        }
        .frame(height: compact ? 90 : 118)
        .clipShape(Self.coverShape)
        .overlay { Self.coverShape.strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5) }
    }

    /// La carátula si la hay; si no, el degradado con el icono de la plataforma.
    @ViewBuilder
    private var coverArt: some View {
        if let coverImage {
            // Color.clear marca el tamaño; la imagen lo rellena sin agrandar la tarjeta.
            Color.clear
                .overlay {
                    Image(uiImage: coverImage)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
        } else {
            LinearGradient(
                colors: [game.tint.opacity(0.76), Color(red: 0.015, green: 0.055, blue: 0.14).opacity(0.94), Color(red: 0.003, green: 0.012, blue: 0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color.cyan.opacity(0.16), Color.clear],
                center: .topTrailing,
                startRadius: 2,
                endRadius: compact ? 70 : 95
            )
            Image(systemName: game.symbol)
                .font(.system(size: compact ? 27 : 34, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
        }
    }

    private var coverBadges: some View {
        VStack {
            HStack {
                Text(game.platform)
                    .font(AppFont.text(9, .bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.38), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5))
                Spacer()
                favoriteButton
            }
            Spacer()
        }
        .padding(8)
    }

    private var favoriteButton: some View {
        let side: CGFloat = compact ? 24 : 28
        return Button(action: onToggleFavorite) {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.system(size: compact ? 11 : 13, weight: .bold))
                .foregroundStyle(isFavorite ? Color.yellow : Color.white.opacity(0.85))
                .frame(width: side, height: side)
                .background(Color.black.opacity(0.38), in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(ControllerFocusableButtonStyle())
        .accessibilityLabel(favoriteLabel)
    }
}

// MARK: - Título de la interfaz

/// «OmniStation Dock» en Orbitron, en un solo texto para que encoja de forma uniforme.
struct BrandTitle: View {
    var size: CGFloat

    private var title: AttributedString {
        var first = AttributedString("OmniStation ")
        first.foregroundColor = Color.white
        var second = AttributedString("Dock")
        second.foregroundColor = Color(red: 0.08, green: 0.68, blue: 1.0)
        return first + second
    }

    var body: some View {
        Text(title)
            .font(AppFont.brand(size, .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .shadow(color: Color.cyan.opacity(0.12), radius: 8, y: 0)
    }
}

/// Título de la cabecera: se desvanece y sube un poco al deslizar.
/// Es una vista aparte para que solo ella se repinte con el desplazamiento.
private struct HeaderTitle: View {
    @ObservedObject var progress: ScrollProgress
    var size: CGFloat

    /// Puntos de scroll en los que el título termina de desvanecerse.
    private static let collapseDistance: CGFloat = 36

    var body: some View {
        let hidden: CGFloat = min(1, progress.offset / Self.collapseDistance)
        return BrandTitle(size: size)
            .opacity(1 - hidden)
            .offset(y: -10 * hidden)
            .scaleEffect(1 - 0.06 * hidden, anchor: .leading)
    }
}

/// La barra de plataformas sigue a la elegida (o, en Favoritos, a la del juego marcado).
private struct PlatformBarFollow: ViewModifier {
    @Binding var scrollID: String?
    let selected: String
    let display: Bool
    let highlight: String?

    func body(content: Content) -> some View {
        content
            .scrollPosition(id: $scrollID, anchor: .center)
            .onChange(of: selected) { _, value in
                follow(value, enabled: !display)
            }
            .onChange(of: highlight) { _, value in
                follow(value, enabled: display)
            }
            .onAppear {
                scrollID = display ? (highlight ?? Platforms.todos.name) : selected
            }
            .allowsHitTesting(!display)
    }

    private func follow(_ value: String?, enabled: Bool) {
        guard enabled, let value else { return }
        withAnimation(.easeInOut(duration: 0.25)) { scrollID = value }
    }
}

/// Planeta en el centro de la cabecera (solo en vertical): transparente, deja ver el fondo,
/// y se desvanece igual que el título al deslizar.
private struct HeaderPlanet: View {
    @ObservedObject var progress: ScrollProgress
    var size: CGFloat

    private static let collapseDistance: CGFloat = 36

    var body: some View {
        let hidden: CGFloat = min(1, progress.offset / Self.collapseDistance)
        return Image("WelcomePlanet")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .shadow(color: Color.cyan.opacity(0.35), radius: 8)
            .opacity(1 - hidden)
            .offset(y: -10 * hidden)
            .scaleEffect(1 - 0.1 * hidden)
            .accessibilityHidden(true)
    }
}

// MARK: - Tipos de los Ajustes

/// Lo que se ve a la derecha del icono en cada tarjeta de ajuste.
private enum SettingControl {
    case toggle(Bool)
    case badge(String, Color)
    case symbol(String)
    case progress
    case plain
}

private struct SettingItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let control: SettingControl
    let action: () -> Void
}

private struct SettingGroup: Identifiable {
    let id: String
    let title: String
    var isSubsection: Bool = false
    let items: [SettingItem]
}

private enum SettingTint {
    static let sky = Color(red: 0.0, green: 0.72, blue: 1.0)
    static let blue = Color(red: 0.18, green: 0.46, blue: 1.0)
    static let periwinkle = Color(red: 0.30, green: 0.60, blue: 1.0)
    static let aqua = Color(red: 0.16, green: 0.82, blue: 1.0)
    static let violet = Color(red: 0.55, green: 0.42, blue: 1.0)
}

#Preview {
    HomeView()
}
