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

/// Ventanas de la pantalla principal. Las que dependen de algo lo llevan dentro (así la ventana
/// nunca abre con los datos de la vez anterior: SwiftUI puede pintarla antes de ver otro @State).
private enum HomeSheet: Identifiable, Hashable {
    case controllers, platformOrder, addShortcut
    case renameGame, achievements, buttonMap, retroAccount, libraryList, platformManager, sounds
    case installMethod, pairing, bundleID
    case jitSetup, installedApps, emulatorSetup
    case textEntry(TextEntryTarget)
    case emulatorConfig(EmuConfigTarget, String?)
    case switchAddons(String)
    var id: Int { hashValue }
}

/// Partes de Ajustes (con el mando, L1/R1 cambia de una a otra).
private enum SettingsCategory: String, CaseIterable {
    case general, library, emulators, system

    var title: String {
        switch self {
        case .general: return "General"
        case .library: return "Biblioteca"
        case .emulators: return "Emuladores"
        case .system: return "Sistema"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .library: return "books.vertical.fill"
        case .emulators: return "cpu.fill"
        case .system: return "bolt.shield.fill"
        }
    }
}

/// Para qué se elige una app instalada (lista de apps con JIT).
private enum AppPickerTarget: Equatable {
    case game(String)
    case emulator(Emulator)
}

/// Qué texto se escribe en la ventana de texto genérica.
private enum TextEntryTarget: Hashable {
    case lcFolder(Emulator)
    case bundle(Emulator)
    case steamGridKey
    /// Cómo se llama el juego en su emulador (id del juego en OmniStation).
    case emulatorGame(String)
}

/// Para qué se abre el selector de Archivos.
private enum ImporterPurpose: Equatable {
    case folder
    case cover(String)
    /// BIOS del núcleo integrado de ARMSX2.
    case coreBIOS
    /// Juegos para ARMSX2/Juegos.
    case coreGames
    /// MeloNX integrado: claves (prod.keys), firmware y juegos para MeloNX/Juegos.
    case melonxKeys
    case melonxFirmware
    case melonxGames
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
    case jitEnabler, jitScript, emulatorLocation, emulatorBundle, emulatorUpdate, emulatorFolder, emulatorHelp
    case coverOptions
    case armsx2Mode, armsx2CoreGames, armsx2CoreHelp, armsx2CoreFlavor
    case melonxMode, melonxCoreGames, melonxCoreHelp, memoryHelp
    case retroSystem
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
    @AppStorage("libraryFolderBookmark") private var folderBookmark = Data()
    @AppStorage("libraryFolderName") private var folderName = ""
    @AppStorage("dockModeEnabled") private var dockModeEnabled = true
    @AppStorage("clock24h") private var clock24h = true
    @AppStorage("dockFullWidth") private var dockFullWidth = true
    @AppStorage("customPlatforms") private var customPlatformsRaw = ""
    @AppStorage(Platforms.hiddenKey) private var hiddenPlatformsRaw = ""
    @AppStorage(Platforms.shownKey) private var shownPlatformsRaw = ""
    @AppStorage("volumeNavigate") private var volumeNavigate = 0.5
    @AppStorage("volumeSelect") private var volumeSelect = 0.7
    @AppStorage("volumeAmbient") private var volumeAmbient = 0.3
    @AppStorage("backgroundMode") private var backgroundMode = "default"
    @AppStorage(InstallMethod.storageKey) private var installMethodRaw = ""
    /// PS2: app ARMSX2 aparte («external») o núcleo integrado («integrated»).
    @AppStorage(ARMSX2Mode.storageKey) private var armsx2ModeRaw = ARMSX2Mode.external.rawValue
    @AppStorage(ARMSX2CoreFolders.touchAlwaysKey) private var armsx2TouchAlways = false
    /// Núcleo de ARMSX2 integrado: el de NeoStation o el compilado por OmniStation.
    @AppStorage("armsx2CoreFlavor") private var armsx2CoreFlavorRaw = "neostation"
    /// Switch: app MeloNX aparte («external») o MeloNX integrado («integrated»).
    @AppStorage(MeloNXMode.storageKey) private var melonxModeRaw = MeloNXMode.external.rawValue
    /// Durante una partida de un núcleo integrado, el juego va a pantalla completa en la tele.
    @AppStorage("tvGameOutput") private var tvGameOutput = true
    /// Mando táctil de MeloNX integrado siempre a la vista (aunque haya mando físico).
    @AppStorage(MeloNXCoreFolders.touchAlwaysKey) private var melonxTouchAlways = false
    /// Firmware de Switch instalado (se lee al abrir sus ajustes).
    @State private var melonxFirmware = ""
    @AppStorage(JITEnabler.storageKey) private var jitEnablerRaw = JITEnabler.builtIn.rawValue
    @AppStorage("emulatorSetupDone") private var emulatorSetupDone = false
    @AppStorage("closeAfterLaunch") private var closeAfterLaunch = true
    @AppStorage(CoverDownloader.enabledKey) private var autoCoversEnabled = true

    // Dispositivos
    @StateObject private var controllers = ControllerMonitor()
    @StateObject private var hdmi = HDMIMonitor()
    @ObservedObject private var jitStatus = JITStatusCenter.shared
    /// Partida de un núcleo integrado en marcha: la interfaz de detrás se para.
    @ObservedObject private var activity = EmulationActivity.shared

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
    /// Sistema libretro del menú abierto (Ajustes → Emuladores → el sistema).
    @State private var activeRetroSystem: RetroSystem = .nes
    @AppStorage("retroTouchAlways") private var retroTouchAlways = false
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
    @State private var appPickerTarget: AppPickerTarget = .emulator(.armsx2)
    // Emulador sobre el que actúan los menús de Ajustes y carpeta que se está eligiendo.
    @State private var activeEmulator: Emulator = .armsx2
    @State private var folderPickEmulator: Emulator?
    // Cambia al tocar los ajustes de un emulador, para repintar Ajustes.
    @State private var emulatorRevision = 0
    @State private var checkingEmulators: Set<String> = []
    @State private var downloadingCovers = false
    /// Para qué se abre el selector de Archivos (carpetas, una carátula o archivos del núcleo).
    @State private var importerPurpose: ImporterPurpose = .folder
    /// Juegos de Switch cuya carátula se pidió a MeloNX a mano: se sustituye aunque fuera propia.
    @State private var forcedCoverIDs: Set<String> = []
    /// Ya hay una petición de biblioteca (MeloNX o ARMSX2) a punto de abrirse.
    @State private var libraryRequestScheduled = false
    /// Pantalla del juego abierta (antes de jugar) y qué marca en ella el mando.
    @State private var detailGameID: String?
    @State private var detailFocus: GameDetailFocus = .play
    @State private var detailShowDescription = false
    @State private var jitLaunching = false
    @State private var pendingReturnMessage: String?
    @State private var photoPurpose: PhotoPurpose = .staticBackground
    @State private var backgroundVideo: URL?
    // Modo Dock: rueda de opciones desplegada (con △).
    @State private var optionsExpanded = false
    // Tipo de enlace con el que se abre «Añadir acceso directo» (0 URL, 1 app iOS, 2 LiveContainer).
    @State private var shortcutMode = 0
    /// Parte de Ajustes que se ve.
    @State private var settingsCategory: SettingsCategory = .general

    init() {
        let library = LibraryStore.load()
        let counts = (UserDefaults.standard.dictionary(forKey: "playCounts") as? [String: Int]) ?? [:]
        let meta = GameMetaStore.load()
        let built = Self.makeLibrary(library: library, counts: counts, meta: meta)
        _gameMeta = State(initialValue: meta)
        _backgroundVideo = State(initialValue: BackgroundStore.videoURL)
        _libraryGames = State(initialValue: library)
        _playCounts = State(initialValue: counts)
        _games = State(initialValue: built.games)
        _featured = State(initialValue: built.featured)
        _customBackground = State(initialValue: BackgroundStore.load())
    }

    // MARK: - Datos derivados

    private static func makeLibrary(library: [LibraryGame], counts: [String: Int], meta: [String: GameMeta]) -> (games: [Game], featured: [Game]) {
        let combined: [Game] = library.map(\.asGame)
        // Un mismo juego puede venir de dos carpetas: se queda solo una vez.
        var seen: Set<String> = []
        let base: [Game] = combined.filter { seen.insert($0.id).inserted }
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
        // Cada modo de ARMSX2 enseña solo sus juegos: los de la app aparte o los del núcleo.
        let integrated: Bool = armsx2Integrated
        let switchIntegrated: Bool = melonxIntegrated
        let visible: [LibraryGame] = libraryGames.filter { item in
            if item.source == ARMSX2CoreFolders.source { return integrated }
            if item.source == "emu:" + Emulator.armsx2.rawValue { return !integrated }
            if item.source == MeloNXCoreFolders.source { return switchIntegrated }
            if item.source == "emu:" + Emulator.melonx.rawValue { return !switchIntegrated }
            return true
        }
        let built = Self.makeLibrary(library: visible, counts: playCounts, meta: gameMeta)
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
    /// Un solo generador de vibración (crear uno en cada movimiento también costaba).
    private static let haptic = UIImpactFeedbackGenerator(style: .light)

    private func feedback(_ kind: SoundKind = .select) {
        if hapticsEnabled {
            Self.haptic.impactOccurred()
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
        let hidden: Set<String> = Platforms.hidden(hiddenPlatformsRaw)
        let shown: Set<String> = Platforms.hidden(shownPlatformsRaw)
        let names: [String] = ordered.filter { name in
            Platforms.isVisible(name, hidden: hidden, shown: shown, present: present)
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
            detailOverlay(landscape: landscape, dock: dock)
            // Los menús (opciones del juego…) siempre por encima de la pantalla del juego.
            padMenuOverlay
                .zIndex(10)
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
        if dock && detailGame == nil {
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
            .fileImporter(isPresented: $showFolderImporter, allowedContentTypes: importerTypes, allowsMultipleSelection: importerMultiple) { result in
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
            PlatformOrderSheet(lang: appLanguage, orderRaw: $platformOrderRaw, pad: sheetPad, present: Set(games.map(\.platform)))
        case .addShortcut:
            addShortcutSheet()
        case .renameGame:
            renameSheet()
        case .switchAddons(let gameID):
            SwitchAddonsSheet(
                lang: appLanguage,
                pad: sheetPad,
                gameName: games.first(where: { $0.id == gameID })?.name ?? "",
                baseTitleID: switchTitleID(gameID),
                integrated: libraryGames.first(where: { $0.id == gameID })?.source == MeloNXCoreFolders.source
            )
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
        case .textEntry(let target):
            textEntrySheet(target)
        case .emulatorConfig(let emulator, let gameID):
            EmulatorConfigSheet(lang: appLanguage, emulator: emulator, gameID: gameID,
                                gameName: gameID.flatMap { id in games.first(where: { $0.id == id })?.name },
                                pad: sheetPad)
                .onDisappear { emulatorRevision += 1 }
        case .emulatorSetup:
            EmulatorSetupSheet(lang: appLanguage, pad: sheetPad, installMethod: installMethodRaw, integrated: integratedEmulators, retroFolders: retroSystems.map(\.folderName), onScanLiveContainer: { emulator in
                scanEmulator(emulator, silent: false)
            }, onFolder: { emulator, url in
                linkEmulatorFolder(emulator, url: url)
            }, onFinish: {
                emulatorSetupDone = true
                emulatorRevision += 1
            })
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
        case .emulator(let emulator):
            EmulatorStore.setBundleID(app.bundleID, emulator)
            emulatorRevision += 1
        }
        showToast(tr("Bundle ID: %@", app.bundleID))
    }

    private func textEntrySheet(_ target: TextEntryTarget) -> some View {
        if case .emulatorGame(let id) = target {
            return AnyView(emulatorGameSheet(id))
        }
        if target == .steamGridKey {
            // La clave es texto libre (32 letras y números): se acepta tal cual, también vacía.
            return AnyView(RenameGameSheet(lang: appLanguage, pad: sheetPad, initialName: SteamGridDB.apiKey,
                                           title: "Clave de SteamGridDB", placeholder: "API key", bundleMode: true,
                                           acceptAnything: true) { value in
                SteamGridDB.setAPIKey(value)
                emulatorRevision += 1
                showToast(value.isEmpty ? tr("Clave de SteamGridDB quitada") : tr("Clave guardada: los fondos se buscarán en alta calidad"), seconds: 3.5)
            })
        }
        return AnyView(emulatorTextSheet(target))
    }

    /// Título exacto o Title ID del juego en MeloNX (vacío = automático).
    private func emulatorGameSheet(_ id: String) -> some View {
        let game: Game? = games.first { $0.id == id }
        let initial: String = gameMeta[id]?.emulatorGameID ?? game?.name ?? ""
        return RenameGameSheet(lang: appLanguage, pad: sheetPad, initialName: initial, title: "Nombre en el emulador", placeholder: "Title ID / título") { value in
            updateMeta(id) { meta in
                meta.emulatorGameID = value.isEmpty ? nil : value
                // Un título (no un Title ID) pasa a ser también el nombre en OmniStation.
                if !value.isEmpty && !Emulator.isTitleID(value) { meta.name = value }
            }
        }
    }

    private func emulatorTextSheet(_ target: TextEntryTarget) -> some View {
        let title: String
        let placeholder: String
        let initial: String
        let emulator: Emulator
        switch target {
        case .lcFolder(let value):
            emulator = value
            title = "Carpeta en LiveContainer"
            placeholder = value.defaultLCFolder
            initial = EmulatorStore.lcFolder(value)
        case .bundle(let value):
            emulator = value
            title = "Bundle ID del emulador"
            placeholder = value.defaultBundleID
            initial = EmulatorStore.bundleID(value)
        case .emulatorGame, .steamGridKey:
            // Se atienden en textEntrySheet.
            emulator = .melonx
            title = ""
            placeholder = ""
            initial = ""
        }
        return RenameGameSheet(lang: appLanguage, pad: sheetPad, initialName: initial, title: title, placeholder: placeholder, bundleMode: true) { value in
            switch target {
            case .lcFolder: EmulatorStore.setLCFolder(value, emulator)
            case .bundle: EmulatorStore.setBundleID(value, emulator)
            case .emulatorGame, .steamGridKey: break
            }
            emulatorRevision += 1
        }
    }

    /// Solo informa del método detectado. La primera vez, al continuar sigue la configuración.
    private func installMethodSheet() -> some View {
        let firstTime: Bool = !emulatorSetupDone
        return InstallMethodSheet(lang: appLanguage, pad: sheetPad, firstTime: firstTime) {
            continueAfterInstallInfo(firstTime: firstTime)
        }
    }

    private func continueAfterInstallInfo(firstTime: Bool) {
        // Con SideStore/AltStore, la primera vez se ofrece importar el archivo de emparejamiento.
        guard firstTime else { return }
        let method: InstallMethod = InstallMethod.detected
        let next: HomeSheet = method == .sideStore && !PairingFile.exists ? .pairing : .emulatorSetup
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            if sheet == nil { sheet = next }
        }
    }

    /// El método de instalación lo decide la app: se guarda siempre el detectado.
    private func syncInstallMethod() {
        let detected: String = InstallMethod.detected.rawValue
        guard installMethodRaw != detected else { return }
        installMethodRaw = detected
        if usesBuiltInJIT { jitStatus.autoPrepare() }
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
            .onReceive(IncomingLinks.shared.$url) { url in
                guard let url else { return }
                IncomingLinks.shared.url = nil
                handleIncomingLink(url)
            }
            .onChange(of: dialog) { _, _ in menuIndex = 0 }
            .onChange(of: showAbout) { _, _ in menuIndex = 0 }
            .onChange(of: keepLandscape) { _, value in handleKeepLandscapeChange(value) }
            .onChange(of: hdmi.isConnected) { _, connected in handleHDMI(connected) }
            .onChange(of: hdmiAutoLandscape) { _, enabled in handleHDMIAutoChange(enabled) }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                refreshJITStatus(announce: false)
                showPendingReturnMessage()
                if usesBuiltInJIT { jitStatus.autoPrepare() }
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
            .onChange(of: hiddenPlatformsRaw) { _, _ in handleHiddenPlatformsChange() }
    }

    /// Si se oculta la plataforma elegida, la barra vuelve a «Todos».
    private func handleHiddenPlatformsChange() {
        guard selectedPlatform != "Todos" else { return }
        if Platforms.hidden(hiddenPlatformsRaw).contains(selectedPlatform) {
            selectedPlatform = "Todos"
        }
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

    /// Carátula elegida en Archivos.
    private func applyCoverFile(_ result: Result<[URL], Error>, id: String) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let accessing: Bool = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), CoverStore.shared.save(data, for: id) else {
            showToast(tr("No se pudo usar esa imagen"))
            return
        }
        AutoCovers.unmark(id)
        coverVersion += 1
        showToast(tr("Carátula actualizada"))
    }

    /// Title ID de un juego de Switch: el del nombre del archivo ([0100…]) o el emparejado con MeloNX.
    private func switchTitleID(_ id: String) -> String? {
        let file: String = libraryGames.first(where: { $0.id == id })?.fileName ?? ""
        if let titleID = Emulator.titleID(in: file) { return titleID }
        if let saved = gameMeta[id]?.emulatorGameID, Emulator.isTitleID(saved) { return saved }
        // El que se leyó del propio archivo al escanear (ticket del .nsp).
        return SwitchAddonStore.shared.titleID(for: id)
    }

    /// «Descargar» en Cambiar carátula: busca la carátula de ese juego ahora mismo.
    private func downloadCover(for game: Game) {
        // Switch con MeloNX instalado aparte: su icono sale de la lista de MeloNX.
        if game.platform == Emulator.melonx.platform, EmulatorStore.isEnabled(.melonx),
           EmulatorStore.location(.melonx, installMethod: installMethodRaw) == .native {
            forcedCoverIDs.insert(game.id)
            requestMeloNXLibrary()
            return
        }
        // El resto (también Switch dentro de LiveContainer): libretro, la eShop por el Title ID
        // o la portada de Wikipedia.
        let id: String = game.id
        let name: String = game.name
        let platform: String = game.platform
        let file: String? = libraryGames.first(where: { $0.id == id })?.fileName
        let titleID: String? = switchTitleID(id)
        showToast(tr("Buscando carátula…"), seconds: 2)
        Task {
            let data: Data? = await CoverDownloader.findCover(for: name, platform: platform, fileName: file, titleID: titleID)
            CoverDownloader.markAttempted(id)
            guard let data, CoverStore.shared.save(data, for: id) else {
                showToast(tr("No se encontró carátula para este juego"), seconds: 3)
                return
            }
            AutoCovers.mark(id)
            coverVersion += 1
            showToast(tr("Carátula descargada"))
        }
    }

    private func applyCover(from item: PhotosPickerItem, id: String) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              CoverStore.shared.save(data, for: id) else {
            showToast(tr("No se pudo usar esa imagen"))
            return
        }
        // Elegida a mano: las automáticas ya no la sustituyen.
        AutoCovers.unmark(id)
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
        // Instalada con SideStore: las carpetas de los núcleos existen desde el principio, así la
        // carpeta de OmniStation sale en Archivos → En mi iPhone sin tener que importar nada antes.
        if !DebugSupport.isInsideLiveContainer {
            DispatchQueue.global(qos: .utility).async {
                ARMSX2CoreFolders.ensure()
                MeloNXCoreFolders.ensure()
            }
        }
        controllers.onShoulder = { step in handleShoulder(step) }
        controllers.onTrigger = { step in handleTrigger(step) }
        controllers.onCancel = { handleControllerCancel() }
        controllers.onDirection = { direction in handleDirection(direction) }
        controllers.onAccept = { handleAccept() }
        controllers.onOptions = { handleOptions() }
        controllers.onSquare = { handleSquare() }
        if keepLandscape {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                OrientationController.apply(landscape: true)
            }
        }
        if hdmi.isConnected { handleHDMI(true) }
        SoundManager.shared.updateAmbient(volume: volumeAmbient)
        askInstallMethodIfNeeded()
        // JIT integrado: se prepara solo, sin que el usuario tenga que hacer nada.
        if usesBuiltInJIT {
            if !PairingFile.exists { _ = PairingFile.importFromDocuments() }
            jitStatus.autoPrepare()
        }
        if armsx2Integrated { scanCoreGames(silent: true) }
        if melonxIntegrated { scanMeloNXGames(silent: true) }
        scanRetroGames(silent: true)
        warnMeloNXKeysIfNeeded()
        downloadMissingCovers()
        for emulator in Emulator.allCases where EmulatorStore.isEnabled(emulator) {
            // Con el núcleo integrado, la app aparte no se toca.
            if emulator == .armsx2 && armsx2Integrated { continue }
            if emulator == .melonx && melonxIntegrated { continue }
            if EmulatorStore.folderBookmark(emulator) != nil || directLCFolder(emulator) != nil { scanEmulator(emulator, silent: true) }
            if EmulatorStore.autoCheck(emulator) && EmulatorStore.shouldCheck(emulator) {
                checkEmulatorUpdate(emulator, manual: false)
            }
        }
    }

    /// La primera vez se pregunta cómo se instaló la app (decide cómo se activa el JIT).
    private func askInstallMethodIfNeeded() {
        let firstTime: Bool = installMethodRaw.isEmpty
        syncInstallMethod()
        if !firstTime {
            // Una vez: qué emuladores tienes y sus carpetas.
            guard !emulatorSetupDone else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                if !emulatorSetupDone && sheet == nil { sheet = .emulatorSetup }
            }
            return
        }
        // Primera vez: se informa del método detectado y sigue la configuración.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if sheet == nil { sheet = .installMethod }
        }
    }

    // MARK: - Botones del mando

    private func handleShoulder(_ step: Int) {
        // Ventana con pestañas (ajustes del emulador): L1/R1 cambian de pestaña.
        if sheet != nil {
            if sheetPad.sendShoulder(step) { feedback(.navigate) }
            return
        }
        // Con una ventana abierta, la interfaz de detrás no se mueve.
        guard !modalActive else { return }
        // En Ajustes los hombros cambian de parte (General, Biblioteca…).
        if selectedSection == .ajustes {
            cycleSettingsCategory(step)
            return
        }
        // En Favoritos no hay filtros visibles.
        guard selectedSection != .favoritos else { return }
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

    /// Cuadrado/X: en el teclado de Búsqueda borra la última letra.
    private func handleSquare() {
        // Con una ventana con teclado abierta, □ borra la última letra en ella.
        if sheet != nil {
            if sheetPad.sendDelete() { feedback() }
            return
        }
        guard !modalActive, selectedSection == .busqueda, controllerSelectedArea == "alphabet" else { return }
        guard !controllerAlphabetSearchText.isEmpty else { return }
        controllerAlphabetSearchText.removeLast()
        searchText = controllerAlphabetSearchText
        feedback()
    }

    private func handleOptions() {
        // Ventana abierta: △ es suyo (en los ajustes del emulador, «Por defecto»).
        if sheet != nil {
            if sheetPad.sendTriangle() { feedback() }
            return
        }
        // En la pantalla del juego, △ abre sus opciones (como el botón «Opciones»).
        if let game = detailGame, dialog == nil, sheet == nil, !showAbout, !systemPickerOpen {
            openGameOptions(game.id)
            return
        }
        guard !modalActive else { return }
        handleOptionsButton()
    }

    // MARK: - Fondo

    private var background: some View {
        GeometryReader { geometry in
            ZStack {
                Group {
                    if activity.running {
                        // Partida en marcha: nada de vídeo ni imágenes detrás del juego.
                        Color.black
                    } else if let activeVideo {
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
        dialog != nil || showAbout || sheet != nil || systemPickerOpen || detailGame != nil
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
        case .coverOptions:
            return coverOptionsMenu(cancel)
        case .armsx2Mode:
            return armsx2ModeMenu(cancel)
        case .armsx2CoreGames:
            return armsx2CoreGamesMenu(cancel)
        case .armsx2CoreHelp:
            return (tr("ARMSX2 integrado"), tr("Necesita:\n• OmniStation instalada con SideStore o AltStore (no en LiveContainer), sin quitarle su extensión de JIT.\n• iOS 18 o posterior y Modo desarrollador.\n• Archivo de emparejamiento RPPairing y la VPN LocalDevVPN conectada.\n• Tu BIOS de PS2 en ARMSX2 → BIOS.\nTodo lo de ARMSX2 (juegos, BIOS, tarjetas de memoria, estados, texturas, trucos) queda en Archivos → OmniStation Dock → ARMSX2.\nCon mando: Home o SELECT+START abre el menú del juego."), [
                PadMenuItem(title: tr("Entendido"), kind: .cancel) { closePadMenu() }
            ])
        case .armsx2CoreFlavor:
            return armsx2CoreFlavorMenu(cancel)
        case .melonxMode:
            return melonxModeMenu(cancel)
        case .melonxCoreGames:
            return melonxCoreGamesMenu(cancel)
        case .melonxCoreHelp:
            return (tr("MeloNX integrado"), tr("Necesita:\n• OmniStation instalada con SideStore o AltStore (no en LiveContainer), sin quitarle su extensión de JIT.\n• iOS 18 o posterior y Modo desarrollador.\n• Archivo de emparejamiento RPPairing y la VPN LocalDevVPN conectada.\n• Tus claves (prod.keys) y el firmware de tu Switch.\n• Un mando conectado.\nLos juegos van en Archivos → OmniStation Dock → MeloNX → Juegos. Ryujinx guarda claves, firmware y partidas en la raíz de OmniStation Dock (carpetas system, bis, sdcard…).\nCon mando: Home o SELECT+START abre el menú del juego."), [
                PadMenuItem(title: tr("Entendido"), kind: .cancel) { closePadMenu() }
            ])
        case .retroSystem:
            return retroSystemMenu(cancel)
        case .memoryHelp:
            return (tr("Más memoria para MeloNX"), tr("Esta versión de OmniStation pide el permiso «Increased Memory Limit». Para que iOS lo conceda:\n1. Abre la app GetMoreRam, inicia sesión con la cuenta con la que firmas OmniStation y añade «Increased Memory Limit» al App ID de OmniStation.\n2. En SideStore, refresca o reinstala OmniStation.\n3. Vuelve aquí: la tarjeta «Memoria» se pondrá en verde."), [
                PadMenuItem(title: tr("Entendido"), kind: .cancel) { closePadMenu() }
            ])
        case .jitEnabler:
            return jitEnablerMenu(cancel)
        case .jitScript:
            return jitScriptMenu(cancel)
        case .emulatorLocation:
            return emulatorLocationMenu(cancel)
        case .emulatorBundle:
            return emulatorBundleMenu(cancel)
        case .emulatorUpdate:
            return emulatorUpdateMenu(cancel)
        case .emulatorFolder:
            return emulatorFolderMenu(cancel)
        case .emulatorHelp:
            return (tr("Juegos de MeloNX"), tr("OmniStation abre cada juego en MeloNX por su Title ID, y lo lee solo del archivo (el ticket de los .nsp o el [0100…] del nombre).\nSi un juego no abre: en sus Opciones (△) → «Nombre en MeloNX», escribe el título exacto que sale en MeloNX.\nLas actualizaciones y DLC no salen como juegos: están en Opciones → «Actualizaciones y DLC» de cada juego, y se activan en la app MeloNX."), [
                PadMenuItem(title: tr("Entendido"), kind: .cancel) { closePadMenu() }
            ])
        }
    }

    private func jitEnablerMenu(_ cancel: PadMenuItem) -> PadMenuContent {
        let current: JITEnabler = JITEnabler(rawValue: jitEnablerRaw) ?? .builtIn
        var items: [PadMenuItem] = []
        items.append(PadMenuItem(title: checked(tr("JIT integrado (StikJIT)"), current == .builtIn)) {
            jitEnablerRaw = JITEnabler.builtIn.rawValue
            closePadMenu()
            if usesBuiltInJIT { jitStatus.autoPrepare() }
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

    private func emulatorLocationMenu(_ cancel: PadMenuItem) -> PadMenuContent {
        let emulator: Emulator = activeEmulator
        let current: Emulator.Location = EmulatorStore.location(emulator, installMethod: installMethodRaw)
        var items: [PadMenuItem] = []
        items.append(PadMenuItem(title: checked("LiveContainer", current == .liveContainer)) {
            EmulatorStore.setLocation(.liveContainer, emulator)
            emulatorRevision += 1
            closePadMenu()
        })
        items.append(PadMenuItem(title: checked(tr("SideStore / AltStore"), current == .native)) {
            EmulatorStore.setLocation(.native, emulator)
            emulatorRevision += 1
            closePadMenu()
        })
        items.append(cancel)
        return (tr("%@ instalado en", emulator.name), nil, items)
    }

    private func emulatorBundleMenu(_ cancel: PadMenuItem) -> PadMenuContent {
        let emulator: Emulator = activeEmulator
        var items: [PadMenuItem] = []
        if usesBuiltInJIT {
            items.append(PadMenuItem(title: tr("Elegir app instalada")) {
                closePadMenu()
                appPickerTarget = .emulator(emulator)
                sheet = .installedApps
            })
        }
        items.append(PadMenuItem(title: tr("Escribir Bundle ID")) {
            closePadMenu()
            sheet = .textEntry(.bundle(emulator))
        })
        items.append(cancel)
        return (tr("Bundle ID de %@", emulator.name), EmulatorStore.bundleID(emulator), items)
    }

    private func emulatorFolderMenu(_ cancel: PadMenuItem) -> PadMenuContent {
        let emulator: Emulator = activeEmulator
        let name: String = EmulatorStore.folderName(emulator)
        var items: [PadMenuItem] = []
        if usesLiveContainerFolder(emulator) {
            // Dentro de LiveContainer no se elige carpeta: el selector copiaría los juegos a la
            // carpeta Inbox de OmniStation. Se lee la carpeta del emulador directamente.
            let found: Bool = directLCFolder(emulator) != nil
            if found {
                items.append(PadMenuItem(title: tr("Escanear su carpeta de LiveContainer")) {
                    closePadMenu()
                    scanEmulator(emulator, silent: false)
                })
            }
            if !name.isEmpty {
                items.append(PadMenuItem(title: tr("Olvidar la carpeta elegida antes"), kind: .destructive) {
                    closePadMenu()
                    unlinkEmulatorFolder(emulator)
                })
            }
            items.append(cancel)
            let message: String = found
                ? tr("OmniStation lee los juegos de la carpeta de %@ en LiveContainer: no se copia nada.", emulator.name)
                : tr("No se encuentra la carpeta de %@ en LiveContainer. Revisa «Carpeta en LiveContainer» (el nombre de su .app).", emulator.name)
            return (tr("Juegos de %@", emulator.name), message, items)
        }
        items.append(PadMenuItem(title: name.isEmpty ? tr("Elegir carpeta") : tr("Cambiar carpeta")) {
            closePadMenu()
            folderPickEmulator = emulator
            openFolderImporter()
        })
        if !name.isEmpty {
            items.append(PadMenuItem(title: tr("Volver a escanear")) {
                closePadMenu()
                scanEmulator(emulator, silent: false)
            })
            items.append(PadMenuItem(title: tr("Desvincular carpeta"), kind: .destructive) {
                closePadMenu()
                unlinkEmulatorFolder(emulator)
            })
        }
        items.append(cancel)
        return (tr("Juegos de %@", emulator.name), name.isEmpty ? tr("La misma carpeta que uses dentro del emulador.") : name, items)
    }

    private func emulatorUpdateMenu(_ cancel: PadMenuItem) -> PadMenuContent {
        let emulator: Emulator = activeEmulator
        let installedTag: String = EmulatorStore.installedVersion(emulator)
        let latestTag: String = EmulatorStore.latestTag(emulator)
        let installed: String = installedTag.isEmpty ? tr("sin marcar") : EmulatorUpdater.shortName(installedTag)
        let latest: String = latestTag.isEmpty ? tr("sin comprobar") : EmulatorUpdater.shortName(latestTag)
        let message: String = tr("Instalada: %@", installed) + "\n" + tr("Última: %@", latest)
        var items: [PadMenuItem] = []
        if !EmulatorStore.latestURL(emulator).isEmpty {
            let title: String = latestTag == installedTag ? tr("Reinstalar") : tr("Instalar %@", latest)
            items.append(PadMenuItem(title: title) {
                closePadMenu()
                installEmulator(emulator)
            })
        }
        items.append(PadMenuItem(title: tr("Buscar actualizaciones")) {
            closePadMenu()
            checkEmulatorUpdate(emulator, manual: true)
        })
        if !latestTag.isEmpty && latestTag != installedTag {
            items.append(PadMenuItem(title: tr("Ya la tengo: marcar como instalada")) {
                EmulatorStore.setInstalledVersion(latestTag, emulator)
                emulatorRevision += 1
                closePadMenu()
            })
        }
        items.append(cancel)
        return (emulator.name, message, items)
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
            openFolderImporter()
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
            dialog = .coverOptions
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
        if let emulator = integratedEmulator(for: id) {
            let own: Bool = EmulatorConfig.hasGameSettings(.app(emulator), id)
            items.insert(PadMenuItem(title: own ? "✓ " + tr("Configuración del emulador") : tr("Configuración del emulador")) {
                closePadMenu()
                openEmulatorConfig(emulator, gameID: id)
            }, at: 0)
        } else if let system = retroSystem(for: id) {
            let own: Bool = EmulatorConfig.hasGameSettings(.retro(system), id)
            items.insert(PadMenuItem(title: own ? "✓ " + tr("Configuración del emulador") : tr("Configuración del emulador")) {
                closePadMenu()
                openRetroConfig(system, gameID: id)
            }, at: 0)
        }
        let jitOn: Bool = wantsJIT(game)
        let jitTitle: String = jitOn ? "✓ " + tr("Abrir con JIT") : tr("Abrir con JIT")
        items.append(PadMenuItem(title: jitTitle) {
            updateMeta(id) { meta in meta.useJIT = !jitOn }
            closePadMenu()
            showToast(jitOn ? tr("Se abrirá sin JIT") : tr("Se abrirá con JIT"))
        })
        if game.platform == Emulator.melonx.platform {
            let addonCount: Int = switchTitleID(id).map { SwitchAddonStore.shared.addons(baseTitleID: $0).count } ?? 0
            items.append(PadMenuItem(title: addonCount > 0 ? tr("Actualizaciones y DLC (%ld)", addonCount) : tr("Actualizaciones y DLC")) {
                closePadMenu()
                sheet = .switchAddons(id)
            })
        }
        if let emulator = emulatorFor(game), emulator == .melonx {
            items.append(PadMenuItem(title: tr("Nombre en %@", emulator.name)) {
                closePadMenu()
                sheet = .textEntry(.emulatorGame(id))
            })
        }
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

    /// Cambiar carátula: descargarla, o importarla de Fotos o de Archivos.
    private func coverOptionsMenu(_ cancel: PadMenuItem) -> PadMenuContent? {
        guard let game = editingGame else { return nil }
        let id: String = game.id
        var items: [PadMenuItem] = []
        items.append(PadMenuItem(title: tr("Descargar")) {
            closePadMenu()
            downloadCover(for: game)
        })
        items.append(PadMenuItem(title: tr("Importar foto")) {
            closePadMenu()
            pickPhoto(.cover(id))
        })
        items.append(PadMenuItem(title: tr("Importar archivo")) {
            closePadMenu()
            importerPurpose = .cover(id)
            showFolderImporter = true
        })
        items.append(cancel)
        return (tr("Cambiar carátula"), game.name, items)
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

    // MARK: - Pantalla del juego

    /// El juego de la pantalla abierta (nil si se cerró o si se quitó de la biblioteca).
    private var detailGame: Game? {
        guard let id = detailGameID else { return nil }
        return games.first { $0.id == id }
    }

    @ViewBuilder
    private func detailOverlay(landscape: Bool, dock: Bool) -> some View {
        if let game = detailGame {
            GameDetailView(
                game: game,
                cover: cover(for: game.id),
                isFavorite: favoriteNames.contains(game.id),
                lang: appLanguage,
                landscape: landscape,
                dock: dock,
                gamepadConnected: gamepadConnected,
                focus: detailFocus,
                showDescription: detailShowDescription,
                fileName: libraryGames.first(where: { $0.id == game.id })?.fileName,
                titleID: game.platform == Emulator.melonx.platform ? switchTitleID(game.id) : nil,
                filePath: detailFilePath(game.id),
                emulatorLabel: detailEmulatorLabel(game),
                hasOwnSettings: integratedConfigTarget(for: game.id).map { EmulatorConfig.hasGameSettings($0, game.id) },
                onPlay: { launch(game) },
                onOptions: { openGameOptions(game.id) },
                onFavorite: { toggleFavorite(game.id) },
                onBack: { closeDetail() },
                onToggleDescription: { toggleDetailDescription() },
                onAchievements: { openDetailAchievements(game.id) }
            )
            .transition(.opacity)
            .zIndex(5)
        }
    }

    /// Ruta del archivo de un juego de los núcleos integrados (para su tamaño).
    private func detailFilePath(_ id: String) -> String? {
        guard let item = libraryGames.first(where: { $0.id == id }), let file = item.fileName else { return nil }
        if item.source == ARMSX2CoreFolders.source { return ARMSX2CoreFolders.path(for: file) }
        if item.source == MeloNXCoreFolders.source { return MeloNXCoreFolders.path(for: file) }
        if let system = RetroSystem.from(source: item.source) { return RetroFolders.path(system, fileName: file) }
        return nil
    }

    private func detailEmulatorLabel(_ game: Game) -> String? {
        if let emulator = integratedEmulator(for: game.id) {
            return tr("%@ integrado", emulator.name)
        }
        if let system = retroSystem(for: game.id), let core = RetroConfig.core(for: system, gameID: game.id) {
            return tr("%@ integrado", core.name)
        }
        return emulatorFor(game)?.name
    }

    private func toggleDetailDescription() {
        feedback()
        withAnimation(.easeOut(duration: 0.22)) { detailShowDescription.toggle() }
    }

    /// ←→ entre «Jugar» y «Opciones»; ↑ a los botones de arriba: volver, descripción (en
    /// horizontal) y favorito.
    private func moveDetailFocus(_ direction: ControllerMonitor.Direction) {
        // La descripción va debajo de los botones (solo si el juego tiene).
        let hasInfo: Bool = detailGame.map { GameDescriptions.hasCached(name: $0.name, language: L10n.resolve(appLanguage)) } ?? false
        let next: GameDetailFocus
        switch (detailFocus, direction) {
        case (.play, .right): next = .options
        case (.options, .left): next = .play
        case (.play, .up): next = .back
        case (.options, .up): next = .achievements
        case (.play, .down), (.options, .down): next = hasInfo ? .info : detailFocus
        case (.info, .up): next = .play
        case (.back, .right): next = .achievements
        case (.achievements, .left): next = .back
        case (.achievements, .right): next = .favorite
        case (.favorite, .left): next = .achievements
        case (.achievements, .down): next = .options
        case (.back, .down): next = .play
        case (.favorite, .down): next = .options
        default: next = detailFocus
        }
        guard next != detailFocus else { return }
        detailFocus = next
        feedback(.navigate)
    }

    private func activateDetailFocus() {
        guard let game = detailGame else { return }
        switch detailFocus {
        case .play: launch(game)
        case .options: openGameOptions(game.id)
        case .favorite: toggleFavorite(game.id)
        case .back: closeDetail()
        case .info: toggleDetailDescription()
        case .achievements: openDetailAchievements(game.id)
        }
    }

    /// Botón de logros de la pantalla del juego (RetroAchievements).
    private func openDetailAchievements(_ id: String) {
        editingGameID = id
        feedback()
        sheet = .achievements
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
                .frame(maxWidth: padMenuColumns > 1 ? 660 : 340)
                .glassCard(cornerRadius: 26)
                .padding(24)
            }
            .transition(.opacity)
        }
    }

    /// En horizontal, los menús con varias opciones se ven en cuadrícula (3 por fila).
    private var padMenuColumns: Int {
        guard isLandscapeNow, let menu = padMenu, menu.items.count > 3 else { return 1 }
        return 3
    }

    @ViewBuilder
    private func padMenuList(_ items: [PadMenuItem]) -> some View {
        if padMenuColumns > 1 {
            padMenuGrid(items)
        } else if items.count > 7 {
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

    private func padMenuGrid(_ items: [PadMenuItem]) -> some View {
        let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
        let rows: Int = (items.count + 2) / 3
        return ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(items.indices, id: \.self) { index in
                        padMenuButton(items[index], selected: index == menuIndex, tile: true)
                            .id(index)
                    }
                }
                .padding(2)
            }
            .frame(height: rows > 3 ? 236 : CGFloat(rows) * 72 + 4)
            .onChange(of: menuIndex) { _, value in
                withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(value, anchor: .center) }
            }
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

    private func padMenuButton(_ item: PadMenuItem, selected rawSelected: Bool, tile: Bool = false) -> some View {
        let selected: Bool = rawSelected && gamepadConnected
        let color: Color = item.kind == .destructive ? Color.red : (item.kind == .cancel ? Color.white.opacity(0.8) : Color.cyan)
        return Button {
            item.action()
        } label: {
            Text(item.title)
                .font(AppFont.text(tile ? 13 : 15, .semibold))
                .foregroundStyle(color)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, minHeight: tile ? 38 : nil)
                .padding(.horizontal, tile ? 8 : 0)
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
            let columns: Int = padMenuColumns
            let last: Int = menu.items.count - 1
            switch direction {
            case .up: menuIndex = max(0, menuIndex - columns)
            case .down: menuIndex = min(last, menuIndex + columns)
            case .left: if columns > 1 && menuIndex % columns > 0 { menuIndex -= 1 }
            case .right: if columns > 1 && menuIndex % columns < columns - 1 && menuIndex < last { menuIndex += 1 }
            }
            feedback(.navigate)
            return
        }
        if sheet != nil {
            let action: PadAction
            switch direction {
            case .up: action = .up
            case .down: action = .down
            case .left: action = .left
            case .right: action = .right
            }
            if sheetPad.send(action) { feedback(.navigate) }
            return
        }
        if detailGame != nil && !systemPickerOpen {
            moveDetailFocus(direction)
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
        if sheet != nil {
            if sheetPad.send(.accept) { feedback() }
            return
        }
        if detailGame != nil && !systemPickerOpen {
            activateDetailFocus()
        }
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
        // 1b) Pantalla del juego: vuelve a la lista.
        if detailGame != nil {
            if detailShowDescription {
                toggleDetailDescription()
            } else {
                closeDetail()
            }
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

    /// Elegir un juego (✕ o toque) abre su pantalla; desde ella, «Jugar» lo lanza.
    private func open(_ game: Game) {
        feedback()
        optionsExpanded = false
        detailFocus = .play
        detailShowDescription = false
        withAnimation(.easeOut(duration: 0.22)) { detailGameID = game.id }
    }

    private func closeDetail() {
        feedback(.navigate)
        withAnimation(.easeIn(duration: 0.18)) { detailGameID = nil }
    }

    /// Abre el juego en su emulador o app.
    private func launch(_ game: Game) {
        feedback()
        if let item = libraryGames.first(where: { $0.id == game.id }), let system = RetroSystem.from(source: item.source) {
            playCounts[game.id, default: 0] += 1
            UserDefaults.standard.set(playCounts, forKey: "playCounts")
            launchRetro(game, item: item, system: system)
            return
        }
        if let item = libraryGames.first(where: { $0.id == game.id }), item.source == ARMSX2CoreFolders.source {
            playCounts[game.id, default: 0] += 1
            UserDefaults.standard.set(playCounts, forKey: "playCounts")
            launchIntegratedARMSX2(game, item: item)
            return
        }
        if let item = libraryGames.first(where: { $0.id == game.id }), item.source == MeloNXCoreFolders.source {
            playCounts[game.id, default: 0] += 1
            UserDefaults.standard.set(playCounts, forKey: "playCounts")
            launchIntegratedMeloNX(game, item: item)
            return
        }
        if melonxIntegrated && game.isCustom && game.launchURL == nil && game.platform == Emulator.melonx.platform {
            showToast(tr("Con MeloNX integrado, los juegos de Switch van en Archivos → OmniStation Dock → MeloNX → Juegos."), seconds: 4.5)
            return
        }
        // Con el núcleo integrado, los juegos de PS2 tienen que estar en su carpeta propia.
        if armsx2Integrated && game.isCustom && game.launchURL == nil && game.platform == Emulator.armsx2.platform {
            showToast(tr("Con el núcleo integrado, los juegos de PS2 van en Archivos → OmniStation Dock → ARMSX2 → Juegos."), seconds: 4.5)
            return
        }
        playCounts[game.id, default: 0] += 1
        UserDefaults.standard.set(playCounts, forKey: "playCounts")
        if let emulator = emulatorFor(game) {
            openInEmulator(game, emulator)
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
        launchExternal(url, failure: tr("No se pudo abrir el enlace"))
    }

    /// ¿Este juego se abre con JIT? Lo decide su ajuste (Opciones del juego); si no tiene, sin JIT.
    private func wantsJIT(_ game: Game) -> Bool {
        gameMeta[game.id]?.useJIT ?? false
    }

    private func openWithJIT(_ game: Game) {
        // Juego de LiveContainer: su enlace con jit=true (LiveContainer se lo pide a StikDebug).
        if let liveContainerURL = JITLauncher.liveContainerJITURL(game.launchURL) {
            // Desde dentro de LiveContainer, el JIT se pide como lo hace LiveContainer.
            if DebugSupport.isInsideLiveContainer, let link = game.launchURL {
                let request: LiveContainerJIT.Request = LiveContainerJIT.request(forLaunchLink: link)
                if requestLiveContainerJIT(request, name: game.name) { return }
            }
            showToast(tr("Abriendo con JIT…"))
            launchExternal(liveContainerURL, failure: tr("No se pudo abrir LiveContainer. ¿Está instalado?"))
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
        launchExternal(url, failure: tr("No se pudo abrir StikDebug. ¿Está instalado?"))
    }

    /// Pide el JIT a StikDebug para una app de LiveContainer. Devuelve false si hay que usar
    /// el enlace normal (por ejemplo, si el activador de LiveContainer no es StikDebug ni SideStore).
    private func requestLiveContainerJIT(_ request: LiveContainerJIT.Request, name: String) -> Bool {
        switch request {
        case .ready(let url):
            showToast(tr("Pidiendo JIT para %@…", name))
            UIApplication.shared.open(url) { success in
                DispatchQueue.main.async {
                    if success {
                        closeAfterLaunchIfNeeded(delay: 1.5)
                    } else {
                        LiveContainerJIT.cancel()
                        showToast(tr("No se pudo abrir StikDebug. ¿Está instalado?"))
                    }
                }
            }
            return true
        case .appNotFound:
            showToast(tr("LiveContainer no encuentra %@. Revisa el nombre de su carpeta.", name), seconds: 4)
            return true
        case .unsupported:
            return false
        }
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
                jitStatus.markReady()
                pendingReturnMessage = afterMessage ?? tr("JIT activado en %@", name)
                // Con un mensaje para cuando vuelvas (ARMSX2), la app se queda para enseñarlo.
                if afterMessage == nil { closeAfterLaunchIfNeeded(delay: 0.5) }
            case .failure(let error):
                let text: String = tr("No se pudo activar el JIT: %@", BuiltInJIT.message(for: error))
                pendingReturnMessage = nil
                showToast(text, seconds: 7)
            }
        })
    }

    /// Indicador de JIT (horizontal): verde si los juegos pueden abrirse con JIT ahora mismo.
    /// Verde si el JIT funciona ahora mismo: en LiveContainer, si la app corre con JIT; con el JIT
    /// integrado (SideStore), si está listo para dárselo a los juegos (OmniStation no lo necesita).
    private var jitIndicatorOn: Bool {
        if usesBuiltInJIT { return jitStatus.isReady }
        // En iOS 26 el JIT solo vale si el depurador sigue enganchado (no basta con que se activara).
        return jitEnabled && OSLibretroEngine.jitActive
    }

    private func explainJITIndicator() {
        refreshJITStatus(announce: false)
        guard usesBuiltInJIT else {
            if jitEnabled && !OSLibretroEngine.jitActive {
                showToast(tr("Se activó el JIT, pero el depurador ya no está enganchado y en iOS 26 hace falta. En StikDebug, pon el script «universal» a LiveContainer y vuelve a activar el JIT."), seconds: 7)
            } else {
                showToast(jitEnabled ? tr("JIT activo en esta app") : tr("JIT no activo en esta app"), seconds: 3)
            }
            return
        }
        let text: String
        switch jitStatus.state {
        case .ready: text = tr("JIT integrado listo")
        case .preparing: text = tr("Preparando el JIT…")
        case .unreachable: text = tr("JIT no disponible: activa la VPN LocalDevVPN")
        case .failed(let reason): text = tr("JIT no disponible: %@", reason)
        case .idle: text = tr("JIT no disponible: falta el archivo de emparejamiento")
        }
        if !jitStatus.isReady { jitStatus.autoPrepare(force: true) }
        showToast(text, seconds: 3.5)
    }

    // MARK: - Enlaces que llegan (MeloNX y ARMSX2)

    private func handleIncomingLink(_ url: URL) {
        if let list = ARMSX2Library.games(from: url) {
            applyARMSX2Library(list)
            return
        }
        guard let list = MeloNXLibrary.games(from: url) else { return }
        applyMeloNXLibrary(list)
        // Después, si hace falta, la de ARMSX2 (nunca las dos a la vez).
        _ = requestARMSX2LibraryIfNeeded()
    }

    /// Empareja los juegos de Switch con los títulos de MeloNX: guarda su Title ID, usa el título
    /// de MeloNX como nombre en OmniStation y su icono como carátula (salvo carátulas elegidas a mano).
    private func applyMeloNXLibrary(_ list: [MeloNXGame]) {
        var matched: Int = 0
        var forcedSaved: Set<String> = []
        let switchGames: [Game] = games.filter { $0.isCustom && $0.platform == Emulator.melonx.platform }
        for game in switchGames {
            let file: String = libraryGames.first(where: { $0.id == game.id })?.fileName ?? ""
            let fileBase: String = (file as NSString).deletingPathExtension
            let originalName: String = libraryGames.first(where: { $0.id == game.id })?.name ?? game.name
            var found: MeloNXGame? = nil
            if let titleID = Emulator.titleID(in: file) {
                found = list.first { $0.titleId.lowercased() == titleID }
            }
            if found == nil, let saved = gameMeta[game.id]?.emulatorGameID, Emulator.isTitleID(saved) {
                found = list.first { $0.titleId.lowercased() == saved.lowercased() }
            }
            if found == nil {
                found = MeloNXLibrary.bestMatch(for: originalName, in: list) ?? MeloNXLibrary.bestMatch(for: fileBase, in: list)
            }
            guard let match = found else { continue }
            updateMeta(game.id) { meta in
                meta.emulatorGameID = match.titleId
                if !match.titleName.isEmpty { meta.name = match.titleName }
            }
            let replaceable: Bool = CoverStore.shared.image(for: game.id) == nil || AutoCovers.contains(game.id) || forcedCoverIDs.contains(game.id)
            if let icon = match.iconData, replaceable, CoverStore.shared.save(icon, for: game.id) {
                AutoCovers.mark(game.id)
                forcedSaved.insert(game.id)
            }
            matched += 1
        }
        let forcedMissing: Bool = !forcedCoverIDs.subtracting(forcedSaved).isEmpty
        forcedCoverIDs = []
        coverVersion += 1
        if forcedMissing {
            showToast(tr("MeloNX no tiene carátula para ese juego"), seconds: 3)
            return
        }
        showToast(tr("MeloNX: %ld de %ld juegos reconocidos", matched, switchGames.count), seconds: 4)
    }

    /// Pide la lista de juegos al emulador que tenga juegos nuevos sin reconocer: primero MeloNX
    /// y, cuando vuelva, ARMSX2. Nunca abre los dos a la vez.
    private func requestEmulatorLibrariesIfNeeded() {
        if !requestMeloNXLibraryIfNeeded() {
            _ = requestARMSX2LibraryIfNeeded()
        }
    }

    /// Si hay juegos de MeloNX nuevos sin reconocer, se le pide su lista (una vez por cada
    /// grupo de juegos nuevos, para no abrir MeloNX cada vez que se abre la app).
    private func requestMeloNXLibraryIfNeeded() -> Bool {
        guard EmulatorStore.isEnabled(.melonx),
              EmulatorStore.location(.melonx, installMethod: installMethodRaw) == .native else { return false }
        let pending: [String] = libraryGames
            .filter { $0.source == "emu:" + Emulator.melonx.rawValue && gameMeta[$0.id]?.emulatorGameID == nil && MeloNXIdentity.link(for: $0.id) == nil }
            .map(\.id)
            .sorted()
        return scheduleLibraryRequest(pending: pending, key: "melonxLibraryAskedFor", perform: {
            requestMeloNXLibrary()
        })
    }

    /// Lo mismo con ARMSX2: sus juegos sin nombre reconocido.
    private func requestARMSX2LibraryIfNeeded() -> Bool {
        guard !armsx2Integrated, EmulatorStore.isEnabled(.armsx2),
              EmulatorStore.location(.armsx2, installMethod: installMethodRaw) == .native else { return false }
        let pending: [String] = libraryGames
            .filter { $0.source == "emu:" + Emulator.armsx2.rawValue && gameMeta[$0.id]?.name == nil }
            .map(\.id)
            .sorted()
        return scheduleLibraryRequest(pending: pending, key: "armsx2LibraryAskedFor", perform: {
            requestARMSX2Library()
        })
    }

    /// Abre el emulador para pedir su lista si hay juegos nuevos. El grupo de juegos se apunta
    /// solo cuando de verdad se abre (si la app no está delante, se pedirá la próxima vez).
    private func scheduleLibraryRequest(pending: [String], key: String, perform: @escaping () -> Void) -> Bool {
        guard !pending.isEmpty, !libraryRequestScheduled else { return false }
        let signature: String = pending.joined(separator: "|")
        guard UserDefaults.standard.string(forKey: key) != signature else { return false }
        libraryRequestScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            libraryRequestScheduled = false
            guard UIApplication.shared.applicationState == .active, sheet == nil, dialog == nil, detailGame == nil else { return }
            UserDefaults.standard.set(signature, forKey: key)
            perform()
        }
        return true
    }

    /// Pide a ARMSX2 su lista de juegos (ARMSX2 pide confirmación antes de mandarla).
    private func requestARMSX2Library() {
        openExternal(ARMSX2Library.requestURL, failure: tr("No se pudo abrir %@. ¿Está instalado?", Emulator.armsx2.name))
    }

    /// Usa el título que conoce ARMSX2 como nombre de cada juego (salvo los renombrados a mano)
    /// y busca de nuevo su carátula con ese nombre.
    private func applyARMSX2Library(_ list: [ARMSX2Game]) {
        let items: [LibraryGame] = libraryGames.filter { $0.source == "emu:" + Emulator.armsx2.rawValue }
        var matched: Int = 0
        var renamed: [String] = []
        for item in items {
            guard let file = item.fileName, let match = ARMSX2Library.match(fileName: file, in: list) else { continue }
            matched += 1
            let title: String = match.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, gameMeta[item.id]?.name == nil else { continue }
            updateMeta(item.id) { meta in meta.name = title }
            renamed.append(item.id)
        }
        showToast(tr("ARMSX2: %ld de %ld juegos reconocidos", matched, items.count), seconds: 4)
        refreshCovers(renamed)
        // Si MeloNX también tenía juegos nuevos, ahora le toca a él.
        _ = requestMeloNXLibraryIfNeeded()
    }

    /// Vuelve a buscar la carátula de estos juegos con su nombre nuevo. Solo cambia las que no
    /// tenían o las puestas por la app; las elegidas a mano se quedan.
    private func refreshCovers(_ ids: [String]) {
        guard autoCoversEnabled, !ids.isEmpty else { return }
        let targets: [Game] = games.filter { game in
            ids.contains(game.id) && (CoverStore.shared.image(for: game.id) == nil || AutoCovers.contains(game.id))
        }
        guard !targets.isEmpty else { return }
        let files: [String: String] = Dictionary(libraryGames.compactMap { item in
            item.fileName.map { (item.id, $0) }
        }, uniquingKeysWith: { first, _ in first })
        Task {
            var added: Int = 0
            for game in targets {
                CoverDownloader.markAttempted(game.id)
                guard let data = await CoverDownloader.findCover(for: game.name, platform: game.platform, fileName: files[game.id]) else { continue }
                let replaceable: Bool = CoverStore.shared.image(for: game.id) == nil || AutoCovers.contains(game.id)
                if replaceable, CoverStore.shared.save(data, for: game.id) {
                    AutoCovers.mark(game.id)
                    added += 1
                }
            }
            if added > 0 {
                coverVersion += 1
                showToast(tr("%ld carátulas descargadas", added), seconds: 3)
            }
        }
    }

    /// Pide a MeloNX su lista de juegos (solo con MeloNX instalado aparte: LiveContainer no la devuelve).
    private func requestMeloNXLibrary() {
        openExternal(MeloNXLibrary.requestURL, failure: tr("No se pudo abrir %@. ¿Está instalado?", Emulator.melonx.name))
    }

    // MARK: - ARMSX2 integrado (núcleo dentro de OmniStation)

    /// ¿Se juega a PS2 con el núcleo integrado? (Nunca dentro de LiveContainer.)
    /// Emuladores que van con su núcleo integrado (sin app aparte).
    private var integratedEmulators: [Emulator] {
        var list: [Emulator] = []
        if armsx2Integrated { list.append(.armsx2) }
        if melonxIntegrated { list.append(.melonx) }
        return list
    }

    private var armsx2Integrated: Bool {
        ARMSX2Mode.effective(armsx2ModeRaw) == .integrated
    }

    /// Ajustes de ARMSX2 según el modo: los de la app aparte o los del núcleo integrado.
    private var emulatorGroups: [SettingGroup] {
        var groups: [SettingGroup] = Emulator.allCases.map { (emulator: Emulator) -> SettingGroup in
            if emulator == .armsx2 && armsx2Integrated { return armsx2CoreSettings }
            if emulator == .melonx && melonxIntegrated { return melonxCoreSettings }
            return emulatorSettings(emulator)
        }
        if let retro = retroSettings { groups.append(retro) }
        return groups
    }

    private var armsx2ModeItem: SettingItem {
        let subtitle: String = armsx2Integrated ? tr("Núcleo integrado") : tr("App aparte (LiveContainer / SideStore)")
        return SettingItem(id: "armsx2Mode", title: tr("Modo de ARMSX2"), subtitle: subtitle, symbol: "switch.2", tint: SettingTint.violet, control: .symbol("chevron.right"), action: {
            dialog = .armsx2Mode
        })
    }

    private var armsx2CoreSettings: SettingGroup {
        _ = emulatorRevision
        var items: [SettingItem] = [armsx2ModeItem]
        let bundled: Bool = OSArmsx2Engine.coreBundled
        let revision: String = OSArmsx2Engine.shared.coreRevision
        let flavorName: String = OSArmsx2Engine.coreFlavor == "omnistation" ? "OmniStation" : "NeoStation"
        let baseText: String = revision.isEmpty ? "ARMSX2 iOS 2.6" : "ARMSX2 " + String(revision.prefix(8))
        let coreText: String = bundled ? baseText + " · " + flavorName : tr("No incluido en esta compilación")
        let coreControl: SettingControl = bundled ? .badge("OK", Color.green) : .badge(tr("FALTA"), Color.orange)
        items.append(SettingItem(id: "armsx2CoreStatus", title: tr("Núcleo"), subtitle: coreText, symbol: "cpu", tint: SettingTint.blue, control: coreControl, action: {
            dialog = .armsx2CoreHelp
        }))
        items.append(SettingItem(id: "armsx2CoreFlavor", title: tr("Versión del núcleo"), subtitle: armsx2FlavorSubtitle, symbol: "square.stack.3d.up.fill", tint: SettingTint.blue, control: .symbol("chevron.right"), action: {
            dialog = .armsx2CoreFlavor
        }))
        let count: Int = libraryGames.filter { $0.source == ARMSX2CoreFolders.source }.count
        items.append(SettingItem(id: "armsx2CoreGames", title: tr("Juegos"), subtitle: "ARMSX2/Juegos", symbol: "externaldrive.fill", tint: SettingTint.blue, control: .badge("\(count)", Color.green), action: {
            dialog = .armsx2CoreGames
        }))
        let biosFiles: [String] = ARMSX2CoreFolders.biosFiles()
        let biosControl: SettingControl = biosFiles.isEmpty ? .badge(tr("FALTA"), Color.orange) : .badge("OK", Color.green)
        items.append(SettingItem(id: "armsx2CoreBIOS", title: "BIOS", subtitle: biosFiles.first ?? tr("Importa tu BIOS de PS2"), symbol: "memorychip", tint: SettingTint.blue, control: biosControl, action: {
            openCoreImporter(.coreBIOS)
        }))
        items.append(emulatorConfigItem(.armsx2))
        items.append(toggleSetting("armsx2CoreTouch", tr("Controles táctiles siempre"), tr("Si no, se ocultan con un mando conectado"), "hand.tap.fill", SettingTint.blue, $armsx2TouchAlways))
        items.append(SettingItem(id: "armsx2CoreBoot", title: tr("Arrancar la BIOS"), subtitle: tr("Prueba el núcleo sin juego"), symbol: "play.circle.fill", tint: SettingTint.blue, control: .symbol("play.fill"), action: {
            startIntegratedARMSX2(gamePath: nil, title: "PS2 BIOS", gameID: nil)
        }))
        items.append(SettingItem(id: "armsx2CoreFolder", title: tr("Carpeta ARMSX2"), subtitle: tr("Abrir en Archivos"), symbol: "folder.fill", tint: SettingTint.blue, control: .symbol("arrow.up.forward"), action: {
            ARMSX2CoreFolders.ensure()
            openExternal(ARMSX2CoreFolders.filesAppURL, failure: tr("No se pudo abrir Archivos."))
        }))
        items.append(SettingItem(id: "armsx2CoreHelp", title: tr("Requisitos"), subtitle: tr("Qué necesita el núcleo integrado"), symbol: "questionmark.circle.fill", tint: SettingTint.blue, control: .symbol("chevron.right"), action: {
            dialog = .armsx2CoreHelp
        }))
        return SettingGroup(id: "armsx2core", title: tr("ARMSX2 integrado (PS2)"), isSubsection: true, items: items)
    }

    /// Ajustes generales de emulación del núcleo integrado (cada juego puede tener los suyos).
    private func emulatorConfigItem(_ emulator: Emulator) -> SettingItem {
        let changed: Int = EmulatorConfig.global(.app(emulator)).count
        let subtitle: String = changed == 0 ? tr("Gráficos, sistema, sonido y HUD") : tr("%ld cambiados", changed)
        return SettingItem(id: emulator.rawValue + "Config", title: tr("Ajustes de emulación"), subtitle: subtitle, symbol: "slider.horizontal.3", tint: SettingTint.violet, control: .symbol("chevron.right"), action: {
            openEmulatorConfig(emulator, gameID: nil)
        })
    }

    private func openEmulatorConfig(_ emulator: Emulator, gameID: String?) {
        sheet = .emulatorConfig(.app(emulator), gameID)
    }

    private func openRetroConfig(_ system: RetroSystem, gameID: String?) {
        sheet = .emulatorConfig(.retro(system), gameID)
    }

    /// Núcleo integrado con el que se juega este juego (nil si se abre con una app aparte).
    private func integratedEmulator(for id: String) -> Emulator? {
        guard installMethodRaw == InstallMethod.sideStore.rawValue,
              let item = libraryGames.first(where: { $0.id == id }) else { return nil }
        if item.source == ARMSX2CoreFolders.source && armsx2Integrated { return .armsx2 }
        if item.source == MeloNXCoreFolders.source && melonxIntegrated { return .melonx }
        return nil
    }

    private func armsx2ModeMenu(_ cancel: PadMenuItem) -> PadMenuContent {
        let integrated: Bool = armsx2Integrated
        var items: [PadMenuItem] = []
        items.append(PadMenuItem(title: checked(tr("App ARMSX2 aparte (LiveContainer / SideStore)"), !integrated)) {
            armsx2ModeRaw = ARMSX2Mode.external.rawValue
            emulatorRevision += 1
            refreshLibrary()
            closePadMenu()
        })
        items.append(PadMenuItem(title: checked(tr("Núcleo integrado en OmniStation"), integrated)) {
            closePadMenu()
            guard ARMSX2Mode.integratedAvailable else {
                showToast(tr("El núcleo integrado no funciona dentro de LiveContainer: instala OmniStation con SideStore."), seconds: 4)
                return
            }
            armsx2ModeRaw = ARMSX2Mode.integrated.rawValue
            emulatorRevision += 1
            ARMSX2CoreFolders.ensure()
            refreshLibrary()
            scanCoreGames(silent: true)
        })
        items.append(cancel)
        return (tr("Modo de ARMSX2"), tr("Son caminos separados: cada uno con sus juegos y sus ajustes."), items)
    }

    private func armsx2CoreGamesMenu(_ cancel: PadMenuItem) -> PadMenuContent {
        var items: [PadMenuItem] = []
        items.append(PadMenuItem(title: tr("Volver a escanear")) {
            closePadMenu()
            scanCoreGames(silent: false)
        })
        items.append(PadMenuItem(title: tr("Importar juegos")) {
            closePadMenu()
            openCoreImporter(.coreGames)
        })
        items.append(PadMenuItem(title: tr("Abrir la carpeta en Archivos")) {
            closePadMenu()
            ARMSX2CoreFolders.ensure()
            openExternal(ARMSX2CoreFolders.filesAppURL, failure: tr("No se pudo abrir Archivos."))
        })
        items.append(cancel)
        return (tr("Juegos de ARMSX2 integrado"), "Archivos → OmniStation Dock → ARMSX2 → Juegos", items)
    }

    /// Lee ARMSX2/Juegos (carpeta local: es rápido) y sustituye los juegos del núcleo.
    private func scanCoreGames(silent: Bool) {
        ARMSX2CoreFolders.ensure()
        Task {
            let found: [LibraryGame] = await Task.detached(priority: .utility) { () -> [LibraryGame] in
                ARMSX2CoreFolders.scanGames()
            }.value
            let kept: [LibraryGame] = libraryGames.filter { $0.source != ARMSX2CoreFolders.source }
            setLibrary(kept + found)
            emulatorRevision += 1
            if !silent {
                showToast(tr("ARMSX2 integrado: %ld juegos", found.count), seconds: 3)
            }
            downloadMissingCovers()
        }
    }

    /// Copia a ARMSX2/BIOS o ARMSX2/Juegos los archivos elegidos en Archivos.
    private func importCoreFiles(_ result: Result<[URL], Error>, bios: Bool) {
        guard case .success(let urls) = result, !urls.isEmpty else { return }
        let folder: URL = bios ? ARMSX2CoreFolders.bios : ARMSX2CoreFolders.games
        showToast(bios ? tr("Copiando la BIOS…") : tr("Copiando %ld juegos…", urls.count), seconds: 60)
        Task {
            let copied: Int = await Task.detached(priority: .userInitiated) { () -> Int in
                ARMSX2CoreFolders.copy(urls, into: folder)
            }.value
            emulatorRevision += 1
            if bios {
                showToast(copied > 0 ? tr("BIOS importada") : tr("No se pudo copiar la BIOS"), seconds: 3)
            } else {
                showToast(tr("%ld juegos copiados a ARMSX2/Juegos", copied), seconds: 3)
                scanCoreGames(silent: true)
            }
        }
    }

    private func launchIntegratedARMSX2(_ game: Game, item: LibraryGame) {
        guard armsx2Integrated else {
            showToast(tr("Activa el núcleo integrado en Ajustes → ARMSX2."), seconds: 3.5)
            return
        }
        guard let file = item.fileName else {
            showToast(tr("Vuelve a escanear ARMSX2/Juegos."), seconds: 3)
            return
        }
        startIntegratedARMSX2(gamePath: ARMSX2CoreFolders.path(for: file), title: game.name, gameID: game.id)
    }

    /// Arranca el núcleo integrado (un juego o, con `gamePath` nil, la BIOS).
    private func startIntegratedARMSX2(gamePath: String?, title: String, gameID: String?) {
        guard !OSArmsx2Engine.shared.busy else { return }
        guard OSArmsx2Engine.coreBundled else {
            showToast(tr("Esta compilación no incluye el núcleo de ARMSX2."), seconds: 4)
            return
        }
        guard OSArmsx2Engine.supportedHere else {
            showToast(tr("El núcleo integrado necesita iOS 18 y OmniStation instalada con SideStore (no en LiveContainer)."), seconds: 4.5)
            return
        }
        guard OSArmsx2Engine.helperBundled else {
            showToast(tr("Falta la extensión de JIT. Reinstala OmniStation con SideStore sin quitar sus extensiones."), seconds: 5)
            return
        }
        guard let pairing = PairingFile.data() else {
            showToast(tr("Importa el archivo de emparejamiento en Ajustes → Depuración."), seconds: 4)
            return
        }
        ARMSX2CoreFolders.ensure()
        guard !ARMSX2CoreFolders.biosFiles().isEmpty else {
            showToast(tr("Falta la BIOS: impórtala en Ajustes → ARMSX2 integrado → BIOS."), seconds: 4.5)
            return
        }
        let language: String = L10n.resolve(appLanguage)
        // Ajustes de emulación (generales y, encima, los del juego) → PCSX2.ini.
        EmulatorConfig.writeARMSX2(gameID: gameID, buttonMap: gameID.flatMap { gameMeta[$0]?.buttonMap } ?? [:])
        let hostOptions: [String: String] = EmulatorConfig.armsx2HostOptions(gameID: gameID, touchHaptics: hapticsEnabled)
        // Durante la partida el mando es del juego, no de la interfaz.
        controllers.navigationEnabled = false
        SoundManager.shared.updateAmbient(volume: 0)
        EmulationActivity.shared.begin(gameID: gameID)
        showToast(tr("Activando el JIT…"), seconds: 60)
        OSArmsx2Engine.shared.launchGame(
            atPath: gamePath,
            title: title,
            dataDirectory: ARMSX2CoreFolders.data.path,
            biosDirectory: ARMSX2CoreFolders.bios.path,
            pairingData: pairing,
            language: language,
            touchControlsAlways: armsx2TouchAlways,
            hostOptions: hostOptions,
            progress: { message in
                showToast(message, seconds: 60)
            },
            completion: { success, message in
                if success {
                    toast = nil
                } else {
                    endIntegratedSession()
                    showToast(message.isEmpty ? tr("No se pudo arrancar el juego.") : message, seconds: 7)
                }
            },
            ended: {
                endIntegratedSession()
            }
        )
    }

    /// Al cerrar la partida, la interfaz vuelve a responder al mando.
    /// Ajustes de emulación de un juego de un núcleo integrado (ARMSX2, MeloNX o libretro).
    private func integratedConfigTarget(for id: String) -> EmuConfigTarget? {
        if let emulator = integratedEmulator(for: id) { return .app(emulator) }
        if let system = retroSystem(for: id) { return .retro(system) }
        return nil
    }

    // MARK: - Núcleos libretro (NES, SNES, Game Boy, GBA, NDS)

    /// Sistema libretro de un juego de la biblioteca (nil si no es de sus carpetas).
    private func retroSystem(for id: String) -> RetroSystem? {
        guard let item = libraryGames.first(where: { $0.id == id }) else { return nil }
        return RetroSystem.from(source: item.source)
    }

    /// Sistemas con algún núcleo en esta compilación.
    private var retroSystems: [RetroSystem] {
        RetroSystem.allCases.filter { $0.isAvailable }
    }

    private func scanRetroGames(silent: Bool) {
        let systems: [RetroSystem] = retroSystems
        guard !systems.isEmpty else { return }
        Task {
            let found: [LibraryGame] = await Task.detached(priority: .utility) { () -> [LibraryGame] in
                var all: [LibraryGame] = []
                for system in systems {
                    RetroFolders.ensure(system)
                    all += RetroFolders.scanGames(system)
                }
                return all
            }.value
            let kept: [LibraryGame] = libraryGames.filter { !$0.source.hasPrefix(RetroFolders.sourcePrefix) }
            setLibrary(kept + found)
            emulatorRevision += 1
            if !silent {
                showToast(tr("Núcleos clásicos: %ld juegos", found.count), seconds: 3)
            }
            downloadMissingCovers()
        }
    }

    private func launchRetro(_ game: Game, item: LibraryGame, system: RetroSystem) {
        guard !OSLibretroEngine.shared.busy, !OSArmsx2Engine.shared.busy, !OSMeloNXEngine.shared.busy else { return }
        guard let chosen = RetroConfig.core(for: system, gameID: game.id) else {
            showToast(tr("Esta compilación no incluye un núcleo para %@.", system.title), seconds: 4)
            return
        }
        guard item.fileName != nil else {
            showToast(tr("Vuelve a escanear las carpetas de los núcleos."), seconds: 3)
            return
        }
        // JIT: si el núcleo puede usarlo y OmniStation aún no lo tiene, se lo pide a su extensión
        // (instalada con SideStore). En LiveContainer vale el JIT con el que se abrió OmniStation.
        let wantsJIT: Bool = chosen.jit && RetroConfig.wantsJIT(system, gameID: game.id)
        if wantsJIT && !OSLibretroEngine.jitActive && canAskSelfJIT, let pairing = PairingFile.data() {
            // Al engancharse el depurador la app se para un instante: la música se quita antes
            // para que no se oiga entrecortada.
            SoundManager.shared.updateAmbient(volume: 0)
            showToast(tr("Activando el JIT…"), seconds: 60)
            OSMeloNXEngine.shared.prepareSharedJIT(withPairing: pairing) { success, message in
                if success {
                    RetroJIT.holding = true
                    showToast(tr("JIT activo"), seconds: 2)
                } else {
                    showToast(tr("Sin JIT (%@). El juego va en modo intérprete.", message), seconds: 5)
                }
                startRetro(game, item: item, system: system)
            }
            return
        }
        startRetro(game, item: item, system: system)
    }

    private func startRetro(_ game: Game, item: LibraryGame, system: RetroSystem) {
        guard !OSLibretroEngine.shared.busy else { return }
        // JIT de verdad ahora y el juego lo quiere (si no, el núcleo que solo va con JIT no vale).
        let jit: Bool = OSLibretroEngine.jitActive && RetroConfig.wantsJIT(system, gameID: game.id)
        guard let file = item.fileName, let core = RetroConfig.playableCore(for: system, gameID: game.id, jit: jit) else {
            showToast(tr("Este núcleo necesita JIT. Elige otro núcleo en los ajustes de %@.", system.title), seconds: 5)
            releaseRetroJIT()
            return
        }
        if let chosen = RetroConfig.core(for: system, gameID: game.id), chosen.id != core.id {
            showToast(tr("Sin JIT: se usa %@.", core.name), seconds: 3)
        }
        RetroFolders.ensure(system)
        RetroFolders.prepareSystemFiles(system)
        let options = RetroConfig.launchOptions(system, core: core, gameID: game.id, jit: jit)
        var host: [String: String] = options.host
        host["touchHaptics"] = hapticsEnabled ? "true" : "false"
        host["touchAlways"] = retroTouchAlways ? "true" : "false"
        // Mapa de botones del juego (Opciones → Mapear botones).
        for (physical, target) in gameMeta[game.id]?.buttonMap ?? [:] where physical != target {
            host["map." + physical] = target
        }
        let language: String = L10n.resolve(appLanguage)
        controllers.navigationEnabled = false
        SoundManager.shared.updateAmbient(volume: 0)
        EmulationActivity.shared.begin(gameID: game.id)
        OSLibretroEngine.shared.launchGame(
            atPath: RetroFolders.path(system, fileName: file),
            title: game.name,
            framework: core.framework,
            layout: system.touchLayout,
            systemDirectory: RetroFolders.bios(system).path,
            saveDirectory: RetroFolders.saves(system).path,
            coreOptions: options.core,
            hostOptions: host,
            language: language,
            completion: { success, message in
                if !success {
                    endIntegratedSession()
                    releaseRetroJIT()
                    showToast(message.isEmpty ? tr("No se pudo arrancar el juego.") : message, seconds: 6)
                }
            },
            ended: {
                endIntegratedSession()
                releaseRetroJIT()
            }
        )
    }

    /// ¿Se puede pedir el JIT para la propia OmniStation ahora? (SideStore con el JIT integrado,
    /// emparejamiento importado y sin saber ya que el VPN no responde.)
    private var canAskSelfJIT: Bool {
        guard usesBuiltInJIT, OSArmsx2Engine.helperBundled, BuiltInJIT.preflightProblem(lang: appLanguage) == nil else { return false }
        if case .unreachable = jitStatus.state { return false }
        return true
    }

    /// MeloNX como app aparte con SideStore: sin las claves en OmniStation no se reconocen sus juegos
    /// (en LiveContainer se cogen solas de la carpeta de MeloNX). Se avisa al abrir la app.
    private func warnMeloNXKeysIfNeeded() {
        guard !melonxIntegrated, EmulatorStore.isEnabled(.melonx),
              EmulatorStore.location(.melonx, installMethod: installMethodRaw) == .native,
              OSMeloNXEngine.runtimeBundled, !OSMeloNXEngine.keysInstalled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            showToast(tr("MeloNX: importa tus claves (prod.keys) para que OmniStation reconozca y abra sus juegos solo."), seconds: 7, actionTitle: tr("Importar"), action: {
                openCoreImporter(.melonxKeys)
            })
        }
    }

    /// Suelta el depurador que OmniStation se pidió para un núcleo libretro.
    private func releaseRetroJIT() {
        guard RetroJIT.holding else { return }
        RetroJIT.holding = false
        // Se suelta el depurador con su propio comando (si no, la próxima vez no se puede volver a
        // enganchar y la app se queda colgada) y después se cierra la extensión.
        OSLibretroEngine.detachJITDebugger()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            OSMeloNXEngine.shared.releaseSharedJIT()
        }
    }

    /// Ajustes → Emuladores → Núcleos clásicos: un elemento por sistema.
    private var retroSettings: SettingGroup? {
        _ = emulatorRevision
        let systems: [RetroSystem] = retroSystems
        guard !systems.isEmpty else { return nil }
        var items: [SettingItem] = []
        for system in systems {
            let count: Int = libraryGames.filter { $0.source == system.source }.count
            let core: String = RetroConfig.core(for: system, gameID: nil)?.name ?? ""
            items.append(SettingItem(id: "retro." + system.rawValue, title: system.title, subtitle: tr("%@ · %@/Juegos", core, system.folderName), symbol: "gamecontroller.fill", tint: SettingTint.aqua, control: .badge("\(count)", count > 0 ? Color.green : Color.gray), action: {
                activeRetroSystem = system
                dialog = .retroSystem
            }))
        }
        items.append(toggleSetting("retroTouchAlways", tr("Mando táctil siempre"), tr("Si no, se oculta al conectar un mando"), "hand.tap.fill", SettingTint.aqua, $retroTouchAlways))
        return SettingGroup(id: "retro", title: tr("Núcleos clásicos (integrados)"), isSubsection: true, items: items)
    }

    private func retroSystemMenu(_ cancel: PadMenuItem) -> PadMenuContent {
        let system: RetroSystem = activeRetroSystem
        var items: [PadMenuItem] = []
        items.append(PadMenuItem(title: tr("Ajustes de emulación")) {
            closePadMenu()
            openRetroConfig(system, gameID: nil)
        })
        items.append(PadMenuItem(title: tr("Abrir su carpeta en Archivos")) {
            closePadMenu()
            RetroFolders.ensure(system)
            if let url = RetroFolders.filesAppURL(system) { UIApplication.shared.open(url) }
        })
        items.append(PadMenuItem(title: tr("Volver a escanear")) {
            closePadMenu()
            scanRetroGames(silent: false)
        })
        items.append(cancel)
        let cores: String = system.availableCores.map(\.name).joined(separator: ", ")
        var message: String = tr("Núcleos: %@.", cores) + "\n" + tr("Pon los juegos en Archivos → OmniStation Dock → %@ → Juegos. Las partidas y estados van en %@ → Partidas.", system.folderName, system.folderName)
        if !system.biosHint.isEmpty {
            message += "\n" + tr("BIOS en %@ → BIOS. %@", system.folderName, tr(system.biosHint))
        }
        return (system.title, message, items)
    }

    private func endIntegratedSession() {
        EmulationActivity.shared.end()
        SoundManager.shared.restoreSession()
        controllers.refresh()
        controllers.navigationEnabled = true
        SoundManager.shared.updateAmbient(volume: volumeAmbient)
        emulatorRevision += 1
    }

    // MARK: - Versión del núcleo de ARMSX2 (NeoStation u OmniStation)

    private var armsx2FlavorSubtitle: String {
        _ = emulatorRevision
        let chosen: String = OSArmsx2Engine.coreFlavor == "omnistation" ? "OmniStation" : "NeoStation"
        let details: String = OSArmsx2Engine.coreFlavor == "omnistation" ? OSArmsx2Engine.omniStationCoreDetails : ""
        return details.isEmpty ? chosen : chosen + " · " + details
    }

    private func armsx2CoreFlavorMenu(_ cancel: PadMenuItem) -> PadMenuContent {
        let current: String = OSArmsx2Engine.coreFlavor
        let loaded: String = OSArmsx2Engine.loadedCoreFlavor
        var items: [PadMenuItem] = []
        let options: [(flavor: String, title: String, bundled: Bool)] = [
            ("neostation", tr("NeoStation (compilado por NeoStation iOS)"), OSArmsx2Engine.neoStationCoreBundled),
            ("omnistation", tr("OmniStation (compilado por nosotros)"), OSArmsx2Engine.omniStationCoreBundled),
        ]
        for option in options {
            let title: String = option.bundled ? option.title : option.title + " — " + tr("no incluido")
            items.append(PadMenuItem(title: checked(title, current == option.flavor)) {
                closePadMenu()
                guard option.bundled else {
                    showToast(tr("Esa versión no va en esta compilación."), seconds: 3.5)
                    return
                }
                armsx2CoreFlavorRaw = option.flavor
                emulatorRevision += 1
                if !loaded.isEmpty && loaded != option.flavor {
                    showToast(tr("Se usará al volver a abrir OmniStation (ya hay un núcleo cargado)."), seconds: 4.5)
                }
            })
        }
        items.append(cancel)
        let message: String = tr("Mismo ARMSX2 2.6; el de OmniStation se compila con LTO, como la app oficial. Prueba los dos y quédate con el que vaya mejor.")
        return (tr("Versión del núcleo"), message, items)
    }

    // MARK: - MeloNX integrado (Switch dentro de OmniStation)

    private var melonxIntegrated: Bool {
        MeloNXMode.effective(melonxModeRaw) == .integrated
    }

    private var melonxModeItem: SettingItem {
        let subtitle: String = melonxIntegrated ? tr("Integrado en OmniStation") : tr("App aparte (LiveContainer / SideStore)")
        return SettingItem(id: "melonxMode", title: tr("Modo de MeloNX"), subtitle: subtitle, symbol: "switch.2", tint: SettingTint.violet, control: .symbol("chevron.right"), action: {
            dialog = .melonxMode
        })
    }

    private var melonxCoreSettings: SettingGroup {
        _ = emulatorRevision
        var items: [SettingItem] = [melonxModeItem]
        let bundled: Bool = OSMeloNXEngine.runtimeBundled
        let version: String = OSMeloNXEngine.runtimeVersion
        let coreText: String = bundled ? "MeloNX " + (version.isEmpty ? "" : version) : tr("No incluido en esta compilación")
        items.append(SettingItem(id: "melonxCoreStatus", title: tr("Núcleo"), subtitle: coreText, symbol: "cpu", tint: SettingTint.blue, control: bundled ? .badge("OK", Color.green) : .badge(tr("FALTA"), Color.orange), action: {
            dialog = .melonxCoreHelp
        }))
        let count: Int = libraryGames.filter { $0.source == MeloNXCoreFolders.source }.count
        items.append(SettingItem(id: "melonxCoreGames", title: tr("Juegos"), subtitle: "MeloNX/Juegos", symbol: "externaldrive.fill", tint: SettingTint.blue, control: .badge("\(count)", Color.green), action: {
            dialog = .melonxCoreGames
        }))
        let keys: Bool = OSMeloNXEngine.keysInstalled
        items.append(SettingItem(id: "melonxCoreKeys", title: tr("Claves"), subtitle: keys ? (MeloNXCoreFolders.titleKeysInstalled ? "prod.keys · title.keys" : tr("prod.keys · title.keys opcional")) : tr("Importa prod.keys (y title.keys si un juego lo pide)"), symbol: "key.fill", tint: SettingTint.blue, control: keys ? .badge("OK", Color.green) : .badge(tr("FALTA"), Color.orange), action: {
            openCoreImporter(.melonxKeys)
        }))
        // La versión se lee al cargar MeloNX (al importar claves, instalar firmware o jugar).
        let firmwareText: String = melonxFirmware.isEmpty ? tr("Instala el firmware de tu Switch (zip)") : melonxFirmware
        items.append(SettingItem(id: "melonxCoreFirmware", title: tr("Firmware"), subtitle: firmwareText, symbol: "memorychip", tint: SettingTint.blue, control: melonxFirmware.isEmpty ? .symbol("plus") : .badge("OK", Color.green), action: {
            guard OSMeloNXEngine.keysInstalled else {
                showToast(tr("Primero importa tus claves (prod.keys)."), seconds: 3.5)
                return
            }
            openCoreImporter(.melonxFirmware)
        }))
        let memoryOK: Bool = OSMeloNXEngine.hasIncreasedMemoryLimit
        items.append(SettingItem(id: "melonxCoreMemory", title: tr("Memoria"), subtitle: (memoryOK ? tr("Límite ampliado") : tr("Límite normal")) + " · " + tr("libre: %@", MeloNXCoreFolders.availableMemoryText), symbol: "gauge.with.dots.needle.67percent", tint: SettingTint.blue, control: memoryOK ? .badge("OK", Color.green) : .badge(tr("NORMAL"), Color.orange), action: {
            dialog = .memoryHelp
        }))
        items.append(emulatorConfigItem(.melonx))
        items.append(toggleSetting("melonxCoreTouchAlways", tr("Mando táctil siempre"), tr("Si no, se oculta al conectar un mando"), "hand.tap.fill", SettingTint.blue, $melonxTouchAlways))
        items.append(SettingItem(id: "melonxCoreFolder", title: tr("Carpeta MeloNX"), subtitle: tr("Abrir en Archivos"), symbol: "folder.fill", tint: SettingTint.blue, control: .symbol("arrow.up.forward"), action: {
            MeloNXCoreFolders.ensure()
            openExternal(MeloNXCoreFolders.filesAppURL, failure: tr("No se pudo abrir Archivos."))
        }))
        items.append(SettingItem(id: "melonxCoreHelp", title: tr("Requisitos"), subtitle: tr("Qué necesita MeloNX integrado"), symbol: "questionmark.circle.fill", tint: SettingTint.blue, control: .symbol("chevron.right"), action: {
            dialog = .melonxCoreHelp
        }))
        return SettingGroup(id: "melonxcore", title: tr("MeloNX integrado (Switch)"), isSubsection: true, items: items)
    }

    private func melonxModeMenu(_ cancel: PadMenuItem) -> PadMenuContent {
        let integrated: Bool = melonxIntegrated
        var items: [PadMenuItem] = []
        items.append(PadMenuItem(title: checked(tr("App MeloNX aparte (LiveContainer / SideStore)"), !integrated)) {
            melonxModeRaw = MeloNXMode.external.rawValue
            emulatorRevision += 1
            refreshLibrary()
            closePadMenu()
        })
        items.append(PadMenuItem(title: checked(tr("MeloNX integrado en OmniStation"), integrated)) {
            closePadMenu()
            guard MeloNXMode.integratedAvailable else {
                showToast(tr("MeloNX integrado no funciona dentro de LiveContainer: instala OmniStation con SideStore."), seconds: 4)
                return
            }
            melonxModeRaw = MeloNXMode.integrated.rawValue
            emulatorRevision += 1
            MeloNXCoreFolders.ensure()
            refreshLibrary()
            scanMeloNXGames(silent: true)
            refreshMeloNXFirmware()
        })
        items.append(cancel)
        return (tr("Modo de MeloNX"), tr("Son caminos separados: cada uno con sus juegos y sus ajustes."), items)
    }

    private func melonxCoreGamesMenu(_ cancel: PadMenuItem) -> PadMenuContent {
        var items: [PadMenuItem] = []
        items.append(PadMenuItem(title: tr("Volver a escanear")) {
            closePadMenu()
            scanMeloNXGames(silent: false)
        })
        items.append(PadMenuItem(title: tr("Importar juegos")) {
            closePadMenu()
            openCoreImporter(.melonxGames)
        })
        items.append(PadMenuItem(title: tr("Abrir la carpeta en Archivos")) {
            closePadMenu()
            MeloNXCoreFolders.ensure()
            openExternal(MeloNXCoreFolders.filesAppURL, failure: tr("No se pudo abrir Archivos."))
        })
        items.append(cancel)
        return (tr("Juegos de MeloNX integrado"), "Archivos → OmniStation Dock → MeloNX → Juegos", items)
    }

    private func scanMeloNXGames(silent: Bool) {
        MeloNXCoreFolders.ensure()
        Task {
            let found: [LibraryGame] = await Task.detached(priority: .utility) { () -> [LibraryGame] in
                MeloNXCoreFolders.scanGames()
            }.value
            let kept: [LibraryGame] = libraryGames.filter { $0.source != MeloNXCoreFolders.source }
            setLibrary(kept + found)
            emulatorRevision += 1
            if !silent {
                showToast(tr("MeloNX integrado: %ld juegos", found.count), seconds: 3)
            }
            downloadMissingCovers()
        }
    }

    private func refreshMeloNXFirmware() {
        guard OSMeloNXEngine.runtimeBundled, OSMeloNXEngine.keysInstalled, !OSMeloNXEngine.shared.busy else { return }
        OSMeloNXEngine.shared.readFirmwareVersion { version in
            melonxFirmware = version
            emulatorRevision += 1
        }
    }

    private func importMeloNXKeys(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, !urls.isEmpty else { return }
        Task {
            let copied: Int = await Task.detached(priority: .userInitiated) { () -> Int in
                MeloNXCoreFolders.importKeys(urls)
            }.value
            let ok: Bool = OSMeloNXEngine.keysInstalled
            // Si MeloNX ya está cargado, que vuelva a leer las claves nuevas.
            if ok && copied > 0 { OSMeloNXEngine.shared.reloadKeys() }
            emulatorRevision += 1
            if copied == 0 {
                showToast(tr("No se encontró ningún archivo .keys entre los elegidos"), seconds: 3.5)
            } else if ok {
                showToast(tr("Claves importadas"), seconds: 3)
            } else {
                // Solo title.keys: se guarda, pero sigue haciendo falta prod.keys.
                showToast(tr("Guardado. Falta prod.keys (title.keys es opcional)"), seconds: 3.5)
            }
            if ok { refreshMeloNXFirmware() }
            // MeloNX como app aparte: con las claves se reconocen sus juegos.
            if ok && !melonxIntegrated && EmulatorStore.isEnabled(.melonx) { scanEmulator(.melonx, silent: true) }
        }
    }

    private func installMeloNXFirmware(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        showToast(tr("Instalando el firmware…"), seconds: 120)
        Task {
            let staged: URL? = await Task.detached(priority: .userInitiated) { () -> URL? in
                MeloNXCoreFolders.stageFirmware(url)
            }.value
            guard let staged else {
                showToast(tr("No se pudo leer el firmware."), seconds: 4)
                return
            }
            OSMeloNXEngine.shared.installFirmware(atPath: staged.path) { success, message in
                try? FileManager.default.removeItem(at: staged.deletingLastPathComponent())
                showToast(success ? tr("Firmware instalado: %@", message) : message, seconds: 5)
                refreshMeloNXFirmware()
            }
        }
    }

    private func importMeloNXGames(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, !urls.isEmpty else { return }
        showToast(tr("Copiando %ld juegos…", urls.count), seconds: 600)
        Task {
            let copied: Int = await Task.detached(priority: .userInitiated) { () -> Int in
                MeloNXCoreFolders.copy(urls, into: MeloNXCoreFolders.games)
            }.value
            showToast(tr("%ld juegos copiados a MeloNX/Juegos", copied), seconds: 3)
            scanMeloNXGames(silent: true)
        }
    }

    private func launchIntegratedMeloNX(_ game: Game, item: LibraryGame) {
        guard melonxIntegrated else {
            showToast(tr("Activa MeloNX integrado en Ajustes → MeloNX."), seconds: 3.5)
            return
        }
        guard let file = item.fileName else {
            showToast(tr("Vuelve a escanear MeloNX/Juegos."), seconds: 3)
            return
        }
        guard !OSMeloNXEngine.shared.busy, !OSArmsx2Engine.shared.busy else { return }
        guard OSMeloNXEngine.runtimeBundled else {
            showToast(tr("Esta compilación no incluye MeloNX."), seconds: 4)
            return
        }
        guard OSMeloNXEngine.supportedHere else {
            showToast(tr("MeloNX integrado necesita iOS 18 y OmniStation instalada con SideStore (no en LiveContainer)."), seconds: 4.5)
            return
        }
        guard OSMeloNXEngine.helperBundled else {
            showToast(tr("Falta la extensión de JIT. Reinstala OmniStation con SideStore sin quitar sus extensiones."), seconds: 5)
            return
        }
        guard let pairing = PairingFile.data() else {
            showToast(tr("Importa el archivo de emparejamiento en Ajustes → Depuración."), seconds: 4)
            return
        }
        guard OSMeloNXEngine.keysInstalled else {
            showToast(tr("Faltan tus claves: impórtalas en Ajustes → MeloNX integrado → Claves."), seconds: 4.5)
            return
        }
        let language: String = L10n.resolve(appLanguage)
        let path: String = MeloNXCoreFolders.path(for: file)
        // Ajustes de emulación: los generales y, encima, los de este juego.
        var settings: [String: String] = EmulatorConfig.effective(.melonx, gameID: game.id)
        // Mapa de botones del juego (Opciones → Mapear botones): «map.<físico>» = botón que manda.
        for (physical, target) in gameMeta[game.id]?.buttonMap ?? [:] where physical != target {
            settings["map." + physical] = target
        }
        controllers.navigationEnabled = false
        SoundManager.shared.updateAmbient(volume: 0)
        EmulationActivity.shared.begin(gameID: game.id)
        // La Switch es horizontal: se gira antes de abrir el juego.
        OrientationController.apply(landscape: true)
        showToast(tr("Activando el JIT…"), seconds: 60)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            OSMeloNXEngine.shared.launchGame(
                atPath: path,
                title: game.name,
                pairingData: pairing,
                language: language,
                settings: settings,
                progress: { message in
                    showToast(message, seconds: 60)
                },
                completion: { success, message in
                    if success {
                        toast = nil
                    } else {
                        endMeloNXSession()
                        showToast(message.isEmpty ? tr("No se pudo arrancar el juego.") : message, seconds: 7)
                    }
                },
                ended: {
                    endMeloNXSession()
                }
            )
        }
    }

    private func endMeloNXSession() {
        if !keepLandscape { OrientationController.apply(landscape: false) }
        endIntegratedSession()
        refreshMeloNXFirmware()
    }

    // MARK: - Carátulas automáticas

    /// Busca y descarga carátulas para los juegos que no tengan (una vez por juego).
    private func downloadMissingCovers() {
        guard autoCoversEnabled, !downloadingCovers else { return }
        // Switch sin MeloNX aparte (por ejemplo, dentro de LiveContainer): eShop o Wikipedia.
        let switchByWeb: Bool = !(EmulatorStore.isEnabled(.melonx) && EmulatorStore.location(.melonx, installMethod: installMethodRaw) == .native)
        let pending: [Game] = games.filter { game in
            let hasSource: Bool = CoverDownloader.repository(for: game.platform) != nil || (switchByWeb && game.platform == Emulator.melonx.platform)
            return game.isCustom && hasSource
                && CoverStore.shared.image(for: game.id) == nil && !CoverDownloader.wasAttempted(game.id)
        }
        guard !pending.isEmpty else { return }
        let files: [String: String] = Dictionary(libraryGames.compactMap { item in
            item.fileName.map { (item.id, $0) }
        }, uniquingKeysWith: { first, _ in first })
        var titleIDs: [String: String] = [:]
        for game in pending where game.platform == Emulator.melonx.platform {
            if let titleID = switchTitleID(game.id) { titleIDs[game.id] = titleID }
        }
        downloadingCovers = true
        Task {
            var lists: [String: [String]] = [:]
            var added: Int = 0
            for game in pending {
                if game.platform == Emulator.melonx.platform {
                    CoverDownloader.markAttempted(game.id)
                    if let data = await CoverDownloader.findCover(for: game.name, platform: game.platform, fileName: files[game.id], titleID: titleIDs[game.id]),
                       CoverStore.shared.image(for: game.id) == nil, CoverStore.shared.save(data, for: game.id) {
                        AutoCovers.mark(game.id)
                        added += 1
                        coverVersion += 1
                    }
                    continue
                }
                guard let repository = CoverDownloader.repository(for: game.platform) else { continue }
                if lists[repository] == nil {
                    lists[repository] = (try? await CoverDownloader.boxartNames(repository)) ?? []
                }
                let names: [String] = lists[repository] ?? []
                guard !names.isEmpty else { continue }
                CoverDownloader.markAttempted(game.id)
                guard let name = CoverDownloader.bestMatch(for: game.name, fileName: files[game.id], in: names),
                      let data = try? await CoverDownloader.download(repository, name: name) else { continue }
                if CoverStore.shared.image(for: game.id) == nil, CoverStore.shared.save(data, for: game.id) {
                    AutoCovers.mark(game.id)
                    added += 1
                    coverVersion += 1
                }
            }
            downloadingCovers = false
            if added > 0 { showToast(tr("%ld carátulas descargadas", added), seconds: 3) }
        }
    }

    // MARK: - Cerrar al abrir un juego

    /// Abre un juego (enlace) y, si sale bien y el ajuste está activo, cierra OmniStation.
    private func launchExternal(_ url: URL?, failure: String) {
        guard let url else { return }
        UIApplication.shared.open(url) { success in
            DispatchQueue.main.async {
                if success {
                    closeAfterLaunchIfNeeded(delay: 1.5)
                } else {
                    showToast(failure)
                }
            }
        }
    }

    /// Cierra OmniStation cuando ya está detrás del juego (si el usuario sigue en ella, no hace nada).
    private func closeAfterLaunchIfNeeded(delay: Double) {
        guard closeAfterLaunch else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard UIApplication.shared.applicationState != .active, !jitLaunching else { return }
            exit(0)
        }
    }

    private func showPendingReturnMessage() {
        guard let text = pendingReturnMessage else { return }
        pendingReturnMessage = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            showToast(text, seconds: 5)
        }
    }

    // MARK: - Emuladores (ARMSX2, MeloNX…)

    /// Juegos de la plataforma de un emulador activado (escaneados, sin acceso directo propio).
    private func emulatorFor(_ game: Game) -> Emulator? {
        guard game.launchURL == nil, game.isCustom, let emulator = Emulator.handling(platform: game.platform),
              EmulatorStore.isEnabled(emulator) else { return nil }
        return emulator
    }

    private func openInEmulator(_ game: Game, _ emulator: Emulator) {
        guard let file = libraryGames.first(where: { $0.id == game.id })?.fileName else {
            showToast(tr("Vuelve a escanear la carpeta para abrir este juego en %@", emulator.name), seconds: 4)
            return
        }
        // MeloNX abre los juegos por su Title ID: el guardado a mano o, si no, el leído del archivo.
        let detected: String? = emulator == .melonx ? SwitchAddonStore.shared.titleID(for: game.id) : nil
        let manual: String? = gameMeta[game.id]?.emulatorGameID
        var link: String = emulator.gameLink(fileName: file, title: game.name, override: manual ?? detected)
        // Lo que se escribió a mano manda; si no, el Title ID tal como lo calcula la app MeloNX.
        if emulator == .melonx, (manual ?? "").isEmpty, let exact = MeloNXIdentity.link(for: game.id) {
            link = exact
        }
        switch EmulatorStore.location(emulator, installMethod: installMethodRaw) {
        case .liveContainer:
            let folder: String = EmulatorStore.lcFolder(emulator)
            if DebugSupport.isInsideLiveContainer {
                let request: LiveContainerJIT.Request = LiveContainerJIT.request(folder: folder, openURL: link)
                if requestLiveContainerJIT(request, name: emulator.name) { return }
            }
            showToast(tr("Abriendo en %@ con JIT…", emulator.name))
            launchExternal(EmulatorLinks.liveContainerURL(appFolder: folder, gameLink: link), failure: tr("No se pudo abrir LiveContainer. ¿Está instalado?"))
        case .native:
            openEmulatorNatively(emulator, link: link, gameName: game.name)
        }
    }

    private func openEmulatorNatively(_ emulator: Emulator, link: String, gameName: String) {
        let url: URL? = URL(string: link)
        let failure: String = tr("No se pudo abrir %@. ¿Está instalado?", emulator.name)
        // Con la app StikDebug, el emulador pide el JIT por su cuenta cuando no lo tiene.
        guard usesBuiltInJIT else {
            launchExternal(url, failure: failure)
            return
        }
        if let problem = BuiltInJIT.preflightProblem(lang: appLanguage) {
            showToast(problem, seconds: 4.5)
            return
        }
        let bundle: String = EmulatorStore.bundleID(emulator)
        BuiltInJIT.isStillRunningWithJIT(bundleID: bundle) { running in
            if running {
                // Sigue abierto con JIT: el juego arranca al momento.
                launchExternal(url, failure: failure)
            } else if emulator.waitsForJIT {
                // Se abre el juego y, mientras el emulador espera, OmniStation le da el JIT.
                attachBuiltInJIT(emulator, bundleID: bundle)
                openExternal(url, failure: failure)
            } else {
                let after: String = tr("%@ ya tiene JIT. Vuelve aquí y pulsa %@ otra vez para arrancarlo.", emulator.name, gameName)
                startBuiltInJIT(bundleID: bundle, script: .automatic, name: emulator.name, afterMessage: after)
            }
        }
    }

    /// Da el JIT a un emulador que ya se está abriendo (MeloNX espera él solo a tenerlo).
    private func attachBuiltInJIT(_ emulator: Emulator, bundleID: String) {
        guard !jitLaunching else { return }
        jitLaunching = true
        BuiltInJIT.attachWhenRunning(bundleID: bundleID, appName: emulator.appName, script: .automatic) { result in
            jitLaunching = false
            switch result {
            case .success:
                jitStatus.markReady()
                closeAfterLaunchIfNeeded(delay: 0.5)
            case .failure(let error):
                let text: String = tr("No se pudo activar el JIT: %@", BuiltInJIT.message(for: error))
                pendingReturnMessage = text
                showToast(text, seconds: 7)
            }
        }
    }

    // MARK: Carpeta de juegos de cada emulador

    private func linkEmulatorFolder(_ emulator: Emulator, url: URL) {
        let accessing: Bool = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark: Data = try LibraryFolder.bookmark(for: url)
            EmulatorStore.setFolder(bookmark: bookmark, name: url.lastPathComponent, emulator)
            emulatorRevision += 1
            showToast(tr("Carpeta de %@: %@", emulator.name, url.lastPathComponent))
            scanEmulator(emulator, silent: false)
        } catch {
            showToast(tr("No se pudo vincular la carpeta"))
        }
    }

    private func unlinkEmulatorFolder(_ emulator: Emulator) {
        EmulatorStore.setFolder(bookmark: nil, name: "", emulator)
        emulatorRevision += 1
        setLibrary(libraryGames.filter { $0.source != "emu:" + emulator.rawValue })
    }

    /// Dentro de LiveContainer, con el emulador también en LiveContainer: sus juegos se leen de su
    /// carpeta por la ruta, nunca con el selector (que copia lo elegido a Inbox).
    private func usesLiveContainerFolder(_ emulator: Emulator) -> Bool {
        DebugSupport.isInsideLiveContainer
            && EmulatorStore.location(emulator, installMethod: installMethodRaw) == .liveContainer
    }

    /// Dentro de LiveContainer, carpeta de datos del emulador leída por su ruta (sin copias en Inbox).
    private func directLCFolder(_ emulator: Emulator) -> URL? {
        guard usesLiveContainerFolder(emulator) else { return nil }
        return LiveContainerStorage.gamesFolder(emulator)
    }

    private func scanEmulator(_ emulator: Emulator, silent: Bool) {
        // Dentro de LiveContainer se lee la carpeta del emulador directamente; si no se encuentra,
        // la carpeta vinculada (con el selector, que LiveContainer copia a Inbox).
        let direct: URL? = directLCFolder(emulator)
        // En LiveContainer nunca la carpeta elegida con el selector (es una copia en Inbox).
        let picked: URL? = usesLiveContainerFolder(emulator) ? nil : EmulatorStore.folderBookmark(emulator).flatMap { LibraryFolder.resolve($0) }
        guard let url = direct ?? picked else {
            if !silent {
                showToast(usesLiveContainerFolder(emulator)
                          ? tr("No se encuentra la carpeta de %@ en LiveContainer. Revisa «Carpeta en LiveContainer».", emulator.name)
                          : tr("Primero vincula una carpeta de juegos"), seconds: 4)
            }
            return
        }
        Task {
            let found: [LibraryGame] = await Task.detached(priority: .utility) { () -> [LibraryGame] in
                let accessing = direct == nil && url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                return LibraryScanner.scan(folder: url, emulator: emulator)
            }.value
            let source: String = "emu:" + emulator.rawValue
            let foundIDs: Set<String> = Set(found.map(\.id))
            // Sustituye los de este emulador; si un juego ya estaba por la carpeta general, manda este.
            let kept: [LibraryGame] = libraryGames.filter { $0.source != source && !foundIDs.contains($0.id) }
            setLibrary(kept + found)
            if !silent {
                showToast(tr("%@: %ld juegos", emulator.name, found.count), seconds: 3)
            }
            // Juegos nuevos de MeloNX: se reconocen solos. Y carátulas para los que no tengan.
            requestEmulatorLibrariesIfNeeded()
            downloadMissingCovers()
        }
    }

    // MARK: Versiones nuevas

    private func checkEmulatorUpdate(_ emulator: Emulator, manual: Bool) {
        guard !checkingEmulators.contains(emulator.rawValue) else { return }
        checkingEmulators.insert(emulator.rawValue)
        Task {
            var found: EmulatorRelease? = nil
            var failed: Bool = false
            do {
                found = try await EmulatorUpdater.latest(emulator)
            } catch {
                failed = true
            }
            checkingEmulators.remove(emulator.rawValue)
            if failed {
                if manual { showToast(tr("No se pudo consultar las versiones de %@. ¿Hay conexión?", emulator.name)) }
                return
            }
            guard let release = found else {
                if manual { showToast(tr("No hay versiones de iOS publicadas")) }
                return
            }
            EmulatorStore.remember(release, emulator)
            emulatorRevision += 1
            handleEmulatorRelease(release, emulator, manual: manual)
        }
    }

    private func handleEmulatorRelease(_ release: EmulatorRelease, _ emulator: Emulator, manual: Bool) {
        let short: String = EmulatorUpdater.shortName(release.tag)
        let installed: String = EmulatorStore.installedVersion(emulator)
        if installed.isEmpty {
            if manual {
                activeEmulator = emulator
                dialog = .emulatorUpdate
            }
            return
        }
        guard release.tag != installed else {
            if manual { showToast(tr("%@ está al día (%@)", emulator.name, short)) }
            return
        }
        if EmulatorStore.autoInstall(emulator) && !manual {
            installEmulator(emulator)
            return
        }
        if sheet == nil && dialog == nil {
            activeEmulator = emulator
            dialog = .emulatorUpdate
        } else {
            showToast(tr("%@ %@ disponible", emulator.name, short), seconds: 4)
        }
    }

    /// Manda la IPA a LiveContainer o a SideStore/AltStore para instalarla.
    private func installEmulator(_ emulator: Emulator) {
        let ipa: String = EmulatorStore.latestURL(emulator)
        guard !ipa.isEmpty else {
            checkEmulatorUpdate(emulator, manual: true)
            return
        }
        let location: Emulator.Location = EmulatorStore.location(emulator, installMethod: installMethodRaw)
        let urls: [URL] = EmulatorLinks.installURLs(ipa: ipa, location: location)
        let tag: String = EmulatorStore.latestTag(emulator)
        openFirst(urls) { success in
            if success {
                EmulatorStore.setInstalledVersion(tag, emulator)
                emulatorRevision += 1
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
        if detailGameID == game.id { detailGameID = nil }
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

    /// Un solo selector de Archivos (iOS solo presenta uno por vista): carpetas o, para una
    /// carátula, imágenes.
    private var importerTypes: [UTType] {
        switch importerPurpose {
        case .folder: return [.folder]
        case .cover: return [.image]
        case .coreBIOS, .coreGames, .melonxKeys, .melonxGames: return [.data]
        case .melonxFirmware: return [.zip, .data, .folder]
        }
    }

    private var importerMultiple: Bool {
        importerPurpose == .coreBIOS || importerPurpose == .coreGames || importerPurpose == .melonxKeys || importerPurpose == .melonxGames
    }

    private func openFolderImporter() {
        importerPurpose = .folder
        showFolderImporter = true
    }

    private func openCoreImporter(_ purpose: ImporterPurpose) {
        importerPurpose = purpose
        showFolderImporter = true
    }

    private func handleFolderPick(_ result: Result<[URL], Error>) {
        let purpose: ImporterPurpose = importerPurpose
        importerPurpose = .folder
        switch purpose {
        case .cover(let coverID):
            applyCoverFile(result, id: coverID)
            return
        case .coreBIOS:
            importCoreFiles(result, bios: true)
            return
        case .coreGames:
            importCoreFiles(result, bios: false)
            return
        case .melonxKeys:
            importMeloNXKeys(result)
            return
        case .melonxFirmware:
            installMeloNXFirmware(result)
            return
        case .melonxGames:
            importMeloNXGames(result)
            return
        case .folder:
            break
        }
        let emulatorTarget: Emulator? = folderPickEmulator
        folderPickEmulator = nil
        guard case .success(let urls) = result, let url = urls.first else { return }
        if let emulatorTarget {
            linkEmulatorFolder(emulatorTarget, url: url)
            return
        }
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
            openFolderImporter()
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
            // Sustituye los escaneados y conserva los accesos directos y los de cada emulador.
            let emulatorIDs: Set<String> = Set(libraryGames.filter { $0.source.hasPrefix("emu:") }.map(\.id))
            setLibrary(libraryGames.filter { $0.source != "scan" } + found.filter { !emulatorIDs.contains($0.id) })
            isScanning = false
            showToast(found.isEmpty ? tr("No se encontraron juegos en la carpeta") : tr("Escaneo completo: %ld juegos", found.count), seconds: 3.2)
            downloadMissingCovers()
        }
    }

    // MARK: - Barra superior

    private func topBar(compact: Bool) -> some View {
        HStack(spacing: 0) {
            // El título y el planeta se desvanecen al deslizar; solo ellos se repintan.
            HeaderTitle(progress: scrollProgress, size: 20)
            Spacer(minLength: 6)
            if isLandscapeNow {
                HeaderPlanet(progress: scrollProgress, size: compact ? 30 : 34)
            } else {
                // En vertical, en el centro, el indicador de JIT (en horizontal va junto a las pestañas).
                JITIndicatorDot(active: jitIndicatorOn)
                    .onTapGesture { explainJITIndicator() }
            }
            Spacer(minLength: 6)
            if isLandscapeNow {
                JITIndicatorDot(active: jitIndicatorOn)
                    .onTapGesture { explainJITIndicator() }
                    .padding(.trailing, 8)
            }
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
                .background {
                    if isSelected {
                        shape.fill(Color.cyan.opacity(0.35)).blur(radius: 12).allowsHitTesting(false)
                    }
                }
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

    /// En horizontal se enseña el teclado entero y la pantalla se queda fija mientras se escribe
    /// (antes seguía cada tecla y la pantalla se movía al bajar de fila).
    private func scrollToLetter(_ proxy: ScrollViewProxy) {
        if isLandscapeNow {
            proxy.scrollTo("alphabet-bar", anchor: .center)
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
        // En Búsqueda la barra y el teclado ocupan la parte de arriba: la fila se centra.
        if selectedSection == .busqueda {
            if row == lastRow && row > 0 {
                proxy.scrollTo("screen-bottom", anchor: .bottom)
            } else {
                proxy.scrollTo(id, anchor: .center)
            }
            return
        }
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
            guard selectedSection != .busqueda, let id = controllerSelectedGameID,
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

                if libraryGames.isEmpty {
                    notice
                } else if list.isEmpty {
                    emptyResults
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
                launch(game)
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
            // Brillo solo en la elegida (una sombra en cada filtro se calculaba siempre).
            .background {
                if isSelected {
                    Capsule().fill(Color.cyan.opacity(0.25)).blur(radius: 8).allowsHitTesting(false)
                }
            }
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

    /// Solo los grupos de la parte elegida de Ajustes (así cada pantalla es corta y clara).
    private var settingGroups: [SettingGroup] {
        switch settingsCategory {
        case .general: return [generalSettings, screenSettings, appearanceSettings]
        case .library: return [gameSettings, artworkSettings]
        case .emulators: return emulatorGroups
        case .system: return [debugSettings, liveContainerSettings]
        }
    }

    private func selectSettingsCategory(_ category: SettingsCategory) {
        guard category != settingsCategory else { return }
        settingsCategory = category
        controllerSelectedSettingIndex = 0
        controllerSelectedArea = "settings"
        feedback(.navigate)
    }

    private func cycleSettingsCategory(_ step: Int) {
        let all: [SettingsCategory] = SettingsCategory.allCases
        guard let index = all.firstIndex(of: settingsCategory) else { return }
        selectSettingsCategory(all[(index + step + all.count) % all.count])
    }

    /// Botones de las partes de Ajustes (L1/R1 con el mando).
    private var settingsCategoryBar: some View {
        HStack(spacing: 8) {
            ForEach(SettingsCategory.allCases, id: \.self) { category in
                let active: Bool = category == settingsCategory
                Button {
                    selectSettingsCategory(category)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: category.symbol)
                            .font(.system(size: 12, weight: .semibold))
                        Text(tr(category.title))
                            .font(AppFont.text(13, .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(active ? Color.black : Color.white.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(active ? Color.cyan : Color.white.opacity(0.07), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(TapHighlightButtonStyle(cornerRadius: 20))
            }
        }
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
        items.append(SettingItem(id: "language", title: tr("Idioma"), subtitle: languageLabel, symbol: "globe", tint: SettingTint.sky, control: .symbol("chevron.up.chevron.down"), action: {
            dialog = .language
        }))
        items.append(toggleSetting("closeAfterLaunch", tr("Cerrar al abrir un juego"), tr("Solo con juegos de otras apps (enlaces y LiveContainer): OmniStation se cierra detrás"), "xmark.app.fill", SettingTint.sky, $closeAfterLaunch))
        items.append(toggleSetting("haptics", tr("Vibración"), tr("Al tocar y en el mando táctil de ARMSX2"), "iphone.radiowaves.left.and.right", SettingTint.sky, $hapticsEnabled))
        items.append(toggleSetting("sound", tr("Sonido al pulsar"), tr("Sonidos de navegación y selección"), "speaker.wave.2.fill", SettingTint.periwinkle, $clickSound))
        items.append(SettingItem(id: "about", title: tr("Acerca de"), subtitle: tr("Versión %@", appVersion), symbol: "info.circle.fill", tint: Color.cyan, control: .symbol("chevron.right"), action: {
            showAbout = true
        }))
        return SettingGroup(id: "general", title: tr("General"), items: items)
    }

    /// Modo Dock, orientación y tele (AirPlay / HDMI).
    private var screenSettings: SettingGroup {
        var items: [SettingItem] = []
        items.append(toggleSetting("dock", tr("Modo Dock"), tr("Carrusel al girar a horizontal"), "tv.fill", SettingTint.blue, $dockModeEnabled))
        items.append(toggleSetting("dockFull", tr("Dock a pantalla completa"), tr("Usa todo el ancho en horizontal"), "arrow.left.and.right", SettingTint.sky, $dockFullWidth))
        items.append(toggleSetting("hdmi", tr("Dock con HDMI"), tr("Activa Dock y horizontal al conectar HDMI"), "display", SettingTint.aqua, $hdmiAutoLandscape))
        items.append(toggleSetting("tvGame", tr("Juego en la tele"), tr("AirPlay o HDMI: el juego a pantalla completa y el iPhone de mando"), "airplayvideo", SettingTint.aqua, $tvGameOutput))
        items.append(toggleSetting("landscape", tr("Bloquear horizontal"), tr("Mantener la app en horizontal"), "iphone.landscape", SettingTint.periwinkle, $keepLandscape))
        items.append(toggleSetting("clock", tr("Reloj 24 horas"), tr("Formato de la hora en Dock"), "clock.fill", SettingTint.sky, $clock24h))
        return SettingGroup(id: "screen", title: tr("Pantalla y tele"), items: items)
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
            if folderName.isEmpty { openFolderImporter() } else { dialog = .externalFolder }
        }))
        items.append(SettingItem(id: "shortcut", title: tr("Acceso directo (URL)"), subtitle: tr("Abre un juego, app o emulador, o añade un acceso a una App de LiveContainer"), symbol: "link.badge.plus", tint: SettingTint.blue, control: .symbol("plus"), action: {
            shortcutMode = 0
            sheet = .addShortcut
        }))
        let emulatorCount: Int = Emulator.allCases.filter { EmulatorStore.isEnabled($0) }.count
        let integratedNames: [String] = integratedEmulators.map { tr("%@ integrado", $0.name) }
        let emulatorsSubtitle: String = integratedNames.isEmpty ? tr("Qué tienes instalado y sus carpetas") : integratedNames.joined(separator: " · ")
        items.append(SettingItem(id: "emulators", title: tr("Emuladores"), subtitle: emulatorsSubtitle, symbol: "cpu.fill", tint: SettingTint.blue, control: .badge("\(emulatorCount)", Color.cyan), action: {
            sheet = .emulatorSetup
        }))
        items.append(SettingItem(id: "achievements", title: tr("Logros"), subtitle: raSubtitle, symbol: "trophy.fill", tint: Color.yellow, control: raControl, action: {
            sheet = .retroAccount
        }))
        items.append(SettingItem(id: "clearFavorites", title: tr("Borrar favoritos"), subtitle: tr("Quita todos los marcados"), symbol: "star.slash.fill", tint: Color.orange, control: .badge("\(favoriteCount)", Color.orange), action: {
            if !favoriteNames.isEmpty { dialog = .clearFavorites }
        }))
        items.append(SettingItem(id: "library", title: tr("Juegos añadidos"), subtitle: tr("Ver y quitar uno a uno"), symbol: "list.bullet.rectangle.fill", tint: Color.orange, control: .badge("\(libraryCount)", Color.orange), action: {
            sheet = .libraryList
        }))
        return SettingGroup(id: "games", title: tr("Juegos"), items: items)
    }

    /// Carátulas y fondos de la pantalla de cada juego.
    private var artworkSettings: SettingGroup {
        _ = emulatorRevision
        var items: [SettingItem] = []
        items.append(SettingItem(id: "autoCovers", title: tr("Carátulas automáticas"), subtitle: autoCoversEnabled ? tr("Se descargan solas") : tr("Desactivadas"), symbol: "photo.stack.fill", tint: SettingTint.blue, control: downloadingCovers ? .progress : .toggle(autoCoversEnabled), action: {
            autoCoversEnabled.toggle()
            if autoCoversEnabled {
                CoverDownloader.resetAttempts()
                downloadMissingCovers()
            }
        }))
        let sgdb: Bool = SteamGridDB.isConfigured
        items.append(SettingItem(id: "steamGridDB", title: tr("Fondos y logos HD"), subtitle: sgdb ? "SteamGridDB" : tr("Pega tu clave gratuita de SteamGridDB"), symbol: "photo.artframe", tint: SettingTint.violet, control: sgdb ? .badge("OK", Color.green) : .symbol("key.fill"), action: {
            sheet = .textEntry(.steamGridKey)
        }))
        return SettingGroup(id: "artwork", title: tr("Carátulas y fondos"), isSubsection: true, items: items)
    }

    private func folderSettingControl(linked: Bool) -> SettingControl {
        if isScanning { return SettingControl.progress }
        if linked { return SettingControl.badge("\(scannedCount)", Color.green) }
        return SettingControl.plain
    }

    private func emulatorSettings(_ emulator: Emulator) -> SettingGroup {
        _ = emulatorRevision
        let key: String = emulator.rawValue
        let location: Emulator.Location = EmulatorStore.location(emulator, installMethod: installMethodRaw)
        let enabled = Binding<Bool>(get: { EmulatorStore.isEnabled(emulator) }, set: { value in
            EmulatorStore.setEnabled(value, emulator)
            emulatorRevision += 1
        })
        let autoCheck = Binding<Bool>(get: { EmulatorStore.autoCheck(emulator) }, set: { value in
            EmulatorStore.setAutoCheck(value, emulator)
            emulatorRevision += 1
        })
        let autoInstall = Binding<Bool>(get: { EmulatorStore.autoInstall(emulator) }, set: { value in
            EmulatorStore.setAutoInstall(value, emulator)
            emulatorRevision += 1
        })
        var items: [SettingItem] = []
        if emulator == .armsx2 { items.append(armsx2ModeItem) }
        if emulator == .melonx { items.append(melonxModeItem) }
        items.append(toggleSetting(key + "On", tr("%@ con %@", emulator.platform, emulator.name), tr("Abre sus juegos directamente"), emulator.symbol, SettingTint.blue, enabled))
        items.append(emulatorFolderItem(emulator))
        let whereText: String = location == .liveContainer ? "LiveContainer" : tr("SideStore / AltStore")
        items.append(SettingItem(id: key + "Where", title: tr("Instalado en"), subtitle: whereText, symbol: "shippingbox.fill", tint: SettingTint.blue, control: .symbol("chevron.right"), action: {
            activeEmulator = emulator
            dialog = .emulatorLocation
        }))
        if location == .liveContainer {
            items.append(SettingItem(id: key + "LC", title: tr("Carpeta en LiveContainer"), subtitle: EmulatorStore.lcFolder(emulator), symbol: "folder.badge.gearshape", tint: SettingTint.blue, control: .symbol("pencil"), action: {
                sheet = .textEntry(.lcFolder(emulator))
            }))
        } else {
            items.append(SettingItem(id: key + "Bundle", title: tr("Bundle ID"), subtitle: EmulatorStore.bundleID(emulator), symbol: "number", tint: SettingTint.blue, control: .symbol("pencil"), action: {
                activeEmulator = emulator
                dialog = .emulatorBundle
            }))
        }
        if emulator == .melonx && location == .native {
            // Con las claves, OmniStation reconoce y abre solos los juegos de la app MeloNX.
            let keys: Bool = OSMeloNXEngine.keysInstalled
            items.append(SettingItem(id: key + "Keys", title: tr("Claves"), subtitle: keys ? tr("Los juegos se reconocen solos") : tr("Importa prod.keys para que los juegos se reconozcan solos"), symbol: "key.fill", tint: SettingTint.blue, control: keys ? .badge("OK", Color.green) : .badge(tr("FALTA"), Color.orange), action: {
                openCoreImporter(.melonxKeys)
            }))
        }
        if emulator == .melonx {
            items.append(SettingItem(id: key + "Help", title: tr("Cómo funciona"), subtitle: tr("Juegos, actualizaciones y DLC"), symbol: "questionmark.circle.fill", tint: SettingTint.blue, control: .symbol("chevron.right"), action: {
                activeEmulator = emulator
                dialog = .emulatorHelp
            }))
        }
        if location == .native {
            items.append(SettingItem(id: key + "Library", title: tr("Leer biblioteca de %@", emulator.name), subtitle: tr("Reconoce títulos y carátulas"), symbol: "books.vertical.fill", tint: SettingTint.blue, control: .symbol("arrow.up.forward"), action: {
                if emulator == .melonx { requestMeloNXLibrary() } else { requestARMSX2Library() }
            }))
        }
        items.append(SettingItem(id: key + "Version", title: tr("Versión"), subtitle: emulatorVersionSubtitle(emulator), symbol: "arrow.triangle.2.circlepath", tint: SettingTint.blue, control: emulatorVersionControl(emulator), action: {
            activeEmulator = emulator
            dialog = .emulatorUpdate
        }))
        items.append(toggleSetting(key + "Check", tr("Buscar versiones nuevas"), tr("Al abrir la app"), "bell.badge.fill", SettingTint.blue, autoCheck))
        items.append(toggleSetting(key + "AutoInstall", tr("Instalar sin preguntar"), tr("Abre el instalador al detectarla"), "square.and.arrow.down.fill", SettingTint.blue, autoInstall))
        return SettingGroup(id: key, title: emulator.name + " (" + emulator.platform + ")", isSubsection: true, items: items)
    }

    private func emulatorFolderItem(_ emulator: Emulator) -> SettingItem {
        let name: String = EmulatorStore.folderName(emulator)
        let count: Int = libraryGames.filter { $0.source == "emu:" + emulator.rawValue }.count
        if usesLiveContainerFolder(emulator) {
            let found: Bool = directLCFolder(emulator) != nil
            return SettingItem(id: emulator.rawValue + "Games", title: tr("Juegos"), subtitle: found ? tr("Su carpeta de LiveContainer") : tr("No se encuentra su carpeta en LiveContainer"), symbol: "externaldrive.fill", tint: SettingTint.blue, control: found ? .badge("\(count)", Color.green) : .badge("!", Color.orange), action: {
                activeEmulator = emulator
                dialog = .emulatorFolder
            })
        }
        let control: SettingControl = name.isEmpty ? SettingControl.symbol("plus") : SettingControl.badge("\(count)", Color.green)
        let subtitle: String = name.isEmpty ? tr("La misma que uses en el emulador") : name
        return SettingItem(id: emulator.rawValue + "Games", title: tr("Carpeta de juegos"), subtitle: subtitle, symbol: "externaldrive.fill", tint: SettingTint.blue, control: control, action: {
            activeEmulator = emulator
            dialog = .emulatorFolder
        })
    }

    private func emulatorVersionSubtitle(_ emulator: Emulator) -> String {
        let latestTag: String = EmulatorStore.latestTag(emulator)
        let installed: String = EmulatorStore.installedVersion(emulator)
        if latestTag.isEmpty { return tr("Sin comprobar") }
        let latest: String = EmulatorUpdater.shortName(latestTag)
        if installed.isEmpty { return tr("Última: %@", latest) }
        if installed == latestTag { return tr("Al día: %@", latest) }
        return tr("Nueva: %@", latest)
    }

    private func emulatorVersionControl(_ emulator: Emulator) -> SettingControl {
        if checkingEmulators.contains(emulator.rawValue) { return SettingControl.progress }
        let latestTag: String = EmulatorStore.latestTag(emulator)
        let installed: String = EmulatorStore.installedVersion(emulator)
        if !latestTag.isEmpty && !installed.isEmpty && latestTag != installed {
            return SettingControl.badge(tr("NUEVA"), Color.green)
        }
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
        if method == .sideStore {
            items.append(jitEnablerSettingItem())
            if usesBuiltInJIT {
                items.append(builtInJITSettingItem())
            }
            items.append(pairingSettingItem())
        }
        // El JIT de la propia OmniStation solo hace falta con StikDebug; el integrado da JIT a los juegos.
        if !usesBuiltInJIT {
            items.append(SettingItem(id: "jitStatus", title: tr("Estado JIT"), subtitle: jitEnabled ? tr("Activo en esta app") : tr("No activo en esta app"), symbol: "cpu", tint: SettingTint.violet, control: jitControl, action: {
                refreshJITStatus(announce: true)
            }))
            items.append(SettingItem(id: "enableJIT", title: tr("Activar JIT"), subtitle: tr("Con StikDebug, en esta app"), symbol: "bolt.fill", tint: SettingTint.violet, control: .symbol("arrow.up.forward"), action: {
                openExternal(DebugSupport.enableJITURL, failure: stikFailure)
            }))
        }
        items.append(SettingItem(id: "copyBundle", title: tr("Copiar Bundle ID"), subtitle: DebugSupport.bundleID, symbol: "doc.on.doc.fill", tint: SettingTint.violet, control: .plain, action: {
            UIPasteboard.general.string = DebugSupport.bundleID
            showToast(tr("Bundle ID copiado"))
        }))
        return SettingGroup(id: "debug", title: tr("Depuración"), items: items)
    }

    private func builtInJITSettingItem() -> SettingItem {
        let subtitle: String
        let control: SettingControl
        switch jitStatus.state {
        case .ready:
            subtitle = tr("Listo para tus juegos")
            control = SettingControl.badge("ON", Color.green)
        case .preparing:
            subtitle = tr("Preparando…")
            control = SettingControl.progress
        case .unreachable:
            subtitle = tr("Activa la VPN LocalDevVPN")
            control = SettingControl.badge("VPN", Color.orange)
        case .failed:
            subtitle = tr("No listo: toca para ver el motivo")
            control = SettingControl.badge(tr("ERROR"), Color.red)
        case .idle:
            subtitle = PairingFile.exists ? tr("Se prepara solo al abrir la app") : tr("Falta el archivo de emparejamiento")
            control = SettingControl.symbol("chevron.right")
        }
        return SettingItem(id: "jitSetup", title: tr("JIT integrado"), subtitle: subtitle, symbol: "bolt.shield.fill", tint: SettingTint.violet, control: control, action: {
            sheet = .jitSetup
        })
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
        let statusControl: SettingControl = inside ? .badge(tr("DENTRO"), Color.green) : .badge(tr("FUERA"), Color.gray)
        var items: [SettingItem] = []
        items.append(SettingItem(id: "lcStatus", title: tr("Estado"), subtitle: statusText, symbol: "shippingbox.fill", tint: SettingTint.aqua, control: statusControl, action: {
            showToast(statusText)
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
                    .padding(.bottom, 2)
                settingsCategoryBar
                    .padding(.bottom, 2)
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
            // Vista aparte y comparable: al mover la selección solo se repintan las tarjetas que cambian.
            SettingCardLabel(title: item.title, subtitle: item.subtitle, symbol: item.symbol, tint: item.tint, control: item.control)
                .equatable()
                .contentShape(shape)
        }
        .buttonStyle(TapHighlightButtonStyle(cornerRadius: 18))
        .id("setting-\(index)")
        .padRing(isSettingSelected(index), cornerRadius: 18)
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
            DockStatus(use24h: clock24h, jitActive: jitIndicatorOn, onJITTap: { explainJITIndicator() })
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
                Text(tr("Aún no hay juegos. Vincula una carpeta, importa juegos a los núcleos integrados o añade accesos directos en Ajustes → Biblioteca."))
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
private enum SettingControl: Equatable {
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

/// Tarjeta de un ajuste (solo el dibujo; el botón y su acción los pone HomeView).
private struct SettingCardLabel: View, Equatable {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let control: SettingControl

    /// Tarjeta de ajuste: icono arriba, control a la derecha (interruptor, etiqueta...) y texto debajo.
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Spacer(minLength: 4)
                settingControl(control)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppFont.text(14, .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(subtitle)
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

    private func settingBadge(_ text: String, tint: Color = Color.cyan) -> some View {
        Text(text)
            .font(AppFont.text(9, .bold))
            .tracking(0.6)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.14), in: Capsule())
    }
}
