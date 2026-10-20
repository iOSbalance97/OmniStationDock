import SwiftUI

// MARK: - Configuración del emulador (generales o de un juego)

/// Ajustes de emulación de ARMSX2 o MeloNX. Sin `gameID` son los generales (Ajustes); con él,
/// los de ese juego: cada uno puede usar el general o tener su propio valor.
/// Con el mando: L1/R1 cambian de pestaña, ↑↓ elige, ←→ o ✕ cambian el valor, △ restablece
/// («Por defecto», arriba a la izquierda) y □ u ○ cierran («Listo», arriba a la derecha).
struct EmulatorConfigSheet: View {
    let lang: String
    let emulator: Emulator
    var gameID: String? = nil
    var gameName: String? = nil
    @ObservedObject var pad: SheetPad
    @Environment(\.dismiss) private var dismiss
    @State private var tab: EmuTab = .graphics
    @State private var revision: Int = 0
    /// 0: pestañas; 1…n: ajustes.
    @State private var selected: Int = 1

    private func tr(_ key: String, _ args: CVarArg...) -> String {
        let base = L10n.tr(key, lang)
        return args.isEmpty ? base : String(format: base, arguments: args)
    }

    private var tabs: [EmuTab] { EmulatorConfig.tabs(emulator) }

    private var options: [EmuOption] {
        EmulatorConfig.options(emulator).filter { $0.tab == tab }
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
                    VStack(spacing: 10) {
                        if gameID != nil {
                            Text(tr("Lo que no cambies aquí usa los ajustes generales de %@ (Ajustes).", emulator.name))
                                .font(AppFont.text(12))
                                .foregroundStyle(.white.opacity(0.55))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }
                        ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                            if !option.group.isEmpty, index == 0 || options[index - 1].group != option.group {
                                Text(tr(option.group).uppercased())
                                    .font(AppFont.text(11, .bold))
                                    .foregroundStyle(Color.cyan.opacity(0.85))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 6)
                                    .padding(.top, index == 0 ? 0 : 8)
                            }
                            optionRow(option, row: index + 1)
                                .padAnchor(index + 1)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 18)
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
        .presentationBackground(.ultraThinMaterial)
        .preferredColorScheme(.dark)
        .onAppear {
            if !tabs.contains(tab), let first = tabs.first { tab = first }
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

    private var tabBar: some View {
        HStack(spacing: 8) {
            ForEach(tabs) { item in
                let active: Bool = item == tab
                Button {
                    switchTab(item)
                } label: {
                    // Icono encima del nombre: caben las cinco pestañas de MeloNX en vertical.
                    VStack(spacing: 3) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 13, weight: .semibold))
                        Text(tr(item.title))
                            .font(AppFont.text(10, .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                        .foregroundStyle(active ? Color.black : Color.white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(active ? Color.cyan : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(ControllerFocusableButtonStyle())
            }
        }
        .padding(4)
        .padRing(pad.gamepadConnected && selected == 0, cornerRadius: 22)
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
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(tr(option.title))
                    .font(AppFont.text(14, .semibold))
                    .foregroundStyle(.white)
                if !option.detail.isEmpty {
                    Text(tr(option.detail))
                        .font(AppFont.text(11))
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
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
                HStack(spacing: 5) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(tr(option.label(for: value)))
                            .font(AppFont.text(13, .bold))
                            .foregroundStyle(changed ? Color.cyan : Color.white.opacity(0.85))
                            .lineLimit(1)
                        if inherited {
                            Text(tr("general"))
                                .font(AppFont.text(9, .semibold))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08), in: Capsule())
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .padRing(pad.gamepadConnected && selected == row, cornerRadius: 18)
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
            dismiss()
        }
    }
}
