import SwiftUI

// MARK: - Ventana: JIT integrado (StikJIT)

struct JITSetupSheet: View {
    let lang: String
    @ObservedObject var pad: SheetPad
    /// Abre la ventana del archivo de emparejamiento (la cambia HomeView).
    var onOpenPairing: () -> Void
    @Environment(\.dismiss) private var dismiss

    @AppStorage(BuiltInJIT.forceScriptKey) private var forceScript = false
    @State private var readiness: BuiltInJIT.Readiness?
    @State private var working = false
    @State private var stage = ""
    @State private var message: String?
    // Con el mando: 0 Preparar, 1 Emparejamiento, 2 Forzar script, 3 Restablecer imagen, 4 Listo.
    @State private var selected = 0

    private func tr(_ key: String) -> String { L10n.tr(key, lang) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    statusCard
                    if let message {
                        Text(message)
                            .font(AppFont.text(12, .semibold))
                            .foregroundStyle(Color.cyan)
                            .multilineTextAlignment(.center)
                    }
                    actions
                    requirements
                }
                .padding(16)
            }
            .navigationTitle(tr("JIT integrado"))
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

    // MARK: Estado

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            statusRow(tr("iOS 17.4 o posterior"), ok: BuiltInJIT.isSupportedOS, detail: nil)
            pairingRow
            connectionRow
            statusRow(tr("TXM (iOS 26)"), ok: nil, detail: txmText)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var pairingRow: some View {
        let info: PairingInfo? = PairingFile.info()
        let ok: Bool? = info == nil ? false : (info?.kind == .remotePairing ? true : nil)
        let detail: String
        if info == nil {
            detail = tr("Falta")
        } else if info?.kind == .remotePairing {
            detail = "RPPairing"
        } else {
            detail = tr("Tipo antiguo: crea uno nuevo con iloader")
        }
        return statusRow(tr("Archivo de emparejamiento"), ok: ok, detail: detail)
    }

    private var connectionRow: some View {
        let title: String = tr("VPN e imagen de desarrollador")
        if working {
            return statusRow(title, ok: nil, detail: stage.isEmpty ? tr("Comprobando…") : stage)
        }
        switch readiness {
        case .ready:
            return statusRow(title, ok: true, detail: tr("Listo"))
        case .unreachable(let reason):
            return statusRow(title, ok: false, detail: tr("Inalcanzable: ") + reason)
        case .notReady(let reason):
            return statusRow(title, ok: false, detail: tr("No listo: ") + reason)
        case .none:
            return statusRow(title, ok: nil, detail: tr("Sin comprobar"))
        }
    }

    private var txmText: String {
        switch BuiltInJIT.txmPresent {
        case .some(true): return tr("Presente: se usa el script de cada app")
        case .some(false): return tr("No presente: basta con conectar")
        case .none: return tr("Desconocido")
        }
    }

    private func statusRow(_ title: String, ok: Bool?, detail: String?) -> some View {
        let symbol: String
        let color: Color
        switch ok {
        case .some(true):
            symbol = "checkmark.circle.fill"
            color = Color.green
        case .some(false):
            symbol = "xmark.circle.fill"
            color = Color.red
        case .none:
            symbol = "info.circle.fill"
            color = Color.orange
        }
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.text(13, .bold))
                if let detail {
                    Text(detail)
                        .font(AppFont.text(10, .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Botones

    private var actions: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                SheetActionButton(title: working ? tr("Preparando…") : tr("Preparar JIT"), selected: pad.gamepadConnected && selected == 0, enabled: !working) {
                    prepare()
                }
                SheetActionButton(title: tr("Emparejamiento"), selected: pad.gamepadConnected && selected == 1) {
                    onOpenPairing()
                }
            }
            HStack(spacing: 10) {
                SheetActionButton(title: forceScript ? tr("Forzar script: SÍ") : tr("Forzar script: NO"), tint: Color.white.opacity(0.85), selected: pad.gamepadConnected && selected == 2) {
                    forceScript.toggle()
                }
                SheetActionButton(title: tr("Restablecer imagen"), tint: Color.orange, selected: pad.gamepadConnected && selected == 3, enabled: !working) {
                    resetImage()
                }
            }
            SheetActionButton(title: tr("Listo"), tint: Color.white.opacity(0.85), selected: pad.gamepadConnected && selected == 4) {
                dismiss()
            }
        }
    }

    private var requirements: some View {
        VStack(alignment: .leading, spacing: 6) {
            SheetCaption(text: tr("Antes del primer uso"))
            requirementLine(tr("OmniStation y tus juegos instalados con SideStore o AltStore (no dentro de LiveContainer)."))
            requirementLine(tr("Modo desarrollador activado en Ajustes → Privacidad y seguridad."))
            requirementLine(tr("Archivo de emparejamiento RPPairing creado con iloader."))
            requirementLine(tr("VPN LocalDevVPN conectada. Mejor con Wi‑Fi; sin Wi‑Fi: datos móviles, conectar la VPN y después modo avión."))
            requirementLine(tr("La primera vez se descarga la imagen de desarrollador (unos 20 MB). Si falla varias veces, reinicia el iPhone o pulsa «Restablecer imagen»."))
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func requirementLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(AppFont.text(11, .bold))
                .foregroundStyle(Color.cyan)
            Text(text)
                .font(AppFont.text(11))
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Acciones

    private func prepare() {
        guard !working else { return }
        if let problem = BuiltInJIT.preflightProblem(lang: lang) {
            message = problem
            return
        }
        working = true
        stage = ""
        message = nil
        BuiltInJIT.prepare(progress: { text in
            stage = text
        }, completion: { result in
            working = false
            readiness = result
        })
    }

    private func resetImage() {
        do {
            try BuiltInJIT.resetDiskImage()
            readiness = nil
            message = tr("Imagen de desarrollador borrada. Se descargará de nuevo al preparar el JIT.")
        } catch {
            message = BuiltInJIT.message(for: error)
        }
    }

    private func handle(_ action: PadAction) {
        switch action {
        case .cancel:
            dismiss()
        case .left:
            if selected == 1 || selected == 3 { selected -= 1 }
        case .right:
            if selected == 0 || selected == 2 { selected += 1 }
        case .up:
            if selected == 4 {
                selected = 2
            } else if selected >= 2 {
                selected -= 2
            }
        case .down:
            if selected <= 1 {
                selected += 2
            } else {
                selected = 4
            }
        case .accept:
            switch selected {
            case 0: prepare()
            case 1: onOpenPairing()
            case 2: forceScript.toggle()
            case 3: resetImage()
            default: dismiss()
            }
        }
    }
}

// MARK: - Ventana: elegir una app instalada

/// Lista las apps instaladas con SideStore/AltStore (las que admiten JIT) para elegir su Bundle ID.
struct InstalledAppsSheet: View {
    let lang: String
    @ObservedObject var pad: SheetPad
    let title: String
    var onPick: (DebuggableApp) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var apps: [DebuggableApp] = []
    @State private var loading = true
    @State private var errorText: String?
    @State private var selected = 0

    private func tr(_ key: String) -> String { L10n.tr(key, lang) }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 8) {
                        content
                    }
                    .padding(16)
                }
                .onChange(of: selected) { _, value in
                    withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo("app-\(value)", anchor: .center) }
                }
            }
            .navigationTitle(title)
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

    @ViewBuilder
    private var content: some View {
        if loading {
            ProgressView()
                .tint(Color.cyan)
                .padding(.top, 30)
            Text(tr("Buscando apps con la VPN…"))
                .font(AppFont.text(12, .medium))
                .foregroundStyle(.white.opacity(0.6))
        } else if let errorText {
            Text(errorText)
                .font(AppFont.text(12, .medium))
                .foregroundStyle(Color.orange)
                .multilineTextAlignment(.center)
                .padding(.top, 20)
            SheetActionButton(title: tr("Reintentar"), selected: pad.gamepadConnected) {
                load()
            }
        } else if apps.isEmpty {
            Text(tr("No hay apps instaladas con SideStore o AltStore."))
                .font(AppFont.text(12, .medium))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.top, 20)
        } else {
            ForEach(apps.indices, id: \.self) { index in
                appRow(apps[index], index: index)
                    .id("app-\(index)")
            }
        }
    }

    private func appRow(_ app: DebuggableApp, index: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Button {
            pick(app)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "app.badge.checkmark.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.cyan)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(AppFont.text(14, .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(app.bundleID)
                        .font(AppFont.text(10, .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(11)
            .contentShape(shape)
            .glassCard(cornerRadius: 14)
            .padRing(pad.gamepadConnected && selected == index, cornerRadius: 14)
        }
        .buttonStyle(ControllerFocusableButtonStyle())
    }

    private func load() {
        if let problem = BuiltInJIT.preflightProblem(lang: lang) {
            loading = false
            errorText = problem
            return
        }
        loading = true
        errorText = nil
        BuiltInJIT.debuggableApps { result in
            loading = false
            switch result {
            case .success(let list):
                apps = list
                selected = 0
            case .failure(let error):
                errorText = tr("No se pudo conectar. ¿Está activa la VPN LocalDevVPN?") + "\n" + BuiltInJIT.message(for: error)
            }
        }
    }

    private func pick(_ app: DebuggableApp) {
        onPick(app)
        dismiss()
    }

    private func handle(_ action: PadAction) {
        switch action {
        case .cancel:
            dismiss()
        case .up:
            selected = max(0, selected - 1)
        case .down:
            selected = min(max(apps.count - 1, 0), selected + 1)
        case .accept:
            if errorText != nil {
                load()
            } else if apps.indices.contains(selected) {
                pick(apps[selected])
            }
        default:
            break
        }
    }
}
