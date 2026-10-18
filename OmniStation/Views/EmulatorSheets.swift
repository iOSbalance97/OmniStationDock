import SwiftUI
import UniformTypeIdentifiers

// MARK: - Ventana: emuladores instalados y sus carpetas de juegos

/// La primera vez (y desde Ajustes) pregunta qué emuladores tienes y la carpeta de juegos de cada uno.
/// Así cada emulador y OmniStation ven los mismos juegos.
struct EmulatorSetupSheet: View {
    let lang: String
    @ObservedObject var pad: SheetPad
    let installMethod: String
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

    private var emulators: [Emulator] { Emulator.allCases }
    private var doneIndex: Int { emulators.count * 2 }

    var body: some View {
        NavigationStack {
            PadScrollView(selection: selected, anchor: selected / 2) {
                VStack(spacing: 14) {
                    Text(tr("¿Qué emuladores tienes instalados?"))
                        .font(AppFont.text(16, .bold))
                        .multilineTextAlignment(.center)
                    Text(tr("Elige la carpeta de juegos de cada uno: la misma que uses dentro del emulador. Así los juegos se ven en OmniStation y se abren directamente en su emulador con JIT."))
                        .font(AppFont.text(11))
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                    ForEach(emulators.indices, id: \.self) { index in
                        emulatorCard(emulators[index], index: index)
                            .padAnchor(index)
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
                    Text(folder.isEmpty ? tr("Sin carpeta de juegos") : tr("Carpeta: %@", folder))
                        .font(AppFont.text(10, .medium))
                        .foregroundStyle(folder.isEmpty ? Color.orange : Color.green)
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
                SheetActionButton(title: folder.isEmpty ? tr("Elegir carpeta") : tr("Cambiar carpeta"), selected: pad.gamepadConnected && selected == index * 2 + 1, enabled: isOn) {
                    pick(emulator)
                }
            }
        }
        .padding(13)
        .glassCard()
    }

    private func toggle(_ emulator: Emulator) {
        let value: Bool = !(enabled[emulator.rawValue] ?? true)
        EmulatorStore.setEnabled(value, emulator)
        enabled[emulator.rawValue] = value
    }

    private func pick(_ emulator: Emulator) {
        guard enabled[emulator.rawValue] ?? true else { return }
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
            if selected < doneIndex && selected % 2 == 0 { selected += 1 }
        case .up:
            if selected == doneIndex {
                selected = doneIndex - 2
            } else if selected >= 2 {
                selected -= 2
            }
        case .down:
            if selected < doneIndex {
                selected = selected + 2 >= doneIndex ? doneIndex : selected + 2
            }
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
