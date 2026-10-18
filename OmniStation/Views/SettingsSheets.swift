import SwiftUI
import PhotosUI

// MARK: - Mando dentro de las ventanas

enum PadAction {
    case up, down, left, right, accept, cancel
}

/// Puente entre el mando (que escucha HomeView) y la ventana que esté abierta encima.
/// La ventana registra aquí su `handler`; devuelve `true` si ha usado el botón.
final class SheetPad: ObservableObject {
    /// Con mando conectado se dibuja el recuadro de selección; sin mando, no.
    @Published var gamepadConnected = false
    var handler: ((PadAction) -> Bool)?
    /// Botón □ (cuadrado): en las ventanas con teclado borra la última letra.
    var deleteHandler: (() -> Bool)?

    @discardableResult
    func send(_ action: PadAction) -> Bool {
        handler?(action) ?? false
    }

    /// Devuelve `true` si la ventana abierta ha usado el □.
    @discardableResult
    func sendDelete() -> Bool {
        deleteHandler?() ?? false
    }
}

/// Identidad de una fila para que la ventana la siga con el mando.
/// Es un tipo propio para que no choque con otros `.id(...)` numéricos.
struct PadAnchor: Hashable {
    let row: Int
}

extension View {
    /// Marca la vista como fila `row` de una `PadScrollView`.
    func padAnchor(_ row: Int) -> some View {
        id(PadAnchor(row: row))
    }
}

/// `ScrollView` que se desplaza sola hasta la fila marcada con el mando
/// (en horizontal las ventanas no caben enteras y la selección se quedaba fuera).
struct PadScrollView<Content: View>: View {
    let selection: Int
    /// Fila a la que ir; si es nil, la propia selección.
    let anchor: Int?
    let content: Content

    init(selection: Int, anchor: Int? = nil, @ViewBuilder content: () -> Content) {
        self.selection = selection
        self.anchor = anchor
        self.content = content()
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content
            }
            .onChange(of: selection) { _, value in
                let row: Int = anchor ?? value
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(PadAnchor(row: row), anchor: .center)
                }
            }
        }
    }
}

extension View {
    /// Recuadro de selección del mando.
    func padRing(_ active: Bool, cornerRadius: CGFloat = 16) -> some View {
        overlay {
            if active {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.cyan.opacity(0.98), lineWidth: 2.5)
                    .shadow(color: Color.cyan.opacity(0.7), radius: 8)
                    .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Mandos

/// Solo informa de los mandos conectados: la interfaz siempre responde al mando.
struct ControllersSheet: View {
    let lang: String
    @ObservedObject var monitor: ControllerMonitor
    @ObservedObject var pad: SheetPad
    @Environment(\.dismiss) private var dismiss

    private func tr(_ key: String, _ args: CVarArg...) -> String {
        let base = L10n.tr(key, lang)
        return args.isEmpty ? base : String(format: base, arguments: args)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if monitor.controllers.isEmpty {
                        emptyState
                    } else {
                        ForEach(monitor.controllers) { controller in
                            row(controller)
                        }
                    }
                    doneButton
                }
                .padding(16)
            }
            .navigationTitle(tr("Mandos"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
        .preferredColorScheme(.dark)
        .onAppear {
            pad.handler = { action in
                switch action {
                case .accept, .cancel:
                    dismiss()
                default:
                    break
                }
                return true
            }
        }
        .onDisappear { pad.handler = nil }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color.cyan)
            Text(tr("Ningún mando conectado"))
                .font(AppFont.text(15, .semibold))
            Text(tr("Conecta un mando por Bluetooth (DualSense, Xbox…) y aparecerá aquí."))
                .font(AppFont.text(12))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .glassCard()
    }

    private func row(_ controller: ControllerMonitor.Info) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.cyan)
                .frame(width: 40, height: 40)
                .background(Color.cyan.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(controller.name)
                    .font(AppFont.text(14, .semibold))
                Text(controller.category)
                    .font(AppFont.text(11))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer(minLength: 6)
            if let battery = controller.battery {
                batteryLabel(battery, charging: controller.charging)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func batteryLabel(_ battery: Int, charging: Bool) -> some View {
        let text: String = charging ? tr("Cargando") + " \(battery)%" : "\(battery)%"
        let symbol: String = charging ? "battery.100percent.bolt" : "battery.75percent"
        return Label(text, systemImage: symbol)
            .font(AppFont.text(11, .semibold))
            .foregroundStyle(.white.opacity(0.7))
    }

    private var doneButton: some View {
        Button {
            dismiss()
        } label: {
            Text(tr("Listo"))
                .font(AppFont.text(15, .semibold))
                .foregroundStyle(Color.cyan)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: true)
                .padRing(pad.gamepadConnected, cornerRadius: 14)
        }
        .buttonStyle(ControllerFocusableButtonStyle())
    }
}

// MARK: - Reorganizar plataformas

struct PlatformOrderSheet: View {
    let lang: String
    @Binding var orderRaw: String
    @ObservedObject var pad: SheetPad
    /// Plataformas que tienen algún juego (para saber si sale una de la carpeta externa).
    var present: Set<String> = []
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Platforms.hiddenKey) private var hiddenRaw = ""
    @AppStorage(Platforms.shownKey) private var shownRaw = ""
    @State private var items: [String] = []
    // Con el mando: 0..<items.count = plataformas, luego «Restablecer» y «Listo».
    @State private var selected = 0
    @State private var grabbed = false

    private func tr(_ key: String) -> String { L10n.tr(key, lang) }

    private var resetRow: Int { items.count }
    private var doneRow: Int { items.count + 1 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    platformList
                        .onChange(of: selected) { _, value in
                            guard items.indices.contains(value) else { return }
                            withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(items[value], anchor: .center) }
                        }
                }

                HStack(spacing: 10) {
                    actionButton(tr("Restablecer"), row: resetRow) { reset() }
                    actionButton(tr("Listo"), row: doneRow) { dismiss() }
                }
                .padding(16)
            }
            .navigationTitle(tr("Reorganizar plataformas"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
        .preferredColorScheme(.dark)
        .onAppear {
            items = Platforms.ordered(orderRaw)
            pad.handler = { action in
                handle(action)
                return true
            }
        }
        .onDisappear { pad.handler = nil }
    }

    private var platformList: some View {
        List {
            Section {
                ForEach(Array(items.enumerated()), id: \.element) { index, name in
                    platformRow(name)
                        .listRowBackground(rowBackground(index))
                }
                .onMove { source, destination in
                    items.move(fromOffsets: source, toOffset: destination)
                    orderRaw = items.joined(separator: "|")
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("Arrastra para cambiar el orden de los filtros. El interruptor decide si la plataforma sale en la barra."))
                    Text(tr("Con el mando: X agarra y suelta, ↑↓ mueve, ←→ muestra u oculta."))
                }
                .font(AppFont.text(12))
            }
        }
        .environment(\.editMode, .constant(.active))
        .scrollContentBackground(.hidden)
    }

    private func isVisible(_ name: String) -> Bool {
        Platforms.isVisible(name, hidden: Platforms.hidden(hiddenRaw), shown: Platforms.hidden(shownRaw), present: present)
    }

    private func platformRow(_ name: String) -> some View {
        let visible: Bool = isVisible(name)
        return HStack(spacing: 10) {
            Label(name, systemImage: Platforms.symbol(for: name))
                .font(AppFont.text(15, .semibold))
                .opacity(visible ? 1 : 0.45)
            Spacer(minLength: 6)
            Toggle("", isOn: visibilityBinding(name))
                .labelsHidden()
                .tint(Color.cyan)
        }
    }

    private func visibilityBinding(_ name: String) -> Binding<Bool> {
        Binding<Bool>(
            get: { isVisible(name) },
            set: { value in setVisible(name, value) }
        )
    }

    /// El interruptor manda: encendida sale siempre en la barra y apagada nunca.
    private func setVisible(_ name: String, _ visible: Bool) {
        var hidden: Set<String> = Platforms.hidden(hiddenRaw)
        var shown: Set<String> = Platforms.hidden(shownRaw)
        if visible {
            hidden.remove(name)
            shown.insert(name)
        } else {
            shown.remove(name)
            hidden.insert(name)
        }
        hiddenRaw = Platforms.encodeHidden(hidden)
        shownRaw = Platforms.encodeHidden(shown)
    }

    private func toggleSelected() {
        guard items.indices.contains(selected) else { return }
        let name: String = items[selected]
        setVisible(name, !isVisible(name))
    }

    private func rowBackground(_ index: Int) -> some View {
        let isSelected: Bool = pad.gamepadConnected && selected == index
        let fill: Color = isSelected ? Color.cyan.opacity(grabbed ? 0.38 : 0.18) : Color.white.opacity(0.07)
        return ZStack {
            fill
            if isSelected {
                Rectangle()
                    .strokeBorder(Color.cyan.opacity(0.98), lineWidth: 2.5)
            }
        }
    }

    private func actionButton(_ title: String, row: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppFont.text(15, .semibold))
                .foregroundStyle(Color.cyan)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: true)
                .padRing(pad.gamepadConnected && selected == row, cornerRadius: 14)
        }
        .buttonStyle(ControllerFocusableButtonStyle())
    }

    private func reset() {
        orderRaw = ""
        hiddenRaw = ""
        shownRaw = ""
        items = Platforms.ordered("")
        grabbed = false
        selected = 0
    }

    private func move(_ step: Int) {
        if grabbed, selected < items.count {
            // Agarrada: la plataforma se mueve y la selección va con ella.
            let target = selected + step
            guard items.indices.contains(target) else { return }
            items.swapAt(selected, target)
            selected = target
            orderRaw = items.joined(separator: "|")
        } else {
            selected = min(max(selected + step, 0), doneRow)
        }
    }

    private func handle(_ action: PadAction) {
        switch action {
        case .up:
            move(-1)
        case .down:
            move(1)
        case .left:
            if selected >= resetRow {
                selected = resetRow
            } else if !grabbed {
                toggleSelected()
            }
        case .right:
            if selected >= resetRow {
                selected = doneRow
            } else if !grabbed {
                toggleSelected()
            }
        case .accept:
            if selected < items.count {
                grabbed.toggle()
            } else if selected == resetRow {
                reset()
            } else {
                dismiss()
            }
        case .cancel:
            if grabbed { grabbed = false } else { dismiss() }
        }
    }
}

// MARK: - Añadir acceso directo (URL, app iOS o LiveContainer)

struct AddShortcutSheet: View {
    private enum Field { case name, url }

    let lang: String
    @ObservedObject var pad: SheetPad
    /// Tipo de enlace con el que se abre: 0 URL, 1 app iOS (StikDebug), 2 LiveContainer.
    var initialMode: Int = 0
    var onSave: (LibraryGame, Data?) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var platform = "PS2"
    @State private var name = ""
    @State private var linkText = ""
    @State private var mode = 0
    @State private var coverItem: PhotosPickerItem?
    @State private var coverData: Data?
    @State private var showCoverPicker = false
    // Con el mando: plataformas (3 por fila), nombre, tipo, enlace, carátula, Cancelar y Añadir.
    @State private var selected = 0
    @FocusState private var field: Field?

    private func tr(_ key: String) -> String { L10n.tr(key, lang) }

    private var platformNames: [String] { Platforms.movableNames }
    private var chipCount: Int { platformNames.count }
    private var nameRow: Int { chipCount }
    private var modeRow: Int { chipCount + 1 }
    private var urlRow: Int { chipCount + 2 }
    private var coverRow: Int { chipCount + 3 }
    private var cancelRow: Int { chipCount + 4 }
    private var addRow: Int { chipCount + 5 }

    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var cleanLink: String { linkText.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var modeTitles: [String] { [tr("URL"), tr("App iOS"), "LiveContainer"] }

    private var placeholder: String {
        switch mode {
        case 1: return "com.empresa.juego"
        case 2: return "Juego.app / livecontainer://…"
        default: return "app://juego"
        }
    }

    private var modeHelp: String {
        switch mode {
        case 1: return tr("Escribe el Bundle ID de la app. Se abrirá con StikDebug (sirve para cualquier app instalada, también ports).")
        case 2: return tr("Pega el enlace de lanzamiento de LiveContainer (mantén pulsada la app en LiveContainer → Copiar enlace de lanzamiento) o escribe el nombre de su carpeta, por ejemplo Juego.app.")
        default: return tr("Debe incluir el esquema de la app, por ejemplo app://…")
        }
    }

    /// Enlace final que se guarda con el juego.
    private var finalURL: String? {
        let text: String = cleanLink
        guard !text.isEmpty else { return nil }
        switch mode {
        case 1:
            guard !text.contains(" ") else { return nil }
            let value: String = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
            return "stikjit://launch-app?bundle-id=" + value
        case 2:
            // Enlace completo pegado desde LiveContainer: se guarda tal cual.
            if text.lowercased().hasPrefix("livecontainer://") {
                return URL(string: text) == nil ? nil : text
            }
            let value: String = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
            return DebugSupport.liveContainerLaunchPrefix + value
        default:
            guard let url = URL(string: text), let scheme = url.scheme, !scheme.isEmpty, text.contains("://") else { return nil }
            return text
        }
    }

    private var canSave: Bool { !cleanName.isEmpty && finalURL != nil }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    formContent
                        .padding(16)
                }
                .onChange(of: selected) { _, value in
                    withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(rowAnchor(value), anchor: .center) }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(tr("Añadir acceso directo"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .padSheetStyle(large: true)
        .photosPicker(isPresented: $showCoverPicker, selection: $coverItem, matching: .images)
        .onChange(of: coverItem) { _, item in
            loadCover(item)
        }
        .onAppear {
            mode = initialMode
            if initialMode == 1 { platform = "Juegos iOS" }
            pad.handler = { action in
                handle(action)
                return true
            }
        }
        .onDisappear { pad.handler = nil }
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetCaption(text: tr("Plataforma"))
            platformGrid
                .id("chips")

            SheetCaption(text: tr("Nombre"))
            TextField(tr("Nombre del juego"), text: $name)
                .font(AppFont.text(15))
                .focused($field, equals: .name)
                .textInputAutocapitalization(.words)
                .padding(14)
                .glassCard(cornerRadius: 14)
                .padRing(pad.gamepadConnected && selected == nameRow, cornerRadius: 14)
                .id("name")

            SheetCaption(text: tr("Tipo de enlace"))
            modePicker
                .id("mode")

            TextField(placeholder, text: $linkText)
                .font(AppFont.text(15))
                .focused($field, equals: .url)
                .keyboardType(mode == 0 ? .URL : .asciiCapable)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(14)
                .glassCard(cornerRadius: 14)
                .padRing(pad.gamepadConnected && selected == urlRow, cornerRadius: 14)
                .id("url")

            Text(modeHelp)
                .font(AppFont.text(11))
                .foregroundStyle(.white.opacity(0.5))

            SheetCaption(text: tr("Carátula"))
            coverButton
                .id("cover")

            HStack(spacing: 10) {
                SheetActionButton(title: tr("Cancelar"), tint: Color.white.opacity(0.85), selected: pad.gamepadConnected && selected == cancelRow) {
                    dismiss()
                }
                SheetActionButton(title: tr("Añadir"), selected: pad.gamepadConnected && selected == addRow, enabled: canSave) {
                    save()
                }
            }
            .padding(.top, 6)
            .id("buttons")
        }
    }

    private func rowAnchor(_ row: Int) -> String {
        if row < chipCount { return "chips" }
        if row == nameRow { return "name" }
        if row == modeRow { return "mode" }
        if row == urlRow { return "url" }
        if row == coverRow { return "cover" }
        return "buttons"
    }

    private var platformGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(Array(platformNames.enumerated()), id: \.element) { index, item in
                platformChip(item, index: index)
            }
        }
    }

    private var modePicker: some View {
        HStack(spacing: 8) {
            ForEach(modeTitles.indices, id: \.self) { index in
                modeChip(index)
            }
        }
        .padding(4)
        .padRing(pad.gamepadConnected && selected == modeRow, cornerRadius: 22)
    }

    private func modeChip(_ index: Int) -> some View {
        let chosen: Bool = mode == index
        let tint: Color? = chosen ? Color(red: 0.05, green: 0.45, blue: 1.0) : nil
        return Button {
            setMode(index)
        } label: {
            Text(modeTitles[index])
                .font(AppFont.text(12, .semibold))
                .foregroundStyle(chosen ? Color.white : Color.white.opacity(0.78))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .contentShape(Capsule())
                .liquidGlass(in: Capsule(), tint: tint, interactive: true)
        }
        .buttonStyle(ControllerFocusableButtonStyle())
    }

    private var coverButton: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Button {
            showCoverPicker = true
        } label: {
            HStack(spacing: 12) {
                coverPreview
                Text(coverData == nil ? tr("Elegir carátula") : tr("Cambiar carátula"))
                    .font(AppFont.text(14, .semibold))
                    .foregroundStyle(Color.cyan)
                Spacer()
                Image(systemName: "photo.on.rectangle")
                    .foregroundStyle(Color.cyan)
            }
            .padding(12)
            .contentShape(shape)
            .glassCard(cornerRadius: 14)
            .padRing(pad.gamepadConnected && selected == coverRow, cornerRadius: 14)
        }
        .buttonStyle(ControllerFocusableButtonStyle())
    }

    @ViewBuilder
    private var coverPreview: some View {
        if let coverData, let image = UIImage(data: coverData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .frame(width: 44, height: 50)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.white.opacity(0.4))
                }
        }
    }

    private func platformChip(_ item: String, index: Int) -> some View {
        let isChosen: Bool = platform == item
        let tint: Color? = isChosen ? Color(red: 0.05, green: 0.45, blue: 1.0) : nil
        return Button {
            platform = item
        } label: {
            HStack(spacing: 6) {
                Image(systemName: Platforms.symbol(for: item))
                    .font(.system(size: 12, weight: .semibold))
                Text(item)
                    .font(AppFont.text(12, .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(isChosen ? Color.white : Color.white.opacity(0.78))
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .contentShape(Capsule())
            .liquidGlass(in: Capsule(), tint: tint, interactive: true)
            .overlay {
                if isChosen {
                    Capsule().strokeBorder(Color.cyan.opacity(0.7), lineWidth: 1)
                }
            }
            .padRing(pad.gamepadConnected && selected == index, cornerRadius: 20)
        }
        .buttonStyle(ControllerFocusableButtonStyle())
    }

    private func setMode(_ index: Int) {
        mode = index
        if index == 1, platform == "PS2" { platform = "Juegos iOS" }
    }

    private func loadCover(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                coverData = data
            }
        }
    }

    private func handle(_ action: PadAction) {
        switch action {
        case .cancel:
            if field != nil { field = nil } else { dismiss() }
        case .accept:
            accept()
        case .up, .down, .left, .right:
            // Al moverse se cierra el teclado del sistema.
            field = nil
            move(action)
        }
    }

    private func accept() {
        if selected < chipCount {
            platform = platformNames[selected]
        } else if selected == nameRow {
            field = .name
        } else if selected == modeRow {
            setMode((mode + 1) % modeTitles.count)
        } else if selected == urlRow {
            field = .url
        } else if selected == coverRow {
            showCoverPicker = true
        } else if selected == cancelRow {
            dismiss()
        } else if canSave {
            save()
        }
    }

    private func move(_ action: PadAction) {
        let columns = 3
        if selected < chipCount {
            if let next = PadGrid.move(selected, count: chipCount, columns: columns, action) {
                selected = next
            } else if action == .down {
                selected = nameRow
            }
            return
        }
        if selected == modeRow, action == .left || action == .right {
            let step: Int = action == .left ? -1 : 1
            setMode(max(0, min(modeTitles.count - 1, mode + step)))
            return
        }
        if selected >= cancelRow {
            switch action {
            case .left: selected = cancelRow
            case .right: selected = addRow
            case .up: selected = coverRow
            default: break
            }
            return
        }
        switch action {
        case .up: selected = selected == nameRow ? chipCount - 1 : selected - 1
        case .down: selected = selected == coverRow ? addRow : selected + 1
        default: break
        }
    }

    private func save() {
        guard canSave, let url = finalURL else { return }
        let item = LibraryGame(
            id: "\(platform)/\(cleanName)",
            name: cleanName,
            platform: platform,
            launchURL: url,
            source: "url"
        )
        onSave(item, coverData)
        dismiss()
    }
}
