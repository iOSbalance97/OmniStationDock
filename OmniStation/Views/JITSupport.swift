import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Método de instalación

/// Cómo se instaló OmniStation Dock: decide cómo se activa el JIT.
enum InstallMethod: String, CaseIterable, Identifiable {
    /// La app y los juegos van dentro de LiveContainer: el JIT lo pide LiveContainer a StikDebug.
    case liveContainer = "livecontainer"
    /// Instalada con SideStore o AltStore: el JIT lo activa StikDebug con el archivo de emparejamiento.
    case sideStore = "sidestore"

    var id: String { rawValue }

    static let storageKey = "installMethod"

    /// Cómo se está ejecutando la app: dentro de LiveContainer o instalada directamente.
    static var detected: InstallMethod {
        DebugSupport.isInsideLiveContainer ? .liveContainer : .sideStore
    }

    var symbol: String {
        switch self {
        case .liveContainer: return "shippingbox.fill"
        case .sideStore: return "arrow.down.app.fill"
        }
    }
}

// MARK: - Abrir juegos con JIT

enum JITLauncher {
    /// Ajuste: abrir con JIT los juegos que no tienen su propia preferencia.
    static let defaultKey = "jitByDefault"

    /// Bundle ID que contiene un enlace de StikDebug ("stikjit://…?bundle-id=…").
    static func bundleID(fromLink link: String?) -> String? {
        guard let link, link.lowercased().hasPrefix("stikjit://"),
              let components = URLComponents(string: link) else { return nil }
        let names: [String] = ["bundle-id", "bundleid", "bundle_id"]
        for item in components.queryItems ?? [] where names.contains(item.name.lowercased()) {
            if let value = item.value, !value.isEmpty { return value }
        }
        return nil
    }

    static func isLiveContainerLink(_ link: String?) -> Bool {
        guard let link else { return false }
        return link.lowercased().hasPrefix("livecontainer") && link.contains("livecontainer-launch")
    }

    /// Enlace de LiveContainer con `jit=true`: LiveContainer abre el juego pidiendo el JIT
    /// al activador que tenga configurado (StikDebug).
    static func liveContainerJITURL(_ link: String?) -> URL? {
        guard isLiveContainerLink(link), let link, var components = URLComponents(string: link) else { return nil }
        var items: [URLQueryItem] = (components.queryItems ?? []).filter { $0.name != "jit" }
        items.append(URLQueryItem(name: "jit", value: "true"))
        components.queryItems = items
        return components.url
    }

    /// StikDebug abre la app con el depurador conectado y deja el JIT activado.
    static func stikDebugJITURL(bundleID: String) -> URL? {
        let clean: String = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "stikdebug"
        components.host = "enable-jit"
        components.queryItems = [URLQueryItem(name: "bundle-id", value: clean)]
        return components.url
    }

    /// ¿Está instalado StikDebug? (iOS solo deja comprobarlo por su enlace).
    @MainActor
    static var stikDebugInstalled: Bool {
        for scheme in ["stikdebug://", "stikjit://"] {
            if let url = URL(string: scheme), UIApplication.shared.canOpenURL(url) { return true }
        }
        return false
    }

    /// Bundle ID válido: letras, números, puntos, guiones y guiones bajos.
    static func isValidBundleID(_ text: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_")
        return !text.isEmpty && text.contains(".") && text.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

// MARK: - Archivo de emparejamiento (SideStore / AltStore)

/// Tipo de archivo de emparejamiento.
enum PairingKind {
    /// RPPairing (claves Ed25519): el que usan StikDebug actual y StikJIT. Se crea con iloader.
    case remotePairing
    /// El clásico de SideStore/jitterbugpair (certificados): StikDebug actual ya no lo usa.
    case legacy
}

struct PairingInfo {
    let kind: PairingKind
    /// Identificador del emparejamiento (identifier o HostID).
    let hostID: String
    let importedAt: Date?
}

enum PairingFile {
    /// Nombre con el que StikDebug lo busca en su carpeta de Archivos.
    static let stikDebugName = "pairingFile.plist"
    static let contentTypes: [UTType] = [
        UTType(filenameExtension: "mobiledevicepairing") ?? .data,
        UTType(filenameExtension: "mobiledevicepair") ?? .data,
        .propertyList,
        .data
    ]

    static var url: URL {
        AppFolders.folder("JIT").appendingPathComponent(stikDebugName)
    }

    static var exists: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Comprueba que los datos son un archivo de emparejamiento de verdad.
    static func validate(_ data: Data) -> PairingInfo? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = plist as? [String: Any] else { return nil }
        // RPPairing: public_key y private_key de 32 bytes e identifier.
        if let publicKey = dict["public_key"] as? Data, publicKey.count == 32,
           let privateKey = dict["private_key"] as? Data, privateKey.count == 32,
           let identifier = dict["identifier"] as? String, !identifier.isEmpty {
            return PairingInfo(kind: .remotePairing, hostID: identifier, importedAt: nil)
        }
        // Clásico: HostID, SystemBUID y certificados.
        guard let hostID = dict["HostID"] as? String, !hostID.isEmpty,
              let buid = dict["SystemBUID"] as? String, !buid.isEmpty else { return nil }
        let hasCertificate: Bool = dict["HostCertificate"] != nil || dict["DeviceCertificate"] != nil
        guard hasCertificate else { return nil }
        return PairingInfo(kind: .legacy, hostID: hostID, importedAt: nil)
    }

    static func info() -> PairingInfo? {
        guard let data = try? Data(contentsOf: url), let base = validate(data) else { return nil }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let date: Date? = attributes?[.modificationDate] as? Date
        return PairingInfo(kind: base.kind, hostID: base.hostID, importedAt: date)
    }

    static func data() -> Data? {
        try? Data(contentsOf: url)
    }

    /// Importa (desde Archivos) y valida. Devuelve nil si no es un archivo válido.
    static func importFile(from source: URL) -> PairingInfo? {
        let accessing: Bool = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: source), validate(data) != nil else { return nil }
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            return nil
        }
        return info()
    }

    /// Busca un archivo de emparejamiento dejado en la carpeta de la app en Archivos.
    static func importFromDocuments() -> PairingInfo? {
        let documents: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        // También donde lo deja la guía de StikJIT: Documents/StikJIT/pairingFile.plist.
        let folders: [URL] = [documents.appendingPathComponent("StikJIT"), documents]
        let extensions: [String] = ["mobiledevicepairing", "mobiledevicepair", "plist"]
        for folder in folders {
            guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { continue }
            for file in files where extensions.contains(file.pathExtension.lowercased()) {
                if let found = importFile(from: file) { return found }
            }
        }
        return nil
    }

    static func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

/// El archivo de emparejamiento como documento, para exportarlo a la carpeta de StikDebug.
struct PairingDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.propertyList] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Ventana: método de instalación (solo informa)

/// La app detecta sola cómo se instaló y aquí solo explica qué ofrece ese método frente al otro.
struct InstallMethodSheet: View {
    let lang: String
    @ObservedObject var pad: SheetPad
    /// Primera vez: al continuar sigue la configuración inicial.
    let firstTime: Bool
    var onContinue: () -> Void
    @Environment(\.dismiss) private var dismiss

    private func tr(_ key: String) -> String { L10n.tr(key, lang) }

    private var detected: InstallMethod { InstallMethod.detected }
    private var other: InstallMethod { detected == .liveContainer ? .sideStore : .liveContainer }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 14) {
                        header
                        methodCard(detected, inUse: true)
                        methodCard(other, inUse: false)
                        Text(tr("Para usar el otro método, instala OmniStation Dock de esa forma: la app lo detecta sola al abrirse."))
                            .font(AppFont.text(11))
                            .foregroundStyle(.white.opacity(0.55))
                            .multilineTextAlignment(.center)
                        SheetActionButton(title: firstTime ? tr("Continuar") : tr("Listo"), selected: pad.gamepadConnected) {
                            finish()
                        }
                        .id("install-done")
                    }
                    .padding(16)
                }
                .onAppear {
                    // Con mando, el botón queda a la vista desde el principio.
                    guard pad.gamepadConnected else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo("install-done", anchor: .bottom) }
                    }
                }
            }
            .navigationTitle(tr("Método de instalación"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .padSheetStyle(large: true)
        .interactiveDismissDisabled(firstTime)
        .onAppear {
            pad.handler = { action in
                switch action {
                case .accept, .cancel:
                    finish()
                default:
                    break
                }
                return true
            }
        }
        .onDisappear { pad.handler = nil }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: detected.symbol)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Color.cyan)
            Text(tr("Detectado automáticamente"))
                .font(AppFont.text(11, .bold))
                .foregroundStyle(Color.green)
            Text(title(detected))
                .font(AppFont.text(18, .bold))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func title(_ method: InstallMethod) -> String {
        switch method {
        case .liveContainer: return "LiveContainer"
        case .sideStore: return "SideStore / AltStore"
        }
    }

    private func summary(_ method: InstallMethod) -> String {
        switch method {
        case .liveContainer:
            return tr("OmniStation y tus emuladores van dentro de LiveContainer. El JIT lo pide LiveContainer a StikDebug cada vez que se abre un juego.")
        case .sideStore:
            return tr("OmniStation está instalada directamente. El JIT lo activa la propia app (StikJIT integrado), sin necesitar otra app.")
        }
    }

    private func advantages(_ method: InstallMethod) -> [String] {
        switch method {
        case .liveContainer:
            return [
                tr("No ocupa huecos de SideStore: dentro de LiveContainer caben las apps que quieras."),
                tr("No necesita archivo de emparejamiento dentro de OmniStation."),
                tr("OmniStation abre cada emulador dentro de LiveContainer pidiendo el JIT.")
            ]
        case .sideStore:
            return [
                tr("JIT integrado: OmniStation lo activa sola, sin StikDebug."),
                tr("Los juegos de MeloNX se abren en un toque, ya con JIT."),
                tr("El punto JIT de la barra indica si el JIT está listo de verdad.")
            ]
        }
    }

    private func needs(_ method: InstallMethod) -> String {
        switch method {
        case .liveContainer:
            return tr("Necesita StikDebug elegido como activador de JIT en los ajustes de LiveContainer.")
        case .sideStore:
            return tr("Necesita un archivo RPPairing (iloader), la VPN LocalDevVPN y ocupa un hueco de SideStore (3 con cuenta gratuita).")
        }
    }

    private func methodCard(_ method: InstallMethod, inUse: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: method.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.cyan)
                Text(title(method))
                    .font(AppFont.text(15, .bold))
                Spacer(minLength: 0)
                Text(inUse ? tr("En uso") : tr("Otro método"))
                    .font(AppFont.text(9, .bold))
                    .foregroundStyle(inUse ? Color.green : Color.white.opacity(0.6))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background((inUse ? Color.green : Color.white).opacity(0.15), in: Capsule())
            }
            Text(summary(method))
                .font(AppFont.text(11))
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(advantages(method), id: \.self) { line in
                bullet(line, symbol: "checkmark", color: Color.green)
            }
            bullet(needs(method), symbol: "exclamationmark", color: Color.orange)
        }
        .padding(13)
        .glassCard()
        .overlay {
            shape.strokeBorder(Color.cyan.opacity(inUse ? 0.6 : 0), lineWidth: 1)
        }
        .opacity(inUse ? 1 : 0.75)
    }

    private func bullet(_ text: String, symbol: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 14, height: 14)
            Text(text)
                .font(AppFont.text(11))
                .foregroundStyle(.white.opacity(0.75))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func finish() {
        dismiss()
        onContinue()
    }
}

// MARK: - Ventana: archivo de emparejamiento

struct PairingFileSheet: View {
    let lang: String
    @ObservedObject var pad: SheetPad
    var onMessage: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var info: PairingInfo?
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var exportDocument = PairingDocument(data: Data())
    @State private var message: String?
    @State private var stikInstalled = false
    // Con el mando: 0 Importar, 1 Exportar, 2 Quitar, 3 Abrir StikDebug, 4 Listo.
    @State private var selected = 0

    private func tr(_ key: String, _ args: CVarArg...) -> String {
        let base = L10n.tr(key, lang)
        return args.isEmpty ? base : String(format: base, arguments: args)
    }

    var body: some View {
        NavigationStack {
            PadScrollView(selection: selected, anchor: selected / 2) {
                VStack(spacing: 14) {
                    statusCard
                    if let message {
                        Text(message)
                            .font(AppFont.text(12, .semibold))
                            .foregroundStyle(Color.cyan)
                            .multilineTextAlignment(.center)
                    }
                    actionButtons
                    steps
                }
                .padding(16)
                // Importar y exportar van en vistas distintas: en la misma, iOS solo presenta uno.
                .fileExporter(isPresented: $showExporter, document: exportDocument, contentType: .propertyList, defaultFilename: PairingFile.stikDebugName) { result in
                    handleExport(result)
                }
            }
            .navigationTitle(tr("Archivo de emparejamiento"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .padSheetStyle(large: true)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: PairingFile.contentTypes, allowsMultipleSelection: false) { result in
            handleImport(result)
        }
        .onAppear {
            info = PairingFile.info() ?? PairingFile.importFromDocuments()
            stikInstalled = JITLauncher.stikDebugInstalled
            pad.handler = { action in
                handle(action)
                return true
            }
        }
        .onDisappear { pad.handler = nil }
    }

    private var statusCard: some View {
        let ready: Bool = info != nil
        return HStack(spacing: 12) {
            Image(systemName: ready ? "checkmark.seal.fill" : "doc.badge.ellipsis")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(ready ? Color.green : Color.orange)
                .frame(width: 48, height: 48)
            statusLines
            Spacer(minLength: 0)
        }
        .padding(13)
        .glassCard()
    }

    private var statusLines: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(info == nil ? tr("Sin archivo de emparejamiento") : tr("Archivo de emparejamiento válido"))
                .font(AppFont.text(14, .bold))
            if let info {
                pairingDetails(info)
            }
            Text(stikInstalled ? tr("StikDebug instalado") : tr("StikDebug no detectado"))
                .font(AppFont.text(10, .semibold))
                .foregroundStyle(stikInstalled ? Color.green : Color.orange)
        }
    }

    @ViewBuilder
    private func pairingDetails(_ info: PairingInfo) -> some View {
        Text(info.kind == .remotePairing ? tr("Tipo: RPPairing (StikJIT y StikDebug)") : tr("Tipo: clásico (StikDebug actual necesita uno nuevo de iloader)"))
            .font(AppFont.text(10, .semibold))
            .foregroundStyle(info.kind == .remotePairing ? Color.green : Color.orange)
        Text("ID: " + info.hostID)
            .font(AppFont.text(10, .medium))
            .foregroundStyle(.white.opacity(0.6))
            .lineLimit(1)
            .truncationMode(.middle)
        if let date = info.importedAt {
            Text(tr("Importado: %@", date.formatted(date: .abbreviated, time: .shortened)))
                .font(AppFont.text(10, .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                SheetActionButton(title: info == nil ? tr("Importar") : tr("Reemplazar"), selected: pad.gamepadConnected && selected == 0) {
                    showImporter = true
                }
                SheetActionButton(title: tr("Exportar a StikDebug"), selected: pad.gamepadConnected && selected == 1, enabled: info != nil) {
                    startExport()
                }
            }
            .padAnchor(0)
            HStack(spacing: 10) {
                SheetActionButton(title: tr("Quitar"), tint: Color.orange, selected: pad.gamepadConnected && selected == 2, enabled: info != nil) {
                    removeFile()
                }
                SheetActionButton(title: tr("Abrir StikDebug"), selected: pad.gamepadConnected && selected == 3) {
                    openStikDebug()
                }
            }
            .padAnchor(1)
            SheetActionButton(title: tr("Listo"), tint: Color.white.opacity(0.85), selected: pad.gamepadConnected && selected == 4) {
                dismiss()
            }
            .padAnchor(2)
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 8) {
            SheetCaption(text: tr("Cómo funciona"))
            stepRow(1, tr("Crea el archivo con iloader en un ordenador (Manage Pairing File) con el iPhone conectado por cable. Es del tipo RPPairing, el que usan StikJIT y StikDebug."))
            stepRow(2, tr("Pásalo al iPhone e impórtalo aquí: la app comprueba que es válido. También puedes dejarlo en Archivos → En mi iPhone → OmniStation Dock y se importa solo."))
            stepRow(3, tr("Con el JIT integrado no hace falta nada más. Si usas la app StikDebug, pulsa «Exportar a StikDebug» y guárdalo en su carpeta."))
            stepRow(4, tr("Activa la VPN LocalDevVPN y abre tus juegos con JIT desde OmniStation."))
        }
        .padding(13)
        .glassCard()
    }

    private func stepRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(AppFont.text(12, .bold))
                .foregroundStyle(Color.black)
                .frame(width: 22, height: 22)
                .background(Color.cyan, in: Circle())
            Text(text)
                .font(AppFont.text(11))
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        if let imported = PairingFile.importFile(from: url) {
            info = imported
            JITStatusCenter.shared.invalidate()
            JITStatusCenter.shared.autoPrepare(force: true)
            message = tr("Archivo de emparejamiento importado.")
            onMessage(tr("Archivo de emparejamiento importado."))
        } else {
            message = tr("Ese archivo no es un archivo de emparejamiento válido.")
        }
    }

    private func startExport() {
        guard let data = PairingFile.data() else { return }
        exportDocument = PairingDocument(data: data)
        showExporter = true
    }

    private func handleExport(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            message = tr("Exportado. Si lo guardaste en la carpeta de StikDebug, ya está listo.")
        case .failure:
            message = tr("No se pudo exportar el archivo.")
        }
    }

    private func removeFile() {
        PairingFile.remove()
        JITStatusCenter.shared.invalidate()
        info = nil
        message = tr("Archivo de emparejamiento quitado.")
    }

    private func openStikDebug() {
        guard let url = DebugSupport.stikDebugURL else { return }
        UIApplication.shared.open(url) { success in
            if !success {
                DispatchQueue.main.async { message = tr("No se pudo abrir StikDebug. ¿Está instalado?") }
            }
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
            case 0: showImporter = true
            case 1: if info != nil { startExport() }
            case 2: if info != nil { removeFile() }
            case 3: openStikDebug()
            default: dismiss()
            }
        }
    }
}
