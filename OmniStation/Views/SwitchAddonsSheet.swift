import SwiftUI

// MARK: - Actualizaciones y DLC de un juego de Switch
//
// • MeloNX integrado: se eligen aquí. Se guardan como los guarda MeloNX (Documentos/games/<Title ID>/
//   updates.json y dlc.json, con rutas desde Documentos) y el núcleo las aplica al arrancar.
// • MeloNX aparte (SideStore o LiveContainer): están en la carpeta de MeloNX y se activan en MeloNX;
//   aquí solo se ven, para que no salgan como juegos sueltos en la biblioteca.

struct SwitchAddonsSheet: View {
    let lang: String
    @ObservedObject var pad: SheetPad
    let gameName: String
    let baseTitleID: String?
    /// MeloNX integrado (se pueden activar aquí).
    let integrated: Bool
    @Environment(\.dismiss) private var dismiss

    @State private var addons: [SwitchAddon] = []
    @State private var selectedUpdate: String = ""
    /// DLC activados (ruta relativa) y sus NCA ya leídos.
    @State private var dlcState: [String: [[String: Any]]] = [:]
    @State private var dlcEnabled: Set<String> = []
    @State private var selected: Int = 0
    @State private var message: String?
    @State private var working = false

    private func tr(_ key: String, _ args: CVarArg...) -> String {
        let base = L10n.tr(key, lang)
        return args.isEmpty ? base : String(format: base, arguments: args)
    }

    private var updates: [SwitchAddon] { addons.filter { $0.kind == .update } }
    private var dlcs: [SwitchAddon] { addons.filter { $0.kind == .dlc } }
    private var rows: [SwitchAddon] { updates + dlcs }
    private var doneRow: Int { rows.count }

    private static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Ruta desde Documentos (como las guarda MeloNX en iOS).
    private static func relative(_ path: String) -> String {
        let base: String = documents.standardizedFileURL.path + "/"
        let full: String = URL(fileURLWithPath: path).standardizedFileURL.path
        return full.hasPrefix(base) ? String(full.dropFirst(base.count)) : full
    }

    private var gameFolder: URL? {
        guard let baseTitleID else { return nil }
        return Self.documents.appendingPathComponent("games", isDirectory: true).appendingPathComponent(baseTitleID.lowercased(), isDirectory: true)
    }

    var body: some View {
        NavigationStack {
            PadScrollView(selection: selected) {
                VStack(spacing: 10) {
                    Text(gameName)
                        .font(AppFont.text(16, .bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(explanation)
                        .font(AppFont.text(11))
                        .foregroundStyle(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if rows.isEmpty {
                        Text(baseTitleID == nil
                             ? tr("No se sabe el Title ID de este juego. Si el archivo lo lleva entre corchetes ([0100…]) o es un .nsp con su ticket, se reconoce al volver a escanear.")
                             : tr("No hay actualizaciones ni DLC de este juego en su carpeta."))
                            .font(AppFont.text(12))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassCard()
                    }
                    if !updates.isEmpty {
                        sectionTitle(tr("Actualizaciones"))
                    }
                    ForEach(Array(updates.enumerated()), id: \.element.id) { index, addon in
                        addonRow(addon, row: index)
                            .padAnchor(index)
                    }
                    if !dlcs.isEmpty {
                        sectionTitle(tr("DLC"))
                    }
                    ForEach(Array(dlcs.enumerated()), id: \.element.id) { index, addon in
                        addonRow(addon, row: updates.count + index)
                            .padAnchor(updates.count + index)
                    }
                    if let message {
                        Text(message)
                            .font(AppFont.text(11, .semibold))
                            .foregroundStyle(Color.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    SheetActionButton(title: tr("Listo"), selected: pad.gamepadConnected && selected == doneRow) {
                        dismiss()
                    }
                    .padAnchor(doneRow)
                }
                .padding(16)
            }
            .navigationTitle(tr("Actualizaciones y DLC"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .padSheetStyle(large: true)
        .onAppear {
            load()
            pad.handler = { action in
                handle(action)
                return true
            }
        }
        .onDisappear { pad.handler = nil }
    }

    private var explanation: String {
        integrated
            ? tr("Pon las actualizaciones y los DLC en MeloNX/Juegos, junto a los juegos. Aquí eliges cuáles usa MeloNX integrado al jugar.")
            : tr("Están en la carpeta de MeloNX. Se activan en la app MeloNX (mantén pulsado el juego → Actualizaciones o DLC); OmniStation solo las enseña aquí para que no salgan como juegos.")
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(AppFont.text(11, .bold))
            .foregroundStyle(Color.cyan.opacity(0.85))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
    }

    private func isOn(_ addon: SwitchAddon) -> Bool {
        let path: String = Self.relative(addon.path)
        return addon.kind == .update ? selectedUpdate == path : dlcEnabled.contains(path)
    }

    private func addonRow(_ addon: SwitchAddon, row: Int) -> some View {
        let on: Bool = isOn(addon)
        let detail: String = [SwitchContent.versionText(addon.version), addon.titleID?.uppercased()]
            .compactMap { $0 }
            .joined(separator: " · ")
        return Button {
            selected = row
            toggle(addon)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(addon.fileName)
                        .font(AppFont.text(12, .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(AppFont.text(10))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                Spacer(minLength: 8)
                if integrated {
                    Image(systemName: on ? (addon.kind == .update ? "checkmark.circle.fill" : "checkmark.square.fill") : (addon.kind == .update ? "circle" : "square"))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(on ? Color.cyan : Color.white.opacity(0.5))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .glassCard()
            .padRing(pad.gamepadConnected && selected == row, cornerRadius: 18)
        }
        .buttonStyle(ControllerFocusableButtonStyle())
        .disabled(!integrated || working)
    }

    // MARK: Datos

    private func load() {
        guard let baseTitleID else { return }
        addons = SwitchAddonStore.shared.addons(baseTitleID: baseTitleID)
        guard integrated, let folder = gameFolder else { return }
        if let data = try? Data(contentsOf: folder.appendingPathComponent("updates.json")),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            selectedUpdate = json["selected"] as? String ?? ""
        }
        if let data = try? Data(contentsOf: folder.appendingPathComponent("dlc.json")),
           let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for container in list {
                guard let path = container["path"] as? String else { continue }
                let ncas: [[String: Any]] = container["dlc_nca_list"] as? [[String: Any]] ?? []
                dlcState[path] = ncas
                if ncas.first?["is_enabled"] as? Bool == true { dlcEnabled.insert(path) }
            }
        }
    }

    private func toggle(_ addon: SwitchAddon) {
        guard integrated, !working else { return }
        message = nil
        let path: String = Self.relative(addon.path)
        if addon.kind == .update {
            selectedUpdate = selectedUpdate == path ? "" : path
            saveUpdates()
            return
        }
        if dlcEnabled.contains(path) {
            dlcEnabled.remove(path)
            saveDLC()
            return
        }
        if dlcState[path]?.isEmpty == false {
            dlcEnabled.insert(path)
            saveDLC()
            return
        }
        // Primera vez: MeloNX tiene que mirar qué contenidos lleva el archivo (con tus claves).
        guard let baseTitleID else { return }
        working = true
        OSMeloNXEngine.shared.dlcContents(atPath: addon.path, titleID: baseTitleID) { items, error in
            working = false
            guard let items, !items.isEmpty else {
                message = error ?? tr("No se pudo leer el DLC.")
                return
            }
            dlcState[path] = items.map { item in
                ["path": item["path"] as? String ?? "", "title_id": item["titleId"] as? NSNumber ?? NSNumber(value: 0), "is_enabled": true]
            }
            dlcEnabled.insert(path)
            saveDLC()
        }
    }

    private func saveUpdates() {
        guard let folder = gameFolder else { return }
        let paths: [String] = updates.map { Self.relative($0.path) }
        let json: [String: Any] = ["selected": selectedUpdate, "paths": paths]
        write(json, to: folder.appendingPathComponent("updates.json"))
    }

    private func saveDLC() {
        guard let folder = gameFolder else { return }
        var list: [[String: Any]] = []
        for (path, ncas) in dlcState.sorted(by: { $0.key < $1.key }) where !ncas.isEmpty {
            let enabled: Bool = dlcEnabled.contains(path)
            let entries: [[String: Any]] = ncas.map { nca in
                var copy: [String: Any] = nca
                copy["is_enabled"] = enabled
                return copy
            }
            list.append(["path": path, "dlc_nca_list": entries])
        }
        write(list, to: folder.appendingPathComponent("dlc.json"))
    }

    private func write(_ object: Any, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func handle(_ action: PadAction) {
        switch action {
        case .up:
            selected = max(0, selected - 1)
        case .down:
            selected = min(doneRow, selected + 1)
        case .left, .right:
            break
        case .accept:
            if selected < rows.count {
                toggle(rows[selected])
            } else {
                dismiss()
            }
        case .cancel:
            dismiss()
        }
    }
}
