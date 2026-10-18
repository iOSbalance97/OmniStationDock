import SwiftUI

// MARK: - Pantalla del juego (antes de jugar)

/// Lo que puede marcar el mando en la pantalla del juego.
enum GameDetailFocus: Int {
    case play = 0
    case options = 1
    case favorite = 2
    case back = 3
    /// Botón de la descripción (solo en horizontal).
    case info = 4
}

/// Pantalla intermedia al elegir un juego, con «Jugar» y «Opciones».
/// Vertical: carátula, nombre, plataforma y descripción. Horizontal: una imagen del juego de
/// fondo a pantalla completa, el nombre en el centro y los botones debajo; la descripción
/// se abre con su botón (al lado del de favorito). Arriba, volver (también ○).
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
    /// Descripción abierta (en horizontal).
    let showDescription: Bool
    /// Para buscar la imagen de fondo: archivo del juego y, en Switch, su Title ID.
    var fileName: String? = nil
    var titleID: String? = nil
    var onPlay: () -> Void
    var onOptions: () -> Void
    var onFavorite: () -> Void
    var onBack: () -> Void
    var onToggleDescription: () -> Void

    @State private var summary: String?
    @State private var loading = true
    @State private var backdropImage: UIImage?

    private func tr(_ key: String) -> String { L10n.tr(key, lang) }

    private static let coverRatio: CGFloat = 1.12

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
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
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
            guard backdropImage == nil else { return }
            backdropImage = await BackdropStore.shared.image(id: game.id, name: game.name, platform: game.platform, fileName: fileName, titleID: titleID)
        }
    }

    // MARK: Fondo

    @ViewBuilder
    private func backdrop(_ size: CGSize) -> some View {
        if landscape {
            landscapeBackdrop
        } else {
            blurredBackdrop
        }
    }

    /// Horizontal: imagen del juego a pantalla completa (si aún no hay, la carátula difuminada).
    private var landscapeBackdrop: some View {
        ZStack {
            Color(red: 0.01, green: 0.02, blue: 0.06)
            if let backdropImage {
                Image(uiImage: backdropImage)
                    .resizable()
                    .scaledToFill()
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
                    .transition(.opacity)
            } else if let cover {
                Image(uiImage: cover)
                    .resizable()
                    .scaledToFill()
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .blur(radius: 30)
                    .opacity(0.6)
                    .clipped()
            } else {
                LinearGradient(colors: [game.tint.opacity(0.55), Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            // Oscurece el centro y los bordes para que se lean el nombre y los botones.
            RadialGradient(
                colors: [Color.black.opacity(0.55), Color.black.opacity(0.25), Color.black.opacity(0.6)],
                center: .center,
                startRadius: 10,
                endRadius: 700
            )
            LinearGradient(
                colors: [Color.black.opacity(0.45), Color.clear, Color.black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .animation(.easeOut(duration: 0.35), value: backdropImage != nil)
        .ignoresSafeArea()
        // Recoge los toques: lo de detrás de la pantalla del juego no debe responder.
        .contentShape(Rectangle())
        .onTapGesture {}
    }

    private var blurredBackdrop: some View {
        ZStack {
            Color(red: 0.01, green: 0.02, blue: 0.06)
            if let cover {
                Image(uiImage: cover)
                    .resizable()
                    .scaledToFill()
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .blur(radius: 38)
                    .opacity(0.55)
                    .clipped()
            } else {
                LinearGradient(colors: [game.tint.opacity(0.55), Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            LinearGradient(
                colors: [Color.black.opacity(0.25), Color.black.opacity(0.55), Color.black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture {}
    }

    // MARK: Barra de arriba

    private var topBar: some View {
        let infoSymbol: String = showDescription ? "text.alignleft" : "text.justify.left"
        let infoColor: Color = showDescription ? Color.cyan : Color.white
        let starSymbol: String = isFavorite ? "star.fill" : "star"
        let starColor: Color = isFavorite ? Color.yellow : Color.white
        let starLabel: String = isFavorite ? tr("Quitar de favoritos") : tr("Añadir a favoritos")
        return HStack(spacing: 12) {
            circleButton("chevron.left", color: Color.white, selected: focus == .back, label: tr("Volver"), action: onBack)
            Spacer()
            if landscape {
                circleButton(infoSymbol, color: infoColor, selected: focus == .info, label: tr("Descripción"), action: onToggleDescription)
            }
            circleButton(starSymbol, color: starColor, selected: focus == .favorite, label: starLabel, action: onFavorite)
        }
        .padding(.horizontal, landscape ? 28 : 18)
        .padding(.top, landscape ? 14 : 8)
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

    // MARK: Vertical

    private func portraitLayout(_ size: CGSize) -> some View {
        let coverWidth: CGFloat = min(size.width * 0.62, 320)
        return VStack(spacing: 16) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    coverView(width: coverWidth)
                        .padding(.top, 64)
                    titleBlock(centered: true)
                    descriptionBlock
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 12)
            }
            buttons
                .padding(.horizontal, 22)
                .padding(.bottom, 18)
        }
    }

    // MARK: Horizontal (con y sin Dock)

    /// Nombre centrado, un poco por encima de la mitad, y los botones debajo.
    private func landscapeLayout(_ size: CGSize) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 64)
            VStack(spacing: dock ? 18 : 14) {
                landscapeTitle
                buttons
                    .frame(maxWidth: dock ? 520 : 440)
                if showDescription {
                    descriptionPanel(maxHeight: size.height * 0.34)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.horizontal, dock ? 64 : 44)
            Spacer(minLength: 12)
            Color.clear
                .frame(height: showDescription ? 8 : size.height * 0.12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.22), value: showDescription)
    }

    private var landscapeTitle: some View {
        VStack(spacing: 8) {
            Text(game.name)
                .font(AppFont.text(dock ? 38 : 30, .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .shadow(color: Color.black.opacity(0.7), radius: 12)
            HStack(spacing: 6) {
                Image(systemName: Platforms.symbol(for: game.platform))
                    .font(.system(size: dock ? 15 : 13, weight: .semibold))
                Text(Platforms.fullName(for: game.platform))
                    .font(AppFont.text(dock ? 16 : 14, .semibold))
            }
            .foregroundStyle(Color.cyan)
            .shadow(color: Color.black.opacity(0.7), radius: 8)
        }
        .frame(maxWidth: .infinity)
    }

    private func descriptionPanel(maxHeight: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        // Alto fijo: con texto, el máximo (se desliza dentro); mientras busca o sin texto, una línea.
        let height: CGFloat = summary == nil ? 60 : maxHeight
        return ScrollView(showsIndicators: false) {
            descriptionBlock
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
        }
        .frame(maxWidth: dock ? 720 : 620)
        .frame(height: height)
        .background(Color.black.opacity(0.35), in: shape)
        .liquidGlass(in: shape)
    }

    // MARK: Piezas

    private func coverView(width: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        let height: CGFloat = width * Self.coverRatio
        return ZStack {
            if let cover {
                Image(uiImage: cover)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
            } else {
                LinearGradient(
                    colors: [game.tint.opacity(0.85), Color(red: 0.015, green: 0.055, blue: 0.14)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: game.symbol)
                    .font(.system(size: width * 0.32, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
            }
        }
        .frame(width: width, height: height)
        .clipShape(shape)
        .glassRim(in: shape)
        .background {
            shape.fill(Color.cyan.opacity(0.28)).blur(radius: 18)
        }
    }

    private func titleBlock(centered: Bool) -> some View {
        let textAlignment: TextAlignment = centered ? .center : .leading
        let alignment: HorizontalAlignment = centered ? .center : .leading
        let frameAlignment: Alignment = centered ? .center : .leading
        return VStack(alignment: alignment, spacing: 6) {
            Text(game.name)
                .font(AppFont.text(dock ? 30 : 24, .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(textAlignment)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
            HStack(spacing: 6) {
                Image(systemName: Platforms.symbol(for: game.platform))
                    .font(.system(size: dock ? 14 : 12, weight: .semibold))
                Text(Platforms.fullName(for: game.platform))
                    .font(AppFont.text(dock ? 15 : 13, .semibold))
            }
            .foregroundStyle(Color.cyan)
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
    }

    @ViewBuilder
    private var descriptionBlock: some View {
        if let summary {
            Text(summary)
                .font(AppFont.text(dock ? 14 : 12))
                .foregroundStyle(.white.opacity(0.78))
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

    private var buttons: some View {
        HStack(spacing: 12) {
            playButton
            optionsButton
        }
    }

    private var playButton: some View {
        let shape = Capsule()
        let blue: Color = Color(red: 0.05, green: 0.45, blue: 1.0)
        return Button(action: onPlay) {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                Text(tr("Jugar"))
            }
            .font(AppFont.text(dock ? 17 : 15, .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, dock ? 17 : 15)
            .background(LinearGradient(colors: [blue, Color.cyan.opacity(0.9)], startPoint: .leading, endPoint: .trailing), in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8))
            .contentShape(shape)
            .padRing(gamepadConnected && focus == .play, cornerRadius: 30)
        }
        .buttonStyle(ControllerFocusableButtonStyle())
    }

    private var optionsButton: some View {
        let shape = Capsule()
        return Button(action: onOptions) {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                Text(tr("Opciones"))
            }
            .font(AppFont.text(dock ? 17 : 15, .bold))
            .foregroundStyle(Color.cyan)
            .frame(maxWidth: .infinity)
            .padding(.vertical, dock ? 17 : 15)
            .contentShape(shape)
            .liquidGlass(in: shape, interactive: true)
            .padRing(gamepadConnected && focus == .options, cornerRadius: 30)
        }
        .buttonStyle(ControllerFocusableButtonStyle())
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
