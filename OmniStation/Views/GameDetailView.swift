import SwiftUI

// MARK: - Pantalla del juego (antes de jugar)

/// Lo que puede marcar el mando en la pantalla del juego.
enum GameDetailFocus: Int {
    case play = 0
    case options = 1
    case favorite = 2
    case back = 3
    /// Descripción (debajo de los botones): la abre entera.
    case info = 4
}

/// Pantalla de presentación de cada juego, con «Jugar» y «Opciones».
/// Horizontal: el fondo panorámico del juego a pantalla completa; abajo a la izquierda su logo,
/// la plataforma y los botones; abajo a la derecha una tarjeta con sus datos (última partida,
/// tiempo jugado, tamaño, emulador y ajustes). Vertical: lo mismo, apilado.
/// Arriba: volver (también ○) y favorito. La descripción se abre tocándola.
struct GameDetailView: View {
    let game: Game
    let cover: UIImage?
    let isFavorite: Bool
    let lang: String
    let landscape: Bool
    /// Modo Dock (pantalla grande): todo algo más grande.
    let dock: Bool
    let gamepadConnected: Bool
    let focus: GameDetailFocus
    /// Descripción abierta.
    let showDescription: Bool
    /// Para buscar la imagen de fondo: archivo del juego y, en Switch, su Title ID.
    var fileName: String? = nil
    var titleID: String? = nil
    /// Ruta del archivo del juego (para su tamaño), si está en el iPhone.
    var filePath: String? = nil
    /// Con qué se juega («ARMSX2 integrado», «MeloNX»…).
    var emulatorLabel: String? = nil
    /// Núcleo integrado: ¿tiene ajustes propios? (nil: no aplica).
    var hasOwnSettings: Bool? = nil
    var onPlay: () -> Void
    var onOptions: () -> Void
    var onFavorite: () -> Void
    var onBack: () -> Void
    var onToggleDescription: () -> Void

    @State private var summary: String?
    @State private var loading = true
    @State private var backdropImage: UIImage?
    @State private var logoImage: UIImage?
    @State private var fileSize: Int64?

    private func tr(_ key: String) -> String { L10n.tr(key, lang) }

    private static let playGradient: [Color] = [
        Color(red: 0.36, green: 0.42, blue: 1.0),
        Color(red: 0.56, green: 0.46, blue: 0.98)
    ]

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                backdrop(geometry.size)
                if landscape {
                    landscapeLayout(geometry.size)
                } else {
                    portraitLayout(geometry.size)
                }
                topBar
                if showDescription {
                    descriptionOverlay(geometry.size)
                        .transition(.opacity)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .animation(.easeOut(duration: 0.22), value: showDescription)
        }
        .task(id: game.id + "|" + game.name) {
            loading = true
            summary = nil
            let language: String = L10n.resolve(lang)
            summary = await GameDescriptions.text(name: game.name, platform: game.platform, language: language)
            loading = false
        }
        .task(id: game.id) {
            backdropImage = BackdropStore.shared.cached(for: game.id)
            logoImage = GameLogoStore.shared.cached(for: game.id)
            if let filePath {
                let path: String = filePath
                fileSize = await Task.detached(priority: .utility) { () -> Int64? in
                    let attributes = try? FileManager.default.attributesOfItem(atPath: path)
                    return (attributes?[.size] as? NSNumber)?.int64Value
                }.value
            }
            if backdropImage == nil || BackdropStore.shared.wantsUpgrade(game.id) {
                if let found = await BackdropStore.shared.image(id: game.id, name: game.name, platform: game.platform, fileName: fileName, titleID: titleID) {
                    backdropImage = found
                }
            }
            if logoImage == nil {
                logoImage = await GameLogoStore.shared.logo(id: game.id, name: game.name)
            }
        }
    }

    // MARK: Fondo

    @ViewBuilder
    private func backdrop(_ size: CGSize) -> some View {
        ZStack {
            Color(red: 0.01, green: 0.02, blue: 0.06)
            if landscape {
                artwork
                    .frame(width: size.width, height: size.height)
                    .clipped()
                // A la izquierda y abajo, más oscuro: ahí van el logo, los botones y los datos.
                LinearGradient(colors: [Color.black.opacity(0.85), Color.black.opacity(0.35), Color.clear],
                               startPoint: .leading, endPoint: UnitPoint(x: 0.7, y: 0.5))
                LinearGradient(colors: [Color.black.opacity(0.35), Color.clear, Color.black.opacity(0.7)],
                               startPoint: .top, endPoint: .bottom)
            } else {
                VStack(spacing: 0) {
                    artwork
                        .frame(width: size.width, height: size.height * 0.46)
                        .clipped()
                        .overlay {
                            LinearGradient(colors: [Color.black.opacity(0.3), Color.clear, Color(red: 0.01, green: 0.02, blue: 0.06)],
                                           startPoint: .top, endPoint: .bottom)
                        }
                    Spacer(minLength: 0)
                }
            }
        }
        .animation(.easeOut(duration: 0.35), value: backdropImage != nil)
        .ignoresSafeArea()
        // Recoge los toques: lo de detrás de la pantalla del juego no debe responder.
        .contentShape(Rectangle())
        .onTapGesture {}
    }

    /// Fondo panorámico; si aún no hay, la carátula difuminada; si tampoco, el color del juego.
    @ViewBuilder
    private var artwork: some View {
        if let backdropImage {
            Image(uiImage: backdropImage)
                .resizable()
                .scaledToFill()
                .transition(.opacity)
        } else if let cover {
            Image(uiImage: cover)
                .resizable()
                .scaledToFill()
                .blur(radius: 30)
                .opacity(0.6)
        } else {
            LinearGradient(colors: [game.tint.opacity(0.55), Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    // MARK: Barra de arriba

    private var topBar: some View {
        let starSymbol: String = isFavorite ? "star.fill" : "star"
        let starColor: Color = isFavorite ? Color.yellow : Color.white
        let starLabel: String = isFavorite ? tr("Quitar de favoritos") : tr("Añadir a favoritos")
        return HStack(spacing: 12) {
            backButton
            Spacer()
            circleButton(starSymbol, color: starColor, selected: focus == .favorite, label: starLabel, action: onFavorite)
        }
        .padding(.horizontal, landscape ? 28 : 18)
        .padding(.top, landscape ? 14 : 8)
    }

    private var backButton: some View {
        let height: CGFloat = dock ? 50 : 44
        return Button(action: onBack) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: dock ? 17 : 15, weight: .bold))
                Text(tr("Biblioteca"))
                    .font(AppFont.text(dock ? 16 : 14, .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: height)
            .contentShape(Capsule())
            .liquidGlass(in: Capsule(), interactive: true)
            .padRing(gamepadConnected && focus == .back, cornerRadius: height / 2)
        }
        .buttonStyle(ControllerFocusableButtonStyle())
        .accessibilityLabel(tr("Volver"))
    }

    private func circleButton(_ symbol: String, color: Color, selected: Bool, label: String, action: @escaping () -> Void) -> some View {
        let side: CGFloat = dock ? 50 : 44
        return Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: dock ? 20 : 17, weight: .bold))
                .foregroundStyle(color)
                .frame(width: side, height: side)
                .contentShape(Circle())
                .liquidGlass(in: Circle(), interactive: true)
                .padRing(gamepadConnected && selected, cornerRadius: side / 2)
        }
        .buttonStyle(ControllerFocusableButtonStyle())
        .accessibilityLabel(label)
    }

    // MARK: Horizontal (con y sin Dock)

    private func landscapeLayout(_ size: CGSize) -> some View {
        let leftWidth: CGFloat = min(size.width * 0.42, dock ? 520 : 440)
        let cardWidth: CGFloat = min(size.width * 0.32, dock ? 400 : 330)
        return VStack(spacing: 0) {
            Spacer(minLength: 70)
            HStack(alignment: .bottom, spacing: 24) {
                VStack(alignment: .leading, spacing: dock ? 14 : 11) {
                    titleArt(maxWidth: leftWidth * 0.78, maxHeight: dock ? 130 : 104, centered: false)
                    platformCaption
                    buttons
                        .frame(maxWidth: leftWidth)
                    notes
                }
                .frame(width: leftWidth, alignment: .leading)
                Spacer(minLength: 0)
                infoCard
                    .frame(width: cardWidth)
            }
            .padding(.horizontal, dock ? 52 : 34)
            .padding(.bottom, dock ? 34 : 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Vertical

    private func portraitLayout(_ size: CGSize) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                Color.clear.frame(height: size.height * 0.30)
                titleArt(maxWidth: size.width * 0.7, maxHeight: 96, centered: false)
                platformCaption
                buttons
                notes
                infoCard
                if let summary {
                    Button(action: onToggleDescription) {
                        Text(summary)
                            .font(AppFont.text(12))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineSpacing(3)
                            .lineLimit(6)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .contentShape(Rectangle())
                            .padRing(gamepadConnected && focus == .info, cornerRadius: 12)
                    }
                    .buttonStyle(ControllerFocusableButtonStyle())
                    .padding(.top, 2)
                    .accessibilityLabel(tr("Descripción"))
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
        }
    }

    // MARK: Piezas

    /// Logo del juego (SteamGridDB) o, si no hay, su nombre.
    @ViewBuilder
    private func titleArt(maxWidth: CGFloat, maxHeight: CGFloat, centered: Bool) -> some View {
        if let logoImage {
            Image(uiImage: logoImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: maxWidth, maxHeight: maxHeight, alignment: .leading)
                .shadow(color: Color.black.opacity(0.6), radius: 12)
                .transition(.opacity)
        } else {
            Text(game.name)
                .font(AppFont.text(dock ? 34 : (landscape ? 28 : 26), .bold))
                .foregroundStyle(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                .shadow(color: Color.black.opacity(0.7), radius: 12)
                .frame(maxWidth: maxWidth, alignment: .leading)
        }
    }

    private var platformCaption: some View {
        let parts: [String] = [Platforms.fullName(for: game.platform)] + (emulatorLabel.map { [$0] } ?? [])
        return HStack(spacing: 6) {
            Image(systemName: Platforms.symbol(for: game.platform))
                .font(.system(size: dock ? 14 : 12, weight: .semibold))
            Text(parts.joined(separator: " · "))
                .font(AppFont.text(dock ? 15 : 13, .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.78))
        .shadow(color: Color.black.opacity(0.7), radius: 8)
    }

    /// Una o dos líneas bajo los botones (como los avisos de la pantalla de Steam).
    @ViewBuilder
    private var notes: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let first = summaryFirstSentence {
                // Tocarla (o ✕ con ella marcada) abre la descripción entera.
                Button(action: onToggleDescription) {
                    noteLine("info.circle.fill", first, color: Color.white.opacity(0.75))
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .contentShape(Rectangle())
                        .padRing(gamepadConnected && focus == .info, cornerRadius: 10)
                }
                .buttonStyle(ControllerFocusableButtonStyle())
                .accessibilityLabel(tr("Descripción"))
            }
            if hasOwnSettings == true {
                noteLine("slider.horizontal.3", tr("Este juego tiene su propia configuración del emulador."), color: Color.cyan.opacity(0.9))
            }
        }
    }

    private func noteLine(_ symbol: String, _ text: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(AppFont.text(dock ? 13 : 11, .medium))
                .lineLimit(2)
        }
        .foregroundStyle(color)
        .shadow(color: Color.black.opacity(0.7), radius: 6)
    }

    private var summaryFirstSentence: String? {
        guard landscape, let summary, !summary.isEmpty else { return nil }
        if let end = summary.range(of: ". ") {
            return String(summary[..<end.lowerBound]) + "."
        }
        return summary
    }

    // MARK: Tarjeta de datos

    private var infoRows: [(String, String)] {
        var rows: [(String, String)] = []
        if let last = PlayStats.lastPlayed(game.id) {
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = Locale(identifier: L10n.resolve(lang) == "en" ? "en_US" : "es_ES")
            formatter.unitsStyle = .short
            rows.append((tr("Última partida"), formatter.localizedString(for: last, relativeTo: Date())))
        } else {
            rows.append((tr("Última partida"), tr("Nunca")))
        }
        let seconds: TimeInterval = PlayStats.playTime(game.id)
        if seconds > 0 {
            let hours: Double = seconds / 3600
            let text: String = hours >= 1 ? String(format: "%.1f h", hours) : String(format: "%.0f min", max(1, seconds / 60))
            rows.append((tr("Tiempo jugado"), text))
        }
        if let fileSize, fileSize > 0 {
            rows.append((tr("Tamaño"), ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)))
        }
        rows.append((tr("Plataforma"), Platforms.fullName(for: game.platform)))
        if let emulatorLabel {
            rows.append((tr("Emulador"), emulatorLabel))
        }
        if let hasOwnSettings {
            rows.append((tr("Ajustes"), hasOwnSettings ? tr("Propios") : tr("Generales")))
        }
        return rows
    }

    private var infoCard: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let rows: [(String, String)] = infoRows
        return VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { index in
                HStack {
                    Text(rows[index].0)
                        .font(AppFont.text(dock ? 14 : 12, .medium))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer(minLength: 8)
                    Text(rows[index].1)
                        .font(AppFont.text(dock ? 14 : 12, .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .padding(.vertical, dock ? 10 : 8)
                if index < rows.count - 1 {
                    Divider().overlay(Color.white.opacity(0.08))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.35), in: shape)
        .liquidGlass(in: shape)
    }

    // MARK: Descripción

    private func descriptionOverlay(_ size: CGSize) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { onToggleDescription() }
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(game.name)
                        .font(AppFont.text(dock ? 20 : 17, .bold))
                        .foregroundStyle(.white)
                    descriptionBlock
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
            }
            .frame(maxWidth: dock ? 760 : 640)
            .frame(maxHeight: size.height * (landscape ? 0.62 : 0.55))
            .fixedSize(horizontal: false, vertical: true)
            .background(Color.black.opacity(0.4), in: shape)
            .liquidGlass(in: shape)
            .padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    private var descriptionBlock: some View {
        if let summary {
            Text(summary)
                .font(AppFont.text(dock ? 14 : 12))
                .foregroundStyle(.white.opacity(0.8))
                .lineSpacing(3)
                .multilineTextAlignment(.leading)
        } else if loading {
            HStack(spacing: 8) {
                ProgressView()
                    .tint(Color.cyan)
                Text(tr("Buscando descripción…"))
                    .font(AppFont.text(11, .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
        } else {
            Text(tr("Sin descripción disponible."))
                .font(AppFont.text(12, .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: Botones

    private var buttons: some View {
        HStack(spacing: 12) {
            playButton
            optionsButton
        }
    }

    private var playButton: some View {
        let shape = Capsule()
        return Button(action: onPlay) {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                Text(tr("Jugar"))
            }
            .font(AppFont.text(dock ? 17 : 15, .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, dock ? 17 : 14)
            .background(LinearGradient(colors: Self.playGradient, startPoint: .leading, endPoint: .trailing), in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8))
            .shadow(color: Self.playGradient[0].opacity(0.45), radius: 14, y: 4)
            .contentShape(shape)
            .padRing(gamepadConnected && focus == .play, cornerRadius: 30)
        }
        .buttonStyle(ControllerFocusableButtonStyle())
        .layoutPriority(1)
    }

    private var optionsButton: some View {
        let shape = Capsule()
        return Button(action: onOptions) {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                Text(tr("Opciones"))
                    .lineLimit(1)
            }
            .fixedSize()
            .font(AppFont.text(dock ? 16 : 14, .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, dock ? 22 : 18)
            .padding(.vertical, dock ? 17 : 14)
            .contentShape(shape)
            .liquidGlass(in: shape, interactive: true)
            .padRing(gamepadConnected && focus == .options, cornerRadius: 30)
        }
        .buttonStyle(ControllerFocusableButtonStyle())
        .fixedSize()
    }
}

// MARK: - Descripción de los juegos (Wikipedia)

/// Busca un resumen del juego en Wikipedia (en el idioma de la app; si no hay, en inglés)
/// y lo guarda en el iPhone para no buscarlo otra vez.
enum GameDescriptions {
    private struct Response: Decodable {
        struct Query: Decodable {
            let pages: [Page]?
        }
        struct Page: Decodable {
            let title: String
            let extract: String?
        }
        let query: Query?
    }

    /// Búsquedas sin resultado en esta sesión (no se repiten hasta reabrir la app).
    private static var misses: Set<String> = []

    private static func cacheURL(_ key: String) -> URL {
        AppFolders.folder("Descriptions").appendingPathComponent(AppFolders.safeName(key) + ".txt")
    }

    /// ¿Ya hay descripción guardada? (para que el mando pueda bajar hasta ella).
    static func hasCached(name: String, language: String) -> Bool {
        let key: String = language + "|" + name
        return FileManager.default.fileExists(atPath: cacheURL(key).path)
    }

    static func text(name: String, platform: String, language: String) async -> String? {
        let key: String = language + "|" + name
        if let cached = try? String(contentsOf: cacheURL(key), encoding: .utf8), !cached.isEmpty {
            return cached
        }
        if misses.contains(key) { return nil }
        var found: String? = await search(name: name, platform: platform, language: language)
        if found == nil && language != "en" {
            found = await search(name: name, platform: platform, language: "en")
        }
        guard let found else {
            misses.insert(key)
            return nil
        }
        try? found.write(to: cacheURL(key), atomically: true, encoding: .utf8)
        return found
    }

    private static func search(name: String, platform: String, language: String) async -> String? {
        let words: [String] = MeloNXLibrary.normalized(name)
        guard !words.isEmpty else { return nil }
        let suffix: String = language == "es" ? " videojuego" : " video game"
        var components = URLComponents()
        components.scheme = "https"
        components.host = language + ".wikipedia.org"
        components.path = "/w/api.php"
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
            URLQueryItem(name: "generator", value: "search"),
            URLQueryItem(name: "gsrsearch", value: words.joined(separator: " ") + suffix),
            URLQueryItem(name: "gsrlimit", value: "1"),
            URLQueryItem(name: "prop", value: "extracts"),
            URLQueryItem(name: "exintro", value: "1"),
            URLQueryItem(name: "explaintext", value: "1"),
            URLQueryItem(name: "redirects", value: "1")
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("OmniStationDock/0.3 (iOS)", forHTTPHeaderField: "User-Agent")
        guard let result = try? await URLSession.shared.data(for: request),
              let response = try? JSONDecoder().decode(Response.self, from: result.0),
              let page = response.query?.pages?.first,
              let extract = page.extract, !extract.isEmpty else { return nil }
        // Que la página sea de verdad de ese juego: el título debe parecerse al nombre.
        guard looksLike(page.title, name) else { return nil }
        return trimmed(extract)
    }

    private static func looksLike(_ title: String, _ name: String) -> Bool {
        let a: Set<String> = Set(MeloNXLibrary.normalized(title))
        let b: Set<String> = Set(MeloNXLibrary.normalized(name))
        guard !a.isEmpty, !b.isEmpty else { return false }
        let common: Double = Double(a.intersection(b).count)
        return common / Double(b.count) >= 0.5
    }

    /// Hasta unos 900 caracteres, cortando al final de una frase.
    private static func trimmed(_ text: String) -> String {
        let clean: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count > 900 else { return clean }
        let limit: String = String(clean.prefix(900))
        if let end = limit.range(of: ". ", options: .backwards) {
            return String(limit[..<end.lowerBound]) + "."
        }
        return limit + "…"
    }
}
