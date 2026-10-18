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

    /// Lo que parece por cómo se está ejecutando la app (solo es una sugerencia).
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

// MARK: - Ventana: ¿cómo has instalado la app?

struct InstallMethodSheet: View {
    let lang: String
    @ObservedObject var pad: SheetPad
    /// Primera vez: hay que elegir (no se puede cerrar sin hacerlo).
    let firstTime: Bool
    let current: InstallMethod?
    var onChoose: (InstallMethod) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var choice: InstallMethod = .liveContainer
    // Con el mando: 0 = LiveContainer, 1 = SideStore/AltStore, 2 = Confirmar.
    @State private var selected = 0

    private func tr(_ key: String) -> String { L10n.tr(key, lang) }

    private var methods: [InstallMethod] { InstallMethod.allCases }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Image(systemName: "bolt.horizontal.circle.fill")
                        .font(.system(size: 46, weight: .light))
                        .foregroundStyle(Color.cyan)
                    Text(tr("¿Cómo has instalado OmniStation Dock?"))
                        .font(AppFont.text(17, .bold))
                        .multilineTextAlignment(.center)
                    Text(tr("Así la app sabe cómo activar el JIT de tus juegos. Puedes cambiarlo cuando quieras en Ajustes → Depuración."))
                        .font(AppFont.text(12))
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                    ForEach(methods.indices, id: \.self) { index in
                        methodCard(methods[index], index: index)
                    }
                    SheetActionButton(title: tr("Confirmar"), selected: pad.gamepadConnected && selected == 2) {
                        confirm()
                    }
                }
                .padding(16)
            }
            .navigationTitle(tr("Método de instalación"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .padSheetStyle(large: true)
        .interactiveDismissDisabled(firstTime)
        .onAppear {
            choice = current ?? InstallMethod.detected
            selected = choice == .liveContainer ? 0 : 1
            pad.handler = { action in
                handle(action)
                return true
            }
        }
        .onDisappear { pad.handler = nil }
    }

    private func title(_ method: InstallMethod) -> String {
        switch method {
        case .liveContainer: return "LiveContainer"
        case .sideStore: return "SideStore / AltStore"
        }
    }

    private func detail(_ method: InstallMethod) -> String {
        switch method {
        case .liveContainer:
            return tr("La app y tus juegos están dentro de LiveContainer. El JIT lo activa LiveContainer con StikDebug (elige StikDebug como activador de JIT en los ajustes de LiveContainer).")
        case .sideStore:
            return tr("La app está instalada directamente. El JIT lo activa OmniStation por sí misma (StikJIT integrado) o la app StikDebug, con tu archivo de emparejamiento.")
        }
    }

    private func methodCard(_ method: InstallMethod, index: Int) -> some View {
        let chosen: Bool = choice == method
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let ringOn: Bool = pad.gamepadConnected && selected == index
        return Button {
            choice = method
            selected = index
        } label: {
            methodLabel(method, chosen: chosen)
                .padding(13)
                .contentShape(shape)
                .glassCard()
                .overlay {
                    shape.strokeBorder(Color.cyan.opacity(chosen ? 0.6 : 0), lineWidth: 1)
                }
                .padRing(ringOn, cornerRadius: 18)
        }
        .buttonStyle(ControllerFocusableButtonStyle())
    }

    private func methodLabel(_ method: InstallMethod, chosen: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: method.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.cyan)
                .frame(width: 44, height: 44)
                .background(Color.cyan.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                methodHeader(method)
                Text(detail(method))
                    .font(AppFont.text(11))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundStyle(chosen ? Color.cyan : Color.white.opacity(0.35))
        }
    }

    private func methodHeader(_ method: InstallMethod) -> some View {
        HStack(spacing: 8) {
            Text(title(method))
                .font(AppFont.text(15, .bold))
                .foregroundStyle(.white)
            if method == InstallMethod.detected {
                Text(tr("Detectado"))
                    .font(AppFont.text(9, .bold))
                    .foregroundStyle(Color.green)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.15), in: Capsule())
            }
        }
    }

    private func confirm() {
        onChoose(choice)
        dismiss()
    }

    private func handle(_ action: PadAction) {
        switch action {
        case .up:
            selected = max(0, selected - 1)
        case .down:
            selected = min(2, selected + 1)
        case .accept:
            if selected < methods.count {
                choice = methods[selected]
                selected = 2
            } else {
                confirm()
            }
        case .cancel:
            if !firstTime { dismiss() }
        default:
            break
        }
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
            ScrollView {
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
            HStack(spacing: 10) {
                SheetActionButton(title: tr("Quitar"), tint: Color.orange, selected: pad.gamepadConnected && selected == 2, enabled: info != nil) {
                    removeFile()
                }
                SheetActionButton(title: tr("Abrir StikDebug"), selected: pad.gamepadConnected && selected == 3) {
                    openStikDebug()
                }
            }
            SheetActionButton(title: tr("Listo"), tint: Color.white.opacity(0.85), selected: pad.gamepadConnected && selected == 4) {
                dismiss()
            }
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
