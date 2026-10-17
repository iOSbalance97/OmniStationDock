import SwiftUI
import UniformTypeIdentifiers

// MARK: - Piezas comunes de las ventanas

extension View {
    /// Estilo de todas las ventanas que se abren desde abajo.
    func padSheetStyle(large: Bool = false) -> some View {
        let detents: Set<PresentationDetent> = large ? [.large] : [.medium, .large]
        return self
            .presentationDetents(detents)
            .presentationBackground(.ultraThinMaterial)
            .preferredColorScheme(.dark)
    }
}

struct SheetActionButton: View {
    let title: String
    var tint: Color = Color.cyan
    var selected: Bool = false
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Button(action: action) {
            Text(title)
                .font(AppFont.text(15, .semibold))
                .foregroundStyle(enabled ? tint : Color.white.opacity(0.35))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .contentShape(shape)
                .liquidGlass(in: shape, interactive: true)
                .padRing(selected, cornerRadius: 14)
        }
        .buttonStyle(ControllerFocusableButtonStyle())
        .disabled(!enabled)
    }
}

struct SheetCaption: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(AppFont.text(11, .bold))
            .tracking(1.4)
            .foregroundStyle(Color.cyan.opacity(0.85))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SheetInfoCard: View {
    let symbol: String
    let text: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Color.cyan)
            Text(text)
                .font(AppFont.text(13, .medium))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .glassCard()
    }
}

/// Movimiento en una cuadrícula. Devuelve nil si se sale por arriba o por abajo
/// (para que la ventana pase la selección a otra zona).
enum PadGrid {
    static func move(_ index: Int, count: Int, columns: Int, _ action: PadAction) -> Int? {
        switch action {
        case .left:
            return index % columns == 0 ? index : index - 1
        case .right:
            return (index % columns == columns - 1 || index + 1 >= count) ? index : index + 1
        case .up:
            return index - columns >= 0 ? index - columns : nil
        case .down:
            if index + columns < count { return index + columns }
            let lastRow: Int = (count - 1) / columns
            return index / columns < lastRow ? count - 1 : nil
        default:
            return index
        }
    }
}

// MARK: - Teclado QWERTY para el mando

enum PadKeys {
    static let columns = 10
    private static let base: [String] = Array("1234567890QWERTYUIOPASDFGHJKLÑ").map(String.init)
    /// Búsqueda: mayúsculas y tecla para borrar todo.
    static let search: [String] = base + ["Z", "X", "C", "V", "B", "N", "M", "␣", "⌫", "✕"]
    /// Escribir nombres: con mayúsculas/minúsculas.
    static let text: [String] = base + ["⇧", "Z", "X", "C", "V", "B", "N", "M", "␣", "⌫"]
    /// Bundle ID (JIT): minúsculas, punto, guion y guion bajo.
    static let bundle: [String] = Array("1234567890qwertyuiopasdfghjkl.zxcvbnm-_").map(String.init) + ["⌫"]
    /// Números (ID de RetroAchievements).
    static let digits: [String] = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "⌫", "0", "✓"]

    static func isLetter(_ key: String) -> Bool {
        key.count == 1 && key.uppercased() != key.lowercased()
    }

    /// Aplica una tecla al texto. Con `autoCapitalize`, la primera letra de cada palabra va en mayúscula.
    static func apply(_ key: String, to text: inout String, shift: inout Bool, autoCapitalize: Bool) {
        switch key {
        case "⌫":
            if !text.isEmpty { text.removeLast() }
            if autoCapitalize { shift = text.isEmpty || text.hasSuffix(" ") }
        case "✕":
            text = ""
            shift = autoCapitalize
        case "␣":
            text += " "
            if autoCapitalize { shift = true }
        case "⇧":
            shift.toggle()
        case "✓":
            break
        default:
            if autoCapitalize && isLetter(key) {
                text += shift ? key : key.lowercased()
                shift = false
            } else {
                text += key
            }
        }
    }
}

struct PadKeyboardView: View {
    let keys: [String]
    var columns: Int = PadKeys.columns
    var selectedIndex: Int?
    var lowercase: Bool = false
    /// Si se indica, cada tecla lleva el id "<prefijo><índice>" (para que la pantalla la siga).
    var idPrefix: String? = nil
    var onKey: (Int) -> Void

    /// Filas fijas (no perezosas): todas las teclas existen siempre y cuadran con el mando.
    private var rows: [[Int]] {
        stride(from: 0, to: keys.count, by: columns).map { first in
            Array(first..<min(first + columns, keys.count))
        }
    }

    var body: some View {
        VStack(spacing: 5) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                keyRow(rows[rowIndex])
            }
        }
    }

    private func keyRow(_ row: [Int]) -> some View {
        let empty: Int = max(0, columns - row.count)
        return HStack(spacing: 5) {
            ForEach(row, id: \.self) { index in
                identified(keyButton(index), index)
            }
            ForEach(0..<empty, id: \.self) { _ in
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 1)
            }
        }
    }

    @ViewBuilder
    private func identified<V: View>(_ view: V, _ index: Int) -> some View {
        if let idPrefix {
            view.id(idPrefix + String(index))
        } else {
            view
        }
    }

    private func keyButton(_ index: Int) -> some View {
        let key: String = keys[index]
        let isSelected: Bool = selectedIndex == index
        let label: String = (lowercase && PadKeys.isLetter(key)) ? key.lowercased() : key
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        return Button {
            onKey(index)
        } label: {
            Text(label)
                .font(AppFont.text(14, .bold))
                // Orbitron es ancha: la letra encoge si la tecla es estrecha, nunca se corta.
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .padding(.horizontal, 2)
                .foregroundStyle(isSelected ? Color.black : Color.white)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(isSelected ? Color.cyan : Color.white.opacity(0.08), in: shape)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Cambiar nombre

struct RenameGameSheet: View {
    let lang: String
    @ObservedObject var pad: SheetPad
    let initialName: String
    var title: String = "Cambiar nombre"
    var placeholder: String = "Nombre del juego"
    /// Para escribir un Bundle ID: teclado en minúsculas, sin mayúscula automática y se puede dejar vacío.
    var bundleMode: Bool = false
    var onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var shift = false
    // 0..<40 teclas, 40 = Cancelar, 41 = Guardar.
    @State private var selected = 0

    private func tr(_ key: String) -> String { L10n.tr(key, lang) }

    private var keys: [String] { bundleMode ? PadKeys.bundle : PadKeys.text }
    private var cancelIndex: Int { keys.count }
    private var saveIndex: Int { keys.count + 1 }
    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool {
        if bundleMode { return cleanName.isEmpty || JITLauncher.isValidBundleID(cleanName) }
        return !cleanName.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    TextField(tr(placeholder), text: $name)
                        .font(AppFont.text(17, .semibold))
                        .textInputAutocapitalization(bundleMode ? .never : .words)
                        .autocorrectionDisabled(bundleMode)
                        .padding(14)
                        .glassCard(cornerRadius: 14)
                    PadKeyboardView(
                        keys: keys,
                        selectedIndex: pad.gamepadConnected && selected < keys.count ? selected : nil,
                        lowercase: bundleMode || !shift,
                        onKey: { index in press(index) }
                    )
                    HStack(spacing: 10) {
                        SheetActionButton(title: tr("Cancelar"), tint: Color.white.opacity(0.85), selected: pad.gamepadConnected && selected == cancelIndex) {
                            dismiss()
                        }
                        SheetActionButton(title: tr("Guardar"), selected: pad.gamepadConnected && selected == saveIndex, enabled: canSave) {
                            save()
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle(tr(title))
            .navigationBarTitleDisplayMode(.inline)
        }
        .padSheetStyle(large: true)
        .onAppear {
            name = initialName
            shift = !bundleMode && initialName.isEmpty
            pad.handler = { action in
                handle(action)
                return true
            }
        }
        .onDisappear { pad.handler = nil }
    }

    private func press(_ index: Int) {
        guard keys.indices.contains(index) else { return }
        selected = index
        PadKeys.apply(keys[index], to: &name, shift: &shift, autoCapitalize: !bundleMode)
    }

    private func save() {
        guard canSave else { return }
        onSave(cleanName)
        dismiss()
    }

    private func handle(_ action: PadAction) {
        switch action {
        case .cancel:
            dismiss()
        case .accept:
            if selected < keys.count {
                press(selected)
            } else if selected == cancelIndex {
                dismiss()
            } else {
                save()
            }
        default:
            move(action)
        }
    }

    private func move(_ action: PadAction) {
        if selected < keys.count {
            if let next = PadGrid.move(selected, count: keys.count, columns: PadKeys.columns, action) {
                selected = next
            } else if action == .down {
                selected = saveIndex
            }
            return
        }
        switch action {
        case .left: selected = cancelIndex
        case .right: selected = saveIndex
        case .up: selected = keys.count - 1
        default: break
        }
    }
}

// MARK: - Logros del juego (RetroAchievements)

struct GameAchievementsSheet: View {
    let lang: String
    @ObservedObject var pad: SheetPad
    let gameName: String
    let platform: String
    let initialGameID: Int?
    var onSaveGameID: (Int?) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var gameID: Int?
    @State private var editingID = false
    @State private var idText = ""
    @State private var progress: RAGameProgress?
    @State private var loading = false
    @State private var errorText: String?
    // Búsqueda del juego en RetroAchievements.
    @State private var matches: [RAGameMatch] = []
    @State private var searching = false
    @State private var searchMessage: String?
    // Con el mando, al elegir juego: 0 = resultados, 1 = teclado numérico.
    @State private var entryZone = 0
    @State private var matchIndex = 0
    @State private var keyIndex = 0
    // Con el mando, en la lista: 0 = botón «Cambiar juego», 1... = logros.
    @State private var selected = 0

    private func tr(_ key: String, _ args: CVarArg...) -> String {
        let base = L10n.tr(key, lang)
        return args.isEmpty ? base : String(format: base, arguments: args)
    }

    private var configured: Bool { RetroAchievements.isConfigured }
    private var showingEntry: Bool { configured && (editingID || gameID == nil) }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 14) {
                        content
                    }
                    .padding(16)
                }
                .onChange(of: selected) { _, value in
                    withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo("row-\(value)", anchor: .center) }
                }
                .onChange(of: matchIndex) { _, value in
                    withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo("match-\(value)", anchor: .center) }
                }
            }
            .navigationTitle(tr("Logros"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .padSheetStyle(large: true)
        .onAppear {
            gameID = initialGameID
            idText = initialGameID.map { String($0) } ?? ""
            pad.handler = { action in
                handle(action)
                return true
            }
            if configured && initialGameID == nil {
                Task { await search() }
            }
        }
        .onDisappear { pad.handler = nil }
        .task(id: gameID) {
            await load()
        }
    }

    @ViewBuilder
    private var content: some View {
        if !configured {
            SheetInfoCard(symbol: "trophy", text: tr("Inicia sesión en RetroAchievements en Ajustes → Juegos → Logros."))
        } else if showingEntry {
            searchSection
            idEntry
        } else {
            changeButton
                .id("row-0")
            if loading {
                ProgressView()
                    .tint(Color.cyan)
                    .padding(30)
            } else if let errorText {
                SheetInfoCard(symbol: "exclamationmark.triangle", text: errorText)
            } else if let progress {
                progressHeader(progress)
                achievementList(progress)
            }
        }
    }

    // MARK: Elegir el juego

    private var searchSection: some View {
        VStack(spacing: 8) {
            SheetCaption(text: tr("¿Cuál es este juego en RetroAchievements?"))
            Text(gameName + " · " + platform)
                .font(AppFont.text(12, .medium))
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
            if searching {
                ProgressView()
                    .tint(Color.cyan)
                    .padding(16)
            } else if let searchMessage {
                Text(searchMessage)
                    .font(AppFont.text(12, .medium))
                    .foregroundStyle(Color.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(matches.indices, id: \.self) { index in
                matchRow(index)
                    .id("match-\(index)")
            }
        }
    }

    private func matchRow(_ index: Int) -> some View {
        let match: RAGameMatch = matches[index]
        let isSelected: Bool = pad.gamepadConnected && entryZone == 0 && matchIndex == index
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Button {
            choose(match)
        } label: {
            HStack(spacing: 12) {
                AsyncImage(url: match.iconURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.white.opacity(0.08)
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(match.title)
                        .font(AppFont.text(13, .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(tr("%ld logros", match.achievements) + " · ID \(match.id)")
                        .font(AppFont.text(10, .semibold))
                        .foregroundStyle(Color.cyan)
                }
                Spacer(minLength: 0)
                if index == 0 && match.score >= 0.9 {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color.green)
                }
            }
            .padding(10)
            .contentShape(shape)
            .glassCard(cornerRadius: 16)
            .padRing(isSelected, cornerRadius: 16)
        }
        .buttonStyle(ControllerFocusableButtonStyle())
    }

    private var idEntry: some View {
        VStack(spacing: 12) {
            SheetCaption(text: tr("O escribe su ID"))
            Text(tr("Es el número de la dirección de su página, por ejemplo retroachievements.org/game/1234."))
                .font(AppFont.text(11, .medium))
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(idText.isEmpty ? "—" : idText)
                .font(AppFont.text(24, .bold))
                .frame(maxWidth: .infinity)
                .padding(12)
                .glassCard(cornerRadius: 14)
            PadKeyboardView(
                keys: PadKeys.digits,
                columns: 3,
                selectedIndex: pad.gamepadConnected && entryZone == 1 ? keyIndex : nil,
                onKey: { index in pressDigit(index) }
            )
            .frame(maxWidth: 280)
        }
    }

    // MARK: Lista de logros

    private var changeButton: some View {
        let label: String = gameID.map { tr("Cambiar juego (ID %@)", String($0)) } ?? ""
        return SheetActionButton(title: label, selected: pad.gamepadConnected && selected == 0) {
            startEditing()
        }
    }

    private func progressHeader(_ progress: RAGameProgress) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: progress.iconURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.white.opacity(0.08)
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(progress.title.isEmpty ? gameName : progress.title)
                    .font(AppFont.text(16, .bold))
                    .lineLimit(2)
                Text(progress.console)
                    .font(AppFont.text(11, .medium))
                    .foregroundStyle(.white.opacity(0.6))
                Text(progressSummary(progress))
                    .font(AppFont.text(12, .semibold))
                    .foregroundStyle(Color.cyan)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .glassCard()
    }

    private func progressSummary(_ progress: RAGameProgress) -> String {
        let count: String = tr("%ld de %ld logros", progress.awarded, progress.total)
        if progress.completion.isEmpty { return count }
        return count + " · " + progress.completion
    }

    private func achievementList(_ progress: RAGameProgress) -> some View {
        VStack(spacing: 8) {
            if progress.achievements.isEmpty {
                SheetInfoCard(symbol: "trophy", text: tr("Este juego no tiene logros."))
            }
            ForEach(progress.achievements.indices, id: \.self) { index in
                achievementRow(progress.achievements[index], selected: pad.gamepadConnected && selected == index + 1)
                    .id("row-\(index + 1)")
            }
        }
    }

    private func achievementRow(_ item: RAAchievement, selected isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: item.badgeURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.white.opacity(0.08)
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .saturation(item.earned ? 1 : 0)
            .opacity(item.earned ? 1 : 0.55)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(AppFont.text(13, .bold))
                    .foregroundStyle(item.earned ? Color.white : Color.white.opacity(0.7))
                Text(item.description)
                    .font(AppFont.text(11))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(3)
                Text(achievementDetail(item))
                    .font(AppFont.text(10, .semibold))
                    .foregroundStyle(item.earned ? Color.cyan : Color.white.opacity(0.45))
            }
            Spacer(minLength: 0)
            if item.earned {
                Image(systemName: item.earnedHardcore ? "checkmark.seal.fill" : "checkmark.circle.fill")
                    .foregroundStyle(item.earnedHardcore ? Color.yellow : Color.green)
            }
        }
        .padding(11)
        .glassCard(cornerRadius: 16)
        .padRing(isSelected, cornerRadius: 16)
    }

    private func achievementDetail(_ item: RAAchievement) -> String {
        let points: String = tr("%ld puntos", item.points)
        guard item.earned else { return points }
        return points + " · " + tr("Conseguido %@", item.dateEarned)
    }

    // MARK: Acciones

    private func errorMessage(_ error: Error) -> String {
        guard let raError = error as? RAError else { return tr("No se pudo conectar con RetroAchievements.") }
        switch raError {
        case .unauthorized, .missingCredentials:
            return tr("La sesión de RetroAchievements no es válida. Vuelve a iniciarla en Ajustes.")
        case .offline:
            return tr("Sin conexión a internet.")
        case .unsupportedPlatform:
            return tr("RetroAchievements no tiene logros para esta plataforma.")
        case .badResponse:
            return tr("No se pudo conectar con RetroAchievements.")
        }
    }

    private func search() async {
        searching = true
        searchMessage = nil
        do {
            let found: [RAGameMatch] = try await RetroAchievements.searchGames(title: gameName, platform: platform)
            matches = found
            matchIndex = 0
            entryZone = found.isEmpty ? 1 : 0
            if found.isEmpty { searchMessage = tr("No se encontró automáticamente: escribe su ID.") }
        } catch {
            matches = []
            entryZone = 1
            searchMessage = errorMessage(error)
        }
        searching = false
    }

    private func load() async {
        guard configured, let id = gameID else { return }
        loading = true
        errorText = nil
        do {
            progress = try await RetroAchievements.gameProgress(gameID: id)
        } catch {
            errorText = errorMessage(error)
        }
        loading = false
    }

    private func startEditing() {
        idText = gameID.map { String($0) } ?? ""
        keyIndex = 0
        editingID = true
        if matches.isEmpty {
            Task { await search() }
        } else {
            entryZone = 0
        }
    }

    private func choose(_ match: RAGameMatch) {
        idText = String(match.id)
        saveID()
    }

    private func pressDigit(_ index: Int) {
        guard PadKeys.digits.indices.contains(index) else { return }
        keyIndex = index
        entryZone = 1
        let key: String = PadKeys.digits[index]
        if key == "✓" {
            saveID()
        } else if key == "⌫" {
            if !idText.isEmpty { idText.removeLast() }
        } else if idText.count < 9 {
            idText += key
        }
    }

    private func saveID() {
        guard let value = Int(idText) else { return }
        gameID = value
        onSaveGameID(value)
        editingID = false
        selected = 0
    }

    private func handle(_ action: PadAction) {
        if showingEntry {
            handleEntry(action)
            return
        }
        let count: Int = progress?.achievements.count ?? 0
        switch action {
        case .cancel:
            dismiss()
        case .accept:
            if selected == 0, configured { startEditing() }
        case .up:
            selected = max(0, selected - 1)
        case .down:
            selected = min(count, selected + 1)
        default:
            break
        }
    }

    private func handleEntry(_ action: PadAction) {
        switch action {
        case .cancel:
            if gameID != nil { editingID = false } else { dismiss() }
        case .accept:
            if entryZone == 0, matches.indices.contains(matchIndex) {
                choose(matches[matchIndex])
            } else {
                pressDigit(keyIndex)
            }
        default:
            if entryZone == 0 {
                if action == .up {
                    matchIndex = max(0, matchIndex - 1)
                } else if action == .down {
                    if matchIndex >= matches.count - 1 {
                        entryZone = 1
                    } else {
                        matchIndex += 1
                    }
                }
            } else if let next = PadGrid.move(keyIndex, count: PadKeys.digits.count, columns: 3, action) {
                keyIndex = next
            } else if action == .up, !matches.isEmpty {
                entryZone = 0
                matchIndex = matches.count - 1
            }
        }
    }
}

// MARK: - Cuenta de RetroAchievements (inicio de sesión recordado)

struct RetroAccountSheet: View {
    let lang: String
    @ObservedObject var pad: SheetPad
    /// Avisa a la app cuando se inicia sesión (para enseñar el aviso fuera de la ventana).
    var onLogin: (String) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var apiKey = ""
    @State private var showKey = false
    @State private var profile: RAProfile?
    @State private var recent: [RARecent] = []
    @State private var loggingIn = false
    @State private var justLoggedIn = false
    @State private var errorText: String?
    // Con el mando: botones de abajo (0, 1, 2).
    @State private var selected = 0

    private static let keysPage = URL(string: "https://retroachievements.org/settings")

    private func tr(_ key: String, _ args: CVarArg...) -> String {
        let base = L10n.tr(key, lang)
        return args.isEmpty ? base : String(format: base, arguments: args)
    }

    private var cleanUser: String { username.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var cleanKey: String { apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canLogin: Bool { !cleanUser.isEmpty && !cleanKey.isEmpty && !loggingIn }
    /// Las claves web de RetroAchievements tienen 32 caracteres.
    private var keyLooksWrong: Bool { !cleanKey.isEmpty && cleanKey.count != 32 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if let profile {
                        loggedInView(profile)
                    } else {
                        loginForm
                    }
                }
                .padding(16)
            }
            .overlay { loadingOverlay }
            .navigationTitle(tr("Logros"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .padSheetStyle(large: true)
        .onAppear {
            username = RetroAchievements.username
            apiKey = RetroAchievements.apiKey
            // Sesión recordada: se enseña al momento y se actualiza por detrás.
            profile = RetroAchievements.cachedProfile
            pad.handler = { action in
                handle(action)
                return true
            }
            if profile != nil {
                Task { await refresh() }
            }
        }
        .onDisappear { pad.handler = nil }
    }

    // MARK: Formulario

    private var loginForm: some View {
        VStack(spacing: 12) {
            Image(systemName: "trophy.circle.fill")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(Color.yellow)
            Text(tr("Iniciar sesión en RetroAchievements"))
                .font(AppFont.text(17, .bold))
                .multilineTextAlignment(.center)
            SheetCaption(text: tr("Usuario"))
            TextField(tr("Tu usuario de RetroAchievements"), text: $username)
                .font(AppFont.text(15))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(14)
                .glassCard(cornerRadius: 14)
            SheetCaption(text: tr("Clave web (Web API Key)"))
            keyField
            if keyLooksWrong {
                Text(tr("La clave web tiene 32 caracteres. ¿Has puesto tu contraseña?"))
                    .font(AppFont.text(11, .semibold))
                    .foregroundStyle(Color.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            keyHelp
            if let errorText {
                SheetInfoCard(symbol: "exclamationmark.triangle", text: errorText)
            }
            HStack(spacing: 10) {
                SheetActionButton(title: tr("Abrir página de la clave"), tint: Color.white.opacity(0.85), selected: pad.gamepadConnected && selected == 0) {
                    openKeysPage()
                }
                SheetActionButton(title: tr("Iniciar sesión"), selected: pad.gamepadConnected && selected == 1, enabled: canLogin) {
                    login()
                }
            }
        }
    }

    private var keyField: some View {
        HStack(spacing: 8) {
            Group {
                if showKey {
                    TextField(tr("Pega aquí tu clave web"), text: $apiKey)
                } else {
                    SecureField(tr("Pega aquí tu clave web"), text: $apiKey)
                }
            }
            .font(AppFont.text(15))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            Button {
                showKey.toggle()
            } label: {
                Image(systemName: showKey ? "eye.slash" : "eye")
                    .foregroundStyle(Color.cyan)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ControllerFocusableButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassCard(cornerRadius: 14)
    }

    private var keyHelp: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(tr("No es tu contraseña"), systemImage: "key.fill")
                .font(AppFont.text(12, .bold))
                .foregroundStyle(Color.cyan)
            Text(tr("Entra en retroachievements.org → Ajustes → apartado «Keys», copia la «Web API Key» y pégala aquí. La sesión queda guardada en este iPhone."))
                .font(AppFont.text(11))
                .foregroundStyle(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassCard(cornerRadius: 14)
    }

    @ViewBuilder
    private var loadingOverlay: some View {
        if loggingIn {
            ZStack {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(Color.cyan)
                        .scaleEffect(1.3)
                    Text(tr("Iniciando sesión…"))
                        .font(AppFont.text(14, .semibold))
                }
                .padding(26)
                .glassCard(cornerRadius: 22)
            }
        }
    }

    // MARK: Sesión iniciada

    private func loggedInView(_ profile: RAProfile) -> some View {
        VStack(spacing: 14) {
            if justLoggedIn {
                Label(tr("Sesión iniciada como %@", profile.user), systemImage: "checkmark.circle.fill")
                    .font(AppFont.text(14, .bold))
                    .foregroundStyle(Color.green)
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .glassCard(cornerRadius: 14)
            }
            profileCard(profile)
            HStack(spacing: 10) {
                SheetActionButton(title: tr("Actualizar"), selected: pad.gamepadConnected && selected == 0) {
                    Task { await refresh() }
                }
                SheetActionButton(title: tr("Cerrar sesión"), tint: Color.orange, selected: pad.gamepadConnected && selected == 1) {
                    logout()
                }
                SheetActionButton(title: tr("Listo"), tint: Color.white.opacity(0.85), selected: pad.gamepadConnected && selected == 2) {
                    dismiss()
                }
            }
            if let errorText {
                Text(errorText)
                    .font(AppFont.text(11, .medium))
                    .foregroundStyle(Color.orange)
            }
            recentList
        }
    }

    private func profileCard(_ profile: RAProfile) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: profile.avatarURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.white.opacity(0.08)
            }
            .frame(width: 60, height: 60)
            .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.user)
                    .font(AppFont.text(17, .bold))
                Text(tr("%ld puntos", profile.totalPoints))
                    .font(AppFont.text(13, .semibold))
                    .foregroundStyle(Color.cyan)
                Text(tr("Sesión guardada en este iPhone"))
                    .font(AppFont.text(10, .medium))
                    .foregroundStyle(.white.opacity(0.5))
                if !profile.richPresence.isEmpty {
                    Text(profile.richPresence)
                        .font(AppFont.text(11))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .glassCard()
    }

    private var recentList: some View {
        VStack(spacing: 8) {
            SheetCaption(text: tr("Logros recientes"))
            if recent.isEmpty {
                Text(tr("Sin logros en los últimos 30 días."))
                    .font(AppFont.text(12))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(recent) { item in
                recentRow(item)
            }
        }
    }

    private func recentRow(_ item: RARecent) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: item.badgeURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.white.opacity(0.08)
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(AppFont.text(13, .bold))
                Text(item.gameTitle)
                    .font(AppFont.text(11, .medium))
                    .foregroundStyle(.white.opacity(0.6))
                Text(recentDetail(item))
                    .font(AppFont.text(10, .semibold))
                    .foregroundStyle(Color.cyan)
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .glassCard(cornerRadius: 16)
    }

    private func recentDetail(_ item: RARecent) -> String {
        let points: String = tr("%ld puntos", item.points)
        return points + " · " + item.date
    }

    // MARK: Acciones

    private func loginErrorMessage(_ error: Error) -> String {
        guard let raError = error as? RAError else { return tr("No se pudo conectar con RetroAchievements.") }
        switch raError {
        case .unauthorized, .missingCredentials:
            return tr("Usuario o clave web incorrectos. Recuerda: es la Web API Key, no tu contraseña.")
        case .offline:
            return tr("Sin conexión a internet.")
        default:
            return tr("No se pudo conectar con RetroAchievements.")
        }
    }

    private func openKeysPage() {
        guard let url = Self.keysPage else { return }
        UIApplication.shared.open(url)
    }

    private func login() {
        guard canLogin else { return }
        let user: String = cleanUser
        let key: String = cleanKey
        loggingIn = true
        errorText = nil
        Task {
            do {
                let result: RAProfile = try await RetroAchievements.login(username: user, apiKey: key)
                profile = result
                justLoggedIn = true
                selected = 2
                onLogin(result.user)
                recent = (try? await RetroAchievements.recentAchievements()) ?? []
            } catch {
                errorText = loginErrorMessage(error)
            }
            loggingIn = false
        }
    }

    private func refresh() async {
        errorText = nil
        do {
            let result: RAProfile = try await RetroAchievements.profile()
            RetroAchievements.saveSession(result)
            profile = result
            recent = (try? await RetroAchievements.recentAchievements()) ?? []
        } catch RAError.unauthorized {
            // La clave ya no vale: se cierra la sesión guardada.
            RetroAchievements.clearSession()
            profile = nil
            errorText = tr("Usuario o clave web incorrectos. Recuerda: es la Web API Key, no tu contraseña.")
        } catch {
            errorText = tr("Sin conexión: se muestra la sesión guardada.")
        }
    }

    private func logout() {
        RetroAchievements.signOut()
        username = ""
        apiKey = ""
        profile = nil
        recent = []
        justLoggedIn = false
        errorText = nil
        selected = 1
    }

    private func handle(_ action: PadAction) {
        let lastButton: Int = profile == nil ? 1 : 2
        switch action {
        case .left:
            selected = max(0, selected - 1)
        case .right:
            selected = min(lastButton, selected + 1)
        case .accept:
            if profile == nil {
                if selected == 0 { openKeysPage() } else { login() }
            } else if selected == 0 {
                Task { await refresh() }
            } else if selected == 1 {
                logout()
            } else {
                dismiss()
            }
        case .cancel:
            dismiss()
        default:
            break
        }
    }
}

// MARK: - Mapear botones del mando (por juego)

enum PadButtons {
    static let ids: [String] = ["a", "b", "x", "y", "l1", "r1", "l2", "r2", "l3", "r3", "menu", "options"]

    static func label(_ id: String) -> String {
        switch id {
        case "a": return "A / ✕"
        case "b": return "B / ○"
        case "x": return "X / □"
        case "y": return "Y / △"
        case "l1": return "L1"
        case "r1": return "R1"
        case "l2": return "L2"
        case "r2": return "R2"
        case "l3": return "L3"
        case "r3": return "R3"
        case "menu": return "Menu"
        default: return "Options"
        }
    }
}

struct ButtonMapSheet: View {
    let lang: String
    @ObservedObject var pad: SheetPad
    let gameName: String
    let initialMap: [String: String]
    var onSave: ([String: String]) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var map: [String: String] = [:]
    // 0..<12 botones, 12 = Restablecer, 13 = Guardar.
    @State private var selected = 0

    private func tr(_ key: String) -> String { L10n.tr(key, lang) }

    private var resetIndex: Int { PadButtons.ids.count }
    private var saveIndex: Int { PadButtons.ids.count + 1 }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 10) {
                        Text(gameName)
                            .font(AppFont.text(16, .bold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(PadButtons.ids.indices, id: \.self) { index in
                            mappingRow(index)
                                .id(index)
                        }
                        HStack(spacing: 10) {
                            SheetActionButton(title: tr("Restablecer"), tint: Color.orange, selected: pad.gamepadConnected && selected == resetIndex) {
                                map = [:]
                            }
                            SheetActionButton(title: tr("Guardar"), selected: pad.gamepadConnected && selected == saveIndex) {
                                save()
                            }
                        }
                        .id(resetIndex)
                        Text(tr("El mapa se guarda para este juego. iOS no deja que una app cambie los botones dentro de otra: úsalo como referencia o configúralo igual en el emulador."))
                            .font(AppFont.text(11))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(16)
                }
                .onChange(of: selected) { _, value in
                    withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(min(value, resetIndex), anchor: .center) }
                }
            }
            .navigationTitle(tr("Mapear botones"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .padSheetStyle(large: true)
        .onAppear {
            map = initialMap
            pad.handler = { action in
                handle(action)
                return true
            }
        }
        .onDisappear { pad.handler = nil }
    }

    private func target(for id: String) -> String {
        map[id] ?? id
    }

    private func mappingRow(_ index: Int) -> some View {
        let id: String = PadButtons.ids[index]
        let changed: Bool = target(for: id) != id
        return HStack(spacing: 10) {
            Text(PadButtons.label(id))
                .font(AppFont.text(14, .bold))
                .frame(width: 90, alignment: .leading)
            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
            Spacer(minLength: 4)
            Button {
                cycle(index, step: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ControllerFocusableButtonStyle())
            Text(PadButtons.label(target(for: id)))
                .font(AppFont.text(14, .semibold))
                .foregroundStyle(changed ? Color.cyan : Color.white)
                .frame(width: 90)
            Button {
                cycle(index, step: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ControllerFocusableButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassCard(cornerRadius: 14)
        .padRing(pad.gamepadConnected && selected == index, cornerRadius: 14)
    }

    private func cycle(_ index: Int, step: Int) {
        let id: String = PadButtons.ids[index]
        let all: [String] = PadButtons.ids
        let current: Int = all.firstIndex(of: target(for: id)) ?? 0
        let next: String = all[(current + step + all.count) % all.count]
        if next == id {
            map[id] = nil
        } else {
            map[id] = next
        }
        selected = index
    }

    private func save() {
        onSave(map)
        dismiss()
    }

    private func handle(_ action: PadAction) {
        switch action {
        case .cancel:
            dismiss()
        case .up:
            if selected == saveIndex {
                selected = PadButtons.ids.count - 1
            } else {
                selected = max(0, selected - 1)
            }
        case .down:
            selected = min(resetIndex, selected + 1)
        case .left:
            if selected < resetIndex { cycle(selected, step: -1) } else { selected = resetIndex }
        case .right:
            if selected < resetIndex { cycle(selected, step: 1) } else { selected = saveIndex }
        case .accept:
            if selected < resetIndex {
                cycle(selected, step: 1)
            } else if selected == resetIndex {
                map = [:]
            } else {
                save()
            }
        }
    }
}

// MARK: - Juegos añadidos (quitar uno a uno)

struct LibraryListSheet: View {
    let lang: String
    @ObservedObject var pad: SheetPad
    let games: [LibraryGame]
    var onRemove: (LibraryGame) -> Void
    var onRemoveAll: () -> Void
    @Environment(\.dismiss) private var dismiss

    // 0..<n juegos, n = Quitar todos, n+1 = Listo.
    @State private var selected = 0
    @State private var confirmAll = false

    private func tr(_ key: String, _ args: CVarArg...) -> String {
        let base = L10n.tr(key, lang)
        return args.isEmpty ? base : String(format: base, arguments: args)
    }

    private var removeAllIndex: Int { games.count }
    private var doneIndex: Int { games.count + 1 }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 8) {
                        if games.isEmpty {
                            SheetInfoCard(symbol: "tray", text: tr("No hay juegos añadidos."))
                        }
                        ForEach(games.indices, id: \.self) { index in
                            gameRow(index)
                                .id(index)
                        }
                        HStack(spacing: 10) {
                            SheetActionButton(title: confirmAll ? tr("Pulsa otra vez para confirmar") : tr("Quitar todos"), tint: Color.orange, selected: pad.gamepadConnected && selected == removeAllIndex, enabled: !games.isEmpty) {
                                removeAll()
                            }
                            SheetActionButton(title: tr("Listo"), tint: Color.white.opacity(0.85), selected: pad.gamepadConnected && selected == doneIndex) {
                                dismiss()
                            }
                        }
                        .padding(.top, 6)
                        .id(removeAllIndex)
                    }
                    .padding(16)
                }
                .onChange(of: selected) { _, value in
                    withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(min(value, removeAllIndex), anchor: .center) }
                }
            }
            .navigationTitle(tr("Juegos añadidos"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .padSheetStyle(large: true)
        .onAppear {
            pad.handler = { action in
                handle(action)
                return true
            }
        }
        .onDisappear { pad.handler = nil }
        .onChange(of: games.count) { _, count in
            selected = min(selected, count + 1)
        }
    }

    private func sourceLabel(_ source: String) -> String {
        switch source {
        case "scan": return tr("Carpeta externa")
        case "ios": return tr("App iOS")
        default: return tr("Acceso directo")
        }
    }

    private func gameRow(_ index: Int) -> some View {
        let game: LibraryGame = games[index]
        return HStack(spacing: 12) {
            Image(systemName: Platforms.symbol(for: game.platform))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.cyan)
                .frame(width: 36, height: 36)
                .background(Color.cyan.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(game.name)
                    .font(AppFont.text(14, .semibold))
                    .lineLimit(1)
                Text(game.platform + " · " + sourceLabel(game.source))
                    .font(AppFont.text(11))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 6)
            Button {
                onRemove(game)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.orange)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ControllerFocusableButtonStyle())
            .accessibilityLabel(tr("Quitar"))
        }
        .padding(10)
        .glassCard(cornerRadius: 16)
        .padRing(pad.gamepadConnected && selected == index, cornerRadius: 16)
    }

    private func removeAll() {
        guard !games.isEmpty else { return }
        if confirmAll {
            confirmAll = false
            onRemoveAll()
        } else {
            confirmAll = true
        }
    }

    private func handle(_ action: PadAction) {
        switch action {
        case .cancel:
            if confirmAll { confirmAll = false } else { dismiss() }
        case .up:
            if selected == doneIndex {
                selected = max(0, games.count - 1)
            } else {
                selected = max(0, selected - 1)
            }
        case .down:
            selected = min(removeAllIndex, selected + 1)
        case .left:
            if selected >= removeAllIndex { selected = removeAllIndex }
        case .right:
            if selected >= removeAllIndex { selected = doneIndex }
        case .accept:
            if selected < games.count {
                onRemove(games[selected])
            } else if selected == removeAllIndex {
                removeAll()
            } else {
                dismiss()
            }
        }
    }
}

// MARK: - Plataformas propias

struct PlatformManagerSheet: View {
    private enum Zone { case keys, symbols, add, list, done }

    let lang: String
    @ObservedObject var pad: SheetPad
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Platforms.customKey) private var customRaw = ""

    @State private var name = ""
    @State private var shift = true
    @State private var symbol = "gamecontroller.fill"
    @State private var zone: Zone = .keys
    @State private var keyIndex = 0
    @State private var symbolIndex = 0
    @State private var listIndex = 0
    @State private var message: String?

    private func tr(_ key: String) -> String { L10n.tr(key, lang) }

    private var custom: [Platforms.Entry] { Platforms.parse(customRaw) }
    private var keys: [String] { PadKeys.text }
    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    SheetCaption(text: tr("Nueva plataforma"))
                    TextField(tr("Nombre de la plataforma"), text: $name)
                        .font(AppFont.text(16, .semibold))
                        .padding(14)
                        .glassCard(cornerRadius: 14)
                    PadKeyboardView(
                        keys: keys,
                        selectedIndex: pad.gamepadConnected && zone == .keys ? keyIndex : nil,
                        lowercase: !shift,
                        onKey: { index in pressKey(index) }
                    )
                    SheetCaption(text: tr("Icono"))
                    symbolGrid
                    if let message {
                        Text(message)
                            .font(AppFont.text(12, .medium))
                            .foregroundStyle(Color.orange)
                    }
                    SheetActionButton(title: tr("Añadir plataforma"), selected: pad.gamepadConnected && zone == .add, enabled: !cleanName.isEmpty) {
                        add()
                    }
                    if !custom.isEmpty {
                        SheetCaption(text: tr("Tus plataformas"))
                        ForEach(custom.indices, id: \.self) { index in
                            customRow(index)
                        }
                    }
                    SheetActionButton(title: tr("Listo"), tint: Color.white.opacity(0.85), selected: pad.gamepadConnected && zone == .done) {
                        dismiss()
                    }
                }
                .padding(16)
            }
            .navigationTitle(tr("Plataformas"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .padSheetStyle(large: true)
        .onAppear {
            pad.handler = { action in
                handle(action)
                return true
            }
        }
        .onDisappear { pad.handler = nil }
    }

    private var symbolGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
            ForEach(Platforms.symbolChoices.indices, id: \.self) { index in
                symbolButton(index)
            }
        }
    }

    private func symbolButton(_ index: Int) -> some View {
        let name: String = Platforms.symbolChoices[index]
        let chosen: Bool = symbol == name
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button {
            symbol = name
            symbolIndex = index
        } label: {
            Image(systemName: name)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(chosen ? Color.white : Color.cyan)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(chosen ? Color.cyan.opacity(0.45) : Color.white.opacity(0.07), in: shape)
                .contentShape(shape)
                .padRing(pad.gamepadConnected && zone == .symbols && symbolIndex == index, cornerRadius: 12)
        }
        .buttonStyle(ControllerFocusableButtonStyle())
    }

    private func customRow(_ index: Int) -> some View {
        let entry: Platforms.Entry = custom[index]
        return HStack(spacing: 12) {
            Image(systemName: entry.symbol)
                .foregroundStyle(Color.cyan)
                .frame(width: 30)
            Text(entry.name)
                .font(AppFont.text(14, .semibold))
            Spacer()
            Button {
                remove(index)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(Color.orange)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ControllerFocusableButtonStyle())
        }
        .padding(10)
        .glassCard(cornerRadius: 14)
        .padRing(pad.gamepadConnected && zone == .list && listIndex == index, cornerRadius: 14)
    }

    private func pressKey(_ index: Int) {
        guard keys.indices.contains(index) else { return }
        keyIndex = index
        PadKeys.apply(keys[index], to: &name, shift: &shift, autoCapitalize: true)
        message = nil
    }

    private func add() {
        let newName: String = cleanName
        guard !newName.isEmpty else { return }
        let taken: [String] = Platforms.builtInNames() + custom.map(\.name)
        if taken.contains(where: { $0.caseInsensitiveCompare(newName) == .orderedSame }) {
            message = tr("Ya existe una plataforma con ese nombre.")
            return
        }
        var list: [Platforms.Entry] = custom
        list.append((name: newName, symbol: symbol))
        customRaw = Platforms.encode(list)
        name = ""
        shift = true
        message = nil
    }

    private func remove(_ index: Int) {
        var list: [Platforms.Entry] = custom
        guard list.indices.contains(index) else { return }
        list.remove(at: index)
        customRaw = Platforms.encode(list)
        listIndex = max(0, min(listIndex, list.count - 1))
        if list.isEmpty, zone == .list { zone = .done }
    }

    private func handle(_ action: PadAction) {
        if action == .cancel {
            dismiss()
            return
        }
        switch zone {
        case .keys:
            if action == .accept {
                pressKey(keyIndex)
            } else if let next = PadGrid.move(keyIndex, count: keys.count, columns: PadKeys.columns, action) {
                keyIndex = next
            } else if action == .down {
                zone = .symbols
            }
        case .symbols:
            if action == .accept {
                symbol = Platforms.symbolChoices[symbolIndex]
            } else if let next = PadGrid.move(symbolIndex, count: Platforms.symbolChoices.count, columns: 6, action) {
                symbolIndex = next
            } else {
                zone = action == .up ? .keys : .add
            }
        case .add:
            if action == .accept { add() }
            if action == .up { zone = .symbols }
            if action == .down { zone = custom.isEmpty ? .done : .list }
        case .list:
            if action == .accept {
                remove(listIndex)
            } else if action == .up {
                if listIndex == 0 { zone = .add } else { listIndex -= 1 }
            } else if action == .down {
                if listIndex >= custom.count - 1 { zone = .done } else { listIndex += 1 }
            }
        case .done:
            if action == .accept { dismiss() }
            if action == .up {
                if custom.isEmpty {
                    zone = .add
                } else {
                    zone = .list
                    listIndex = custom.count - 1
                }
            }
        }
    }
}

// MARK: - Sonidos

struct SoundsSheet: View {
    let lang: String
    @ObservedObject var pad: SheetPad
    @Environment(\.dismiss) private var dismiss
    @AppStorage("volumeNavigate") private var volumeNavigate = 0.5
    @AppStorage("volumeSelect") private var volumeSelect = 0.7
    @AppStorage("volumeAmbient") private var volumeAmbient = 0.3

    // 0..2 sonidos, 3 = Listo.
    @State private var selected = 0
    @State private var importKind: SoundKind = .navigate
    @State private var showImporter = false
    // Cambia al importar o restaurar, para repintar el estado de cada sonido.
    @State private var refresh = 0
    @State private var message: String?

    private func tr(_ key: String, _ args: CVarArg...) -> String {
        let base = L10n.tr(key, lang)
        return args.isEmpty ? base : String(format: base, arguments: args)
    }

    private var kinds: [SoundKind] { SoundKind.allCases }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(kinds.indices, id: \.self) { index in
                        soundRow(index)
                    }
                    if let message {
                        Text(message)
                            .font(AppFont.text(12, .medium))
                            .foregroundStyle(Color.cyan)
                    }
                    Text(tr("Formatos: wav, mp3, m4a, caf, aac o aif. Con el mando: ←→ volumen, X probar."))
                        .font(AppFont.text(11))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    SheetActionButton(title: tr("Listo"), tint: Color.white.opacity(0.85), selected: pad.gamepadConnected && selected == kinds.count) {
                        dismiss()
                    }
                }
                .padding(16)
                .id(refresh)
            }
            .navigationTitle(tr("Sonidos"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .padSheetStyle(large: true)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
            handleImport(result)
        }
        .onAppear {
            pad.handler = { action in
                handle(action)
                return true
            }
        }
        .onDisappear { pad.handler = nil }
        .onChange(of: volumeAmbient) { _, value in
            SoundManager.shared.updateAmbient(volume: value)
        }
    }

    private func title(_ kind: SoundKind) -> String {
        switch kind {
        case .navigate: return tr("Desplazamiento por menús")
        case .select: return tr("Selección")
        case .ambient: return tr("Música de ambiente")
        }
    }

    private func symbol(_ kind: SoundKind) -> String {
        switch kind {
        case .navigate: return "arrow.up.and.down.and.arrow.left.and.right"
        case .select: return "hand.tap.fill"
        case .ambient: return "music.note"
        }
    }

    private func volumeBinding(_ kind: SoundKind) -> Binding<Double> {
        switch kind {
        case .navigate: return $volumeNavigate
        case .select: return $volumeSelect
        case .ambient: return $volumeAmbient
        }
    }

    private func status(_ kind: SoundKind) -> String {
        switch SoundManager.shared.status(kind) {
        case .imported(let file):
            return tr("Importado: %@", file)
        case .bundled(let file):
            return tr("De la app: %@", file)
        case .unreadable(let file):
            return tr("No se pudo leer %@", file)
        case .unsupported(let file):
            return tr("%@: formato no compatible", file)
        case .missing:
            return kind == .ambient ? tr("Sin música: importa una") : tr("Clic del sistema")
        }
    }

    private func soundRow(_ index: Int) -> some View {
        let kind: SoundKind = kinds[index]
        let volume: Binding<Double> = volumeBinding(kind)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: symbol(kind))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.cyan)
                    .frame(width: 36, height: 36)
                    .background(Color.cyan.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(kind))
                        .font(AppFont.text(14, .semibold))
                    Text(status(kind))
                        .font(AppFont.text(11))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 4)
                Text("\(Int((volume.wrappedValue * 100).rounded()))%")
                    .font(AppFont.text(12, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.75))
            }
            Slider(value: volume, in: 0...1)
                .tint(Color.cyan)
            HStack(spacing: 8) {
                smallButton(tr("Probar"), symbol: "play.fill") { preview(kind) }
                smallButton(tr("Importar"), symbol: "square.and.arrow.down") {
                    importKind = kind
                    showImporter = true
                }
                if SoundManager.shared.hasCustom(kind) {
                    smallButton(tr("Original"), symbol: "arrow.uturn.backward") { restore(kind) }
                }
            }
        }
        .padding(13)
        .glassCard()
        .padRing(pad.gamepadConnected && selected == index, cornerRadius: 18)
    }

    private func smallButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        let shape = Capsule()
        return Button(action: action) {
            Label(title, systemImage: symbol)
                .font(AppFont.text(11, .semibold))
                .foregroundStyle(Color.cyan)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.07), in: shape)
                .contentShape(shape)
        }
        .buttonStyle(ControllerFocusableButtonStyle())
    }

    private func preview(_ kind: SoundKind) {
        let volume: Double = volumeBinding(kind).wrappedValue
        if kind == .ambient {
            SoundManager.shared.updateAmbient(volume: volume)
        } else {
            SoundManager.shared.play(kind, volume: volume)
        }
    }

    private func restore(_ kind: SoundKind) {
        SoundManager.shared.removeCustom(kind)
        if kind == .ambient { SoundManager.shared.updateAmbient(volume: volumeAmbient) }
        refresh += 1
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        if SoundManager.shared.importSound(from: url, for: importKind) {
            message = tr("Sonido importado")
            if importKind == .ambient { SoundManager.shared.updateAmbient(volume: volumeAmbient) }
        } else {
            message = tr("No se pudo importar ese archivo")
        }
        refresh += 1
    }

    private func adjust(_ step: Double) {
        guard selected < kinds.count else { return }
        let binding: Binding<Double> = volumeBinding(kinds[selected])
        let value: Double = min(1, max(0, binding.wrappedValue + step))
        binding.wrappedValue = (value * 10).rounded() / 10
        if kinds[selected] != .ambient {
            SoundManager.shared.play(kinds[selected], volume: binding.wrappedValue)
        }
    }

    private func handle(_ action: PadAction) {
        switch action {
        case .cancel:
            dismiss()
        case .up:
            selected = max(0, selected - 1)
        case .down:
            selected = min(kinds.count, selected + 1)
        case .left:
            adjust(-0.1)
        case .right:
            adjust(0.1)
        case .accept:
            if selected < kinds.count { preview(kinds[selected]) } else { dismiss() }
        }
    }
}
