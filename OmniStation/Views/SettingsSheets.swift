import SwiftUI

// MARK: - Mando dentro de las ventanas

enum PadAction {
    case up, down, left, right, accept, cancel
}

/// Puente entre el mando (que escucha HomeView) y la ventana que esté abierta encima.
/// La ventana registra aquí su `handler`; devuelve `true` si ha usado el botón.
final class SheetPad: ObservableObject {
    var handler: ((PadAction) -> Bool)?

    @discardableResult
    func send(_ action: PadAction) -> Bool {
        handler?(action) ?? false
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

struct ControllersSheet: View {
    let lang: String
    @ObservedObject var monitor: ControllerMonitor
    @Binding var navigationEnabled: Bool
    let pad: SheetPad
    @Environment(\.dismiss) private var dismiss
    // Con el mando: 0 = interruptor, 1 = Listo.
    @State private var selected = 0

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
                    navigationToggle
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
                case .up: selected = 0
                case .down: selected = 1
                case .left, .right: break
                case .accept:
                    if selected == 0 { navigationEnabled.toggle() } else { dismiss() }
                case .cancel: dismiss()
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
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Text(tr("Conecta un mando por Bluetooth (DualSense, Xbox…) y aparecerá aquí."))
                .font(.system(size: 12))
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
                    .font(.system(size: 14, weight: .semibold))
                Text(controller.category)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer(minLength: 6)
            if let battery = controller.battery {
                Label(controller.charging ? tr("Cargando") + " \(battery)%" : "\(battery)%", systemImage: controller.charging ? "battery.100.bolt" : "battery.75")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var navigationToggle: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("Navegar con el mando"))
                        .font(.system(size: 14, weight: .semibold))
                    Text(tr("L1 y R1 cambian de pestaña"))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 6)
                Toggle(tr("Navegar con el mando"), isOn: $navigationEnabled)
                    .labelsHidden()
                    .tint(Color.cyan)
            }
            Text(tr("Si lo desactivas, el mando dejará de mover la interfaz."))
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(13)
        .glassCard()
        .padRing(selected == 0, cornerRadius: 18)
    }

    private var doneButton: some View {
        Button {
            dismiss()
        } label: {
            Text(tr("Listo"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.cyan)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: true)
                .padRing(selected == 1, cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Reorganizar plataformas

struct PlatformOrderSheet: View {
    let lang: String
    @Binding var orderRaw: String
    let pad: SheetPad
    @Environment(\.dismiss) private var dismiss
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
                List {
                    Section {
                        ForEach(Array(items.enumerated()), id: \.element) { index, name in
                            Label(name, systemImage: Platforms.symbol(for: name))
                                .font(.system(size: 15, weight: .semibold))
                                .listRowBackground(rowBackground(index))
                        }
                        .onMove { source, destination in
                            items.move(fromOffsets: source, toOffset: destination)
                            orderRaw = items.joined(separator: "|")
                        }
                    } footer: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tr("Arrastra para cambiar el orden de los filtros."))
                            Text(tr("Con el mando: X agarra y suelta, ↑↓ mueve."))
                        }
                    }
                }
                .environment(\.editMode, .constant(.active))
                .scrollContentBackground(.hidden)

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

    private func rowBackground(_ index: Int) -> some View {
        let isSelected = selected == index
        return ZStack {
            (isSelected ? Color.cyan.opacity(grabbed ? 0.38 : 0.18) : Color.white.opacity(0.07))
            if isSelected {
                Rectangle()
                    .strokeBorder(Color.cyan.opacity(0.98), lineWidth: 2.5)
            }
        }
    }

    private func actionButton(_ title: String, row: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.cyan)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: true)
                .padRing(selected == row, cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }

    private func reset() {
        orderRaw = ""
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
            if selected >= resetRow { selected = resetRow }
        case .right:
            if selected >= resetRow { selected = doneRow }
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

// MARK: - Añadir acceso directo (URL)

struct AddShortcutSheet: View {
    private enum Field { case name, url }

    let lang: String
    let pad: SheetPad
    var onSave: (LibraryGame) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var platform = "PS2"
    @State private var name = ""
    @State private var urlText = ""
    // Con el mando: plataformas (3 por fila), luego nombre, URL, Cancelar y Añadir.
    @State private var selected = 0
    @FocusState private var field: Field?

    private func tr(_ key: String) -> String { L10n.tr(key, lang) }

    private var chipCount: Int { Platforms.movableNames.count }
    private var nameRow: Int { chipCount }
    private var urlRow: Int { chipCount + 1 }
    private var cancelRow: Int { chipCount + 2 }
    private var addRow: Int { chipCount + 3 }

    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var cleanURL: String { urlText.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var urlIsValid: Bool {
        guard let url = URL(string: cleanURL), let scheme = url.scheme else { return false }
        return !scheme.isEmpty && cleanURL.contains("://")
    }

    private var canSave: Bool { !cleanName.isEmpty && urlIsValid }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    caption(tr("Plataforma"))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(Array(Platforms.movableNames.enumerated()), id: \.element) { index, item in
                            platformChip(item, index: index)
                        }
                    }

                    caption(tr("Nombre"))
                    TextField(tr("Nombre del juego"), text: $name)
                        .focused($field, equals: .name)
                        .textInputAutocapitalization(.words)
                        .padding(14)
                        .glassCard(cornerRadius: 14)
                        .padRing(selected == nameRow, cornerRadius: 14)

                    caption(tr("URL de acceso directo"))
                    TextField("app://juego", text: $urlText)
                        .focused($field, equals: .url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(14)
                        .glassCard(cornerRadius: 14)
                        .padRing(selected == urlRow, cornerRadius: 14)

                    Text(tr("Debe incluir el esquema de la app, por ejemplo app://…"))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))

                    HStack(spacing: 10) {
                        bottomButton(tr("Cancelar"), row: cancelRow, enabled: true) { dismiss() }
                        bottomButton(tr("Añadir"), row: addRow, enabled: canSave) { save() }
                    }
                    .padding(.top, 6)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(tr("Añadir acceso directo"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
        .presentationBackground(.ultraThinMaterial)
        .preferredColorScheme(.dark)
        .onAppear {
            pad.handler = { action in
                handle(action)
                return true
            }
        }
        .onDisappear { pad.handler = nil }
    }

    private func caption(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .tracking(1.4)
            .foregroundStyle(Color.cyan.opacity(0.85))
    }

    private func platformChip(_ item: String, index: Int) -> some View {
        let isChosen = platform == item
        return Button {
            platform = item
        } label: {
            HStack(spacing: 6) {
                Image(systemName: Platforms.symbol(for: item))
                    .font(.system(size: 12, weight: .semibold))
                Text(item)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(isChosen ? Color.white : Color.white.opacity(0.78))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .liquidGlass(in: Capsule(), tint: isChosen ? Color(red: 0.05, green: 0.45, blue: 1.0) : nil, interactive: true)
            .overlay {
                if isChosen {
                    Capsule().strokeBorder(Color.cyan.opacity(0.7), lineWidth: 1)
                }
            }
            .padRing(selected == index, cornerRadius: 20)
        }
        .buttonStyle(ControllerFocusableButtonStyle())
        .focusable()
    }

    private func bottomButton(_ title: String, row: Int, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(enabled ? Color.cyan : Color.white.opacity(0.35))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: true)
                .padRing(selected == row, cornerRadius: 14)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func handle(_ action: PadAction) {
        switch action {
        case .cancel:
            if field != nil { field = nil } else { dismiss() }
        case .accept:
            if selected < chipCount {
                platform = Platforms.movableNames[selected]
            } else if selected == nameRow {
                field = .name
            } else if selected == urlRow {
                field = .url
            } else if selected == cancelRow {
                dismiss()
            } else if canSave {
                save()
            }
        case .up, .down, .left, .right:
            // Al moverse se cierra el teclado del sistema.
            field = nil
            move(action)
        }
    }

    private func move(_ action: PadAction) {
        let columns = 3
        if selected < chipCount {
            let column = selected % columns
            switch action {
            case .left: if column > 0 { selected -= 1 }
            case .right: if column < columns - 1, selected + 1 < chipCount { selected += 1 }
            case .up: if selected >= columns { selected -= columns }
            case .down: selected = selected + columns < chipCount ? selected + columns : nameRow
            default: break
            }
        } else if selected == nameRow {
            switch action {
            case .up: selected = chipCount - 1
            case .down: selected = urlRow
            default: break
            }
        } else if selected == urlRow {
            switch action {
            case .up: selected = nameRow
            case .down: selected = addRow
            default: break
            }
        } else {
            switch action {
            case .left: selected = cancelRow
            case .right: selected = addRow
            case .up: selected = urlRow
            default: break
            }
        }
    }

    private func save() {
        guard canSave else { return }
        let item = LibraryGame(
            id: "\(platform)/\(cleanName)",
            name: cleanName,
            platform: platform,
            launchURL: cleanURL,
            source: "url"
        )
        onSave(item)
        dismiss()
    }
}
