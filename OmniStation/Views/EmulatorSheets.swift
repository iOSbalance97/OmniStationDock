import SwiftUI
import UniformTypeIdentifiers

// MARK: - Ventana: emuladores instalados y sus carpetas de juegos

/// La primera vez (y desde Ajustes) pregunta qué emuladores tienes y la carpeta de juegos de cada uno.
/// Así cada emulador y OmniStation ven los mismos juegos.
struct EmulatorSetupSheet: View {
    let lang: String
    @ObservedObject var pad: SheetPad
    let installMethod: String
    /// Emuladores que se usan con su núcleo integrado: no hace falta su app ni su carpeta.
    var integrated: [Emulator] = []
    /// Carpetas de los núcleos clásicos que trae la app (NES, SNES…).
    var retroFolders: [String] = []
    /// Dentro de LiveContainer: los juegos se leen de la carpeta del emulador (sin elegir carpeta).
    var onScanLiveContainer: (Emulator) -> Void = { _ in }
    var onFolder: (Emulator, URL) -> Void
    var onFinish: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var enabled: [String: Bool] = [:]
    @State private var folders: [String: String] = [:]
    @State private var pickingFor: Emulator?
    @State private var showImporter = false
    // Con el mando: por cada emulador, 0 = lo tengo / no, 1 = carpeta. Al final, Listo.
    @State private var selected = 0

    private func tr(_ key: String, _ args: CVarArg...) -> String {
        let base = L10n.tr(key, lang)
        return args.isEmpty ? base : String(format: base, arguments: args)
    }

    private var emulators: [Emulator] { Emulator.allCases.filter { !integrated.contains($0) } }
    private var doneIndex: Int { emulators.count * 2 }

    var body: some View {
        NavigationStack {
            PadScrollView(selection: selected, anchor: selected / 2) {
                VStack(spacing: 14) {
                    if !integrated.isEmpty || !retroFolders.isEmpty {
                        integratedNotice
                    }
                    if !emulators.isEmpty {
                    Text(tr("¿Qué emuladores tienes instalados?"))
                        .font(AppFont.text(16, .bold))
                        .multilineTextAlignment(.center)
                    Text(DebugSupport.isInsideLiveContainer
                         ? tr("Dentro de LiveContainer no hace falta elegir carpetas: OmniStation lee los juegos de la carpeta de cada emulador y los abre en él con JIT.")
                         : tr("Elige la carpeta de juegos de cada uno: la misma que uses dentro del emulador. Así los juegos se ven en OmniStation y se abren directamente en su emulador con JIT."))
                        .font(AppFont.text(11))
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                    ForEach(emulators.indices, id: \.self) { index in
                        emulatorCard(emulators[index], index: index)
                            .padAnchor(index)
                    }
                    }
                    SheetActionButton(title: tr("Listo"), selected: pad.gamepadConnected && selected == doneIndex) {
                        finish()
                    }
                    .padAnchor(emulators.count)
                }
                .padding(16)
            }
            .navigationTitle(tr("Emuladores"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .padSheetStyle(large: true)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            handlePick(result)
        }
        .onAppear {
            reload()
            pad.handler = { action in
                handle(action)
                return true
            }
        }
        .onDisappear { pad.handler = nil }
    }

    /// Núcleos integrados en uso: van dentro de OmniStation, con sus propias carpetas.
    private var integratedNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(tr("Núcleos integrados"), systemImage: "cpu.fill")
                .font(AppFont.text(15, .bold))
                .foregroundStyle(Color.cyan)
            ForEach(integrated, id: \.self) { emulator in
                Text(tr("%@ integrado: sus juegos van en Archivos → OmniStation Dock → %@ → Juegos.", emulator.name, emulator.name))
                    .font(AppFont.text(12))
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !retroFolders.isEmpty {
                Text(tr("Clásicos (%@): cada uno en su carpeta → Juegos, en Archivos → OmniStation Dock.", retroFolders.joined(separator: ", ")))
                    .font(AppFont.text(12))
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !integrated.isEmpty {
                Text(tr("Para usar su app aparte, cambia el modo en Ajustes → Emuladores."))
                    .font(AppFont.text(11))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func reload() {
        var states: [String: Bool] = [:]
        var names: [String: String] = [:]
        for emulator in emulators {
            states[emulator.rawValue] = EmulatorStore.isEnabled(emulator)
            names[emulator.rawValue] = EmulatorStore.folderName(emulator)
        }
        enabled = states
        folders = names
    }

    private func emulatorCard(_ emulator: Emulator, index: Int) -> some View {
        let isOn: Bool = enabled[emulator.rawValue] ?? true
        let folder: String = folders[emulator.rawValue] ?? ""
        let location: Emulator.Location = EmulatorStore.location(emulator, installMethod: installMethod)
        let whereText: String = location == .liveContainer ? "LiveContainer" : tr("SideStore / AltStore")
        // Dentro de LiveContainer se lee su carpeta directamente (el selector haría copias en Inbox).
        let direct: Bool = DebugSupport.isInsideLiveContainer && location == .liveContainer
        let found: Bool = direct && LiveContainerStorage.gamesFolder(emulator) != nil
        let status: String = direct
            ? (found ? tr("Carpeta de LiveContainer encontrada") : tr("No se encuentra su carpeta en LiveContainer"))
            : (folder.isEmpty ? tr("Sin carpeta de juegos") : tr("Carpeta: %@", folder))
        let statusOK: Bool = direct ? found : !folder.isEmpty
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: emulator.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.cyan)
                    .frame(width: 38, height: 38)
                    .background(Color.cyan.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(emulator.name + " · " + emulator.platform)
                        .font(AppFont.text(14, .bold))
                    Text(status)
                        .font(AppFont.text(10, .medium))
                        .foregroundStyle(statusOK ? Color.green : Color.orange)
                        .lineLimit(1)
                    Text(whereText)
                        .font(AppFont.text(10, .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                SheetActionButton(title: isOn ? tr("Lo tengo: SÍ") : tr("Lo tengo: NO"), tint: Color.white.opacity(0.85), selected: pad.gamepadConnected && selected == index * 2) {
                    toggle(emulator)
                }
                // En LiveContainer sus juegos se leen solos de su carpeta: no hay nada que elegir.
                if !direct {
                    SheetActionButton(title: folder.isEmpty ? tr("Elegir carpeta") : tr("Cambiar carpeta"), selected: pad.gamepadConnected && selected == index * 2 + 1, enabled: isOn) {
                        pick(emulator)
                    }
                }
            }
            Text(emulator.setupHint(liveContainer: direct, lang: lang))
                .font(AppFont.text(10))
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .glassCard()
    }

    /// Dentro de LiveContainer, con el emulador también allí: sus juegos se leen solos.
    private func readsFolderDirectly(_ emulator: Emulator) -> Bool {
        DebugSupport.isInsideLiveContainer && EmulatorStore.location(emulator, installMethod: installMethod) == .liveContainer
    }

    private func toggle(_ emulator: Emulator) {
        let value: Bool = !(enabled[emulator.rawValue] ?? true)
        EmulatorStore.setEnabled(value, emulator)
        enabled[emulator.rawValue] = value
    }

    private func pick(_ emulator: Emulator) {
        guard enabled[emulator.rawValue] ?? true else { return }
        if DebugSupport.isInsideLiveContainer && EmulatorStore.location(emulator, installMethod: installMethod) == .liveContainer {
            onScanLiveContainer(emulator)
            return
        }
        pickingFor = emulator
        showImporter = true
    }

    private func handlePick(_ result: Result<[URL], Error>) {
        guard let emulator = pickingFor, case .success(let urls) = result, let url = urls.first else { return }
        onFolder(emulator, url)
        folders[emulator.rawValue] = url.lastPathComponent
        pickingFor = nil
    }

    private func finish() {
        onFinish()
        dismiss()
    }

    private func handle(_ action: PadAction) {
        switch action {
        case .cancel:
            finish()
        case .left:
            if selected < doneIndex && selected % 2 == 1 { selected -= 1 }
        case .right:
            if selected < doneIndex && selected % 2 == 0 && !readsFolderDirectly(emulators[selected / 2]) { selected += 1 }
        case .up:
            if selected == doneIndex {
                selected = doneIndex - 2
            } else if selected >= 2 {
                selected -= 2
            }
            if selected < doneIndex && selected % 2 == 1 && readsFolderDirectly(emulators[selected / 2]) { selected -= 1 }
        case .down:
            if selected < doneIndex {
                selected = selected + 2 >= doneIndex ? doneIndex : selected + 2
            }
            if selected < doneIndex && selected % 2 == 1 && readsFolderDirectly(emulators[selected / 2]) { selected -= 1 }
        case .accept:
            if selected == doneIndex {
                finish()
            } else {
                let emulator: Emulator = emulators[selected / 2]
                if selected % 2 == 0 { toggle(emulator) } else { pick(emulator) }
            }
        }
    }
}
