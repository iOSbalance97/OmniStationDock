import SwiftUI

// MARK: - Configuración del emulador (generales o de un juego)

/// Ajustes de emulación de ARMSX2 o MeloNX. Sin `gameID` son los generales (Ajustes); con él,
/// los de ese juego: cada uno puede usar el general o tener su propio valor.
/// Con el mando: L1/R1 cambian de pestaña, ↑↓ elige, ←→ o ✕ cambian el valor, △ restablece
/// («Por defecto», arriba a la izquierda), □ guarda y cierra («Listo», arriba a la derecha) y
/// ○ sale sin guardar (deja los ajustes como estaban al abrir).
struct EmulatorConfigSheet: View {
    let lang: String
    let emulator: EmuConfigTarget
    var gameID: String? = nil
    var gameName: String? = nil
    @ObservedObject var pad: SheetPad
    @Environment(\.dismiss) private var dismiss
    @State private var tab: EmuTab = .graphics
    @State private var revision: Int = 0
    /// 0: pestañas; 1…n: ajustes.
    @State private var selected: Int = 1
    /// Ajustes al abrir la ventana (○ los deja así).
    @State private var snapshot: [String: String]? = nil

    private func tr(_ key: String, _ args: CVarArg...) -> String {
        let base = L10n.tr(key, lang)
        return args.isEmpty ? base : String(format: base, arguments: args)
    }

    /// Núcleos libretro: el núcleo elegido (en el juego o en general); sus opciones son las que salen.
    private var activeCore: String? {
        _ = revision
        guard case .retro(let system) = emulator else { return nil }
        return RetroConfig.core(for: system, gameID: gameID)?.id
    }

    private var isRetro: Bool {
        if case .retro = emulator { return true }
        return false
    }

    private var visibleOptions: [EmuOption] {
        let core: String? = activeCore
        return EmulatorConfig.options(emulator).filter { $0.onlyCore == nil || $0.onlyCore == core }
    }

    private var tabs: [EmuTab] {
        let used: Set<EmuTab> = Set(visibleOptions.map(\.tab))
        return EmuTab.allCases.filter { used.contains($0) }
    }

    /// Las de la pestaña, juntas por grupo (en el orden en que sale cada grupo).
    private var options: [EmuOption] {
        let list: [EmuOption] = visibleOptions.filter { $0.tab == tab }
        var order: [String: Int] = [:]
        for option in list where order[option.group] == nil { order[option.group] = order.count }
        let sorted = list.enumerated().sorted { first, second in
            let a: Int = order[first.element.group] ?? 0
            let b: Int = order[second.element.group] ?? 0
            return a != b ? a < b : first.offset < second.offset
        }
        return sorted.map { $0.element }
    }

    /// Las opciones de la pestaña por grupos (en su orden), con el número de fila de cada una.
    private var sections: [(title: String, rows: [(option: EmuOption, row: Int)])] {
        var result: [(title: String, rows: [(option: EmuOption, row: Int)])] = []
        for (index, option) in options.enumerated() {
            let item: (option: EmuOption, row: Int) = (option: option, row: index + 1)
            if let last = result.last, last.title == option.group {
                result[result.count - 1].rows.append(item)
            } else {
                result.append((title: option.group, rows: [item]))
            }
        }
        return result
    }

    private var lastRow: Int { options.count }

    private var title: String {
        if let gameName { return gameName }
        return tr("Ajustes de %@", emulator.name)
    }

    private var resetTitle: String {
        gameID == nil ? tr("Por defecto") : tr("Usar los generales")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                PadScrollView(selection: selected) {
                    VStack(alignment: .leading, spacing: 22) {
                        if gameID != nil {
                            Text(tr("Lo que no cambies aquí usa los ajustes generales de %@ (Ajustes).", emulator.name))
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.55))
                                .padding(.horizontal, 16)
                        }
                        ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                            IOSSection(header: tr(section.title)) {
                                ForEach(Array(section.rows.enumerated()), id: \.offset) { position, item in
                                    if position > 0 { IOSRowDivider() }
                                    optionRow(item.option, row: item.row)
                                        .padAnchor(item.row)
                                }
                            }
                        }
                        if options.isEmpty && isRetro {
                            Text(tr("Las opciones de este núcleo salen aquí en cuanto se puedan leer."))
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.5))
                                .padding(.horizontal, 16)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    toolbarButton(resetTitle, glyph: "△") { reset() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    toolbarButton(tr("Listo"), glyph: "□", bold: true) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(.regularMaterial)
        .preferredColorScheme(.dark)
        .onAppear {
            // Núcleos libretro: sus opciones se leen ahora si aún no se tenían.
            if case .retro(let system) = emulator {
                RetroCoreOptions.prepare(system)
                revision += 1
            }
            if !tabs.contains(tab), let first = tabs.first { tab = first }
            if snapshot == nil {
                snapshot = gameID.map { EmulatorConfig.game(emulator, $0) } ?? EmulatorConfig.global(emulator)
            }
            pad.handler = { action in
                handle(action)
                return true
            }
            pad.shoulderHandler = { step in
                stepTab(step)
                return true
            }
            pad.triangleHandler = {
                reset()
                return true
            }
            pad.deleteHandler = {
                dismiss()
                return true
            }
        }
        .onDisappear {
            pad.handler = nil
            pad.shoulderHandler = nil
            pad.triangleHandler = nil
            pad.deleteHandler = nil
        }
    }

    private func toolbarButton(_ text: String, glyph: String, bold: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if pad.gamepadConnected {
                    Text(glyph)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Text(text)
                    .font(AppFont.text(14, bold ? .bold : .semibold))
                    .foregroundStyle(Color.cyan)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    // MARK: Pestañas

    /// Pestañas como un control segmentado de iOS (con su icono encima).
    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { item in
                let active: Bool = item == tab
                Button {
                    switchTab(item)
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 12, weight: .semibold))
                        Text(tr(item.title))
                            .font(.system(size: 11, weight: active ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .foregroundStyle(active ? Color.white : Color.white.opacity(0.65))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background {
                        if active {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.white.opacity(0.22))
                                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .padRing(pad.gamepadConnected && selected == 0, cornerRadius: 12)
        .animation(.easeInOut(duration: 0.18), value: tab)
    }

    private func switchTab(_ item: EmuTab) {
        guard item != tab else { return }
        tab = item
        if selected > 0 { selected = 1 }
    }

    /// L1/R1 (o ←→ en la fila de pestañas): pestaña anterior o siguiente.
    private func stepTab(_ step: Int) {
        guard let index = tabs.firstIndex(of: tab), !tabs.isEmpty else { return }
        let next: Int = (index + step + tabs.count) % tabs.count
        switchTab(tabs[next])
    }

    // MARK: Filas

    /// Valor propio del juego (nil: usa el general).
    private func ownValue(_ option: EmuOption) -> String? {
        guard let gameID else { return nil }
        return EmulatorConfig.game(emulator, gameID)[option.id]
    }

    private func currentValue(_ option: EmuOption) -> String {
        ownValue(option) ?? EmulatorConfig.globalValue(option, emulator)
    }

    private func optionRow(_ option: EmuOption, row: Int) -> some View {
        _ = revision
        let value: String = currentValue(option)
        let inherited: Bool = gameID != nil && ownValue(option) == nil
        let changed: Bool = gameID == nil ? value != option.defaultValue : !inherited
        let focused: Bool = pad.gamepadConnected && selected == row
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tr(option.title))
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                if !option.detail.isEmpty {
                    Text(tr(option.detail))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            // Sí/No en los ajustes generales: un interruptor, como en iOS.
            if option.isToggle && gameID == nil {
                Toggle("", isOn: Binding(
                    get: { value == "true" },
                    set: { set(option, $0 ? "true" : "false") }
                ))
                .labelsHidden()
                .tint(Color.cyan)
            } else {
                Menu {
                    if gameID != nil {
                        Button {
                            set(option, nil)
                        } label: {
                            menuLabel(tr("General (%@)", tr(option.label(for: EmulatorConfig.globalValue(option, emulator)))), checked: inherited)
                        }
                    }
                    ForEach(option.choices, id: \.self) { choice in
                        Button {
                            set(option, choice.value)
                        } label: {
                            menuLabel(tr(choice.label), checked: !inherited && value == choice.value)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(tr(option.label(for: value)))
                                .font(.system(size: 15))
                                .foregroundStyle(changed ? Color.cyan : Color.white.opacity(0.5))
                                .lineLimit(1)
                            if inherited {
                                Text(tr("general"))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                        }
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .iosRowHighlight(focused)
    }

    @ViewBuilder
    private func menuLabel(_ text: String, checked: Bool) -> some View {
        if checked {
            Label(text, systemImage: "checkmark")
        } else {
            Text(text)
        }
    }

    // MARK: Cambios

    private func set(_ option: EmuOption, _ value: String?) {
        if let gameID {
            EmulatorConfig.setGame(emulator, gameID, option.id, value)
        } else {
            // El valor por defecto no se guarda: así un cambio futuro de ARMSX2/MeloNX llega solo.
            EmulatorConfig.setGlobal(emulator, option.id, value == option.defaultValue ? nil : value)
        }
        revision += 1
    }

    private func reset() {
        if let gameID {
            EmulatorConfig.resetGame(emulator, gameID)
        } else {
            EmulatorConfig.resetGlobal(emulator)
        }
        revision += 1
    }

    /// Valores por los que pasa ←→ (en un juego, el primero es «General»).
    private func cycle(_ option: EmuOption, step: Int) {
        var values: [String?] = option.choices.map { Optional($0.value) }
        if gameID != nil { values.insert(nil, at: 0) }
        let current: String? = gameID != nil ? ownValue(option) : currentValue(option)
        let index: Int = values.firstIndex(where: { $0 == current }) ?? 0
        let next: Int = (index + step + values.count) % values.count
        set(option, values[next])
    }

    private func handle(_ action: PadAction) {
        let list: [EmuOption] = options
        switch action {
        case .up:
            selected = max(0, selected - 1)
        case .down:
            selected = min(lastRow, selected + 1)
        case .left, .right:
            let step: Int = action == .left ? -1 : 1
            if selected == 0 {
                stepTab(step)
                selected = 0
            } else if selected <= list.count {
                cycle(list[selected - 1], step: step)
            }
        case .accept:
            if selected == 0 {
                selected = list.isEmpty ? 0 : 1
            } else if selected <= list.count {
                cycle(list[selected - 1], step: 1)
            }
        case .cancel:
            // ○: salir sin guardar.
            if let snapshot { EmulatorConfig.restore(emulator, gameID: gameID, values: snapshot) }
            dismiss()
        }
    }
}
