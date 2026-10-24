import SwiftUI
import JavaScriptCore
import UniformTypeIdentifiers

// MARK: - Parcheador (el motor de Rom Patcher JS de Marc Robledo, MIT, con interfaz propia)

/// Carpetas del parcheador.
enum PatcherFolders {
    /// Lo parcheado: Archivos → OmniStation Dock → Parcheados.
    static var output: URL {
        let documents: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url: URL = documents.appendingPathComponent("Parcheados", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// El motor (solo sus .js, sin la web): Resources/RomPatcher/rom-patcher-js.
    static var engine: URL? {
        Bundle.main.url(forResource: "RomPatcher", withExtension: nil)?.appendingPathComponent("rom-patcher-js", isDirectory: true)
    }
}

/// Rom Patcher JS ejecutado con JavaScriptCore (sin vista web): los bytes pasan directamente
/// entre Swift y el motor en arrays tipados.
final class RomPatcherEngine {
    static let shared = RomPatcherEngine()

    struct PatchInfo {
        let format: String
        let description: String
    }

    struct Result {
        let data: Data
        let name: String
        let romMatched: Bool
    }

    enum Failure: Error {
        case engineMissing, unknownPatch, invalidROM, failed(String)
    }

    private let queue = DispatchQueue(label: "omnistation.patcher", qos: .userInitiated)
    private var context: JSContext?
    private var lastError: String?

    private static let scripts: [String] = [
        "modules/BinFile.js", "modules/HashCalculator.js", "RomPatcher.js",
        "modules/RomPatcher.format.ips.js", "modules/RomPatcher.format.aps_n64.js", "modules/RomPatcher.format.aps_gba.js",
        "modules/RomPatcher.format.ups.js", "modules/RomPatcher.format.bps.js", "modules/RomPatcher.format.rup.js",
        "modules/RomPatcher.format.ppf.js", "modules/RomPatcher.format.bdf.js", "modules/RomPatcher.format.pmsr.js",
        "modules/RomPatcher.format.vcdiff.js"
    ]

    /// Puente pequeño: nombres de formato, cabeceras y aplicar el parche.
    private static let glue: String = """
    var OmniPatcher = {
      open: function (bytes, name) { var f = new BinFile(bytes); f.fileName = name; return f; },
      formatName: function (patch) {
        var known = [['IPS', IPS], ['UPS', UPS], ['APS (N64)', APS], ['APS (GBA)', APSGBA], ['BPS', BPS], ['RUP', RUP],
                     ['PPF', PPF], ['BDF', BDF], ['PMSR', PMSR], ['xdelta / VCDIFF', VCDIFF]];
        for (var i = 0; i < known.length; i++) { if (typeof known[i][1] === 'function' && patch instanceof known[i][1]) return known[i][0]; }
        return '';
      },
      info: function (bytes, name) {
        var patch = RomPatcher.parsePatchFile(OmniPatcher.open(bytes, name));
        if (!patch) return null;
        var description = (typeof patch.getDescription === 'function') ? (patch.getDescription() || '') : '';
        return { format: OmniPatcher.formatName(patch), description: String(description) };
      },
      header: function (bytes, name) {
        var rom = OmniPatcher.open(bytes, name);
        return { canAdd: !!RomPatcher.canRomGetHeader(rom), headered: !!RomPatcher.isRomHeadered(rom) };
      },
      apply: function (romBytes, romName, patchBytes, patchName, options) {
        var rom = OmniPatcher.open(romBytes, romName);
        var patch = RomPatcher.parsePatchFile(OmniPatcher.open(patchBytes, patchName));
        if (!patch) throw new Error('OMNI_UNKNOWN_PATCH');
        var matched = RomPatcher.validateRom(rom, patch, 0);
        if (options.requireValidation && !matched) throw new Error('OMNI_INVALID_ROM');
        var out = RomPatcher.applyPatch(rom, patch, options);
        var bytesOut = out._u8array;
        if (bytesOut.length !== out.fileSize) bytesOut = bytesOut.subarray(0, out.fileSize);
        return { data: bytesOut.slice(), name: out.fileName, matched: !!matched };
      }
    };
    """

    private func prepare() -> JSContext? {
        if let context { return context }
        guard let root = PatcherFolders.engine, let created = JSContext() else { return nil }
        created.exceptionHandler = { [weak self] _, value in
            self?.lastError = value?.toString()
        }
        for script in Self.scripts {
            guard let code = try? String(contentsOf: root.appendingPathComponent(script), encoding: .utf8) else { return nil }
            created.evaluateScript(code, withSourceURL: root.appendingPathComponent(script))
        }
        created.evaluateScript(Self.glue)
        guard created.objectForKeyedSubscript("OmniPatcher")?.isObject == true else { return nil }
        context = created
        return created
    }

    /// Un Uint8Array con estos bytes (copiados una vez, sin pasar por texto).
    private func typedArray(_ data: Data, in context: JSContext) -> JSValue? {
        let ref: JSGlobalContextRef = context.jsGlobalContextRef
        var exception: JSValueRef? = nil
        guard let object = JSObjectMakeTypedArray(ref, kJSTypedArrayTypeUint8Array, data.count, &exception), exception == nil else { return nil }
        if data.count > 0, let pointer = JSObjectGetTypedArrayBytesPtr(ref, object, &exception) {
            data.withUnsafeBytes { buffer in
                if let base = buffer.baseAddress { memcpy(pointer, base, data.count) }
            }
        }
        return JSValue(jsValueRef: object, in: context)
    }

    private func bytes(of value: JSValue, in context: JSContext) -> Data? {
        let ref: JSGlobalContextRef = context.jsGlobalContextRef
        var exception: JSValueRef? = nil
        guard let object = JSValueToObject(ref, value.jsValueRef, &exception) else { return nil }
        let length: Int = JSObjectGetTypedArrayByteLength(ref, object, &exception)
        guard length > 0, let pointer = JSObjectGetTypedArrayBytesPtr(ref, object, &exception) else { return length == 0 ? Data() : nil }
        return Data(bytes: pointer, count: length)
    }

    func info(patch: Data, name: String, completion: @escaping (PatchInfo?) -> Void) {
        queue.async {
            var result: PatchInfo? = nil
            if let context = self.prepare(), let array = self.typedArray(patch, in: context),
               let value = context.objectForKeyedSubscript("OmniPatcher")?.invokeMethod("info", withArguments: [array, name]),
               value.isObject {
                result = PatchInfo(format: value.forProperty("format")?.toString() ?? "",
                                   description: value.forProperty("description")?.toString() ?? "")
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// ¿La ROM puede llevar o lleva cabecera de copiadora (NES, SNES, Lynx)?
    func header(rom: Data, name: String, completion: @escaping (_ canAdd: Bool, _ headered: Bool) -> Void) {
        queue.async {
            var canAdd: Bool = false
            var headered: Bool = false
            if let context = self.prepare(), let array = self.typedArray(rom, in: context),
               let value = context.objectForKeyedSubscript("OmniPatcher")?.invokeMethod("header", withArguments: [array, name]),
               value.isObject {
                canAdd = value.forProperty("canAdd")?.toBool() ?? false
                headered = value.forProperty("headered")?.toBool() ?? false
            }
            DispatchQueue.main.async { completion(canAdd, headered) }
        }
    }

    func apply(rom: Data, romName: String, patch: Data, patchName: String, options: [String: Bool],
               completion: @escaping (Swift.Result<Result, Failure>) -> Void) {
        queue.async {
            let outcome: Swift.Result<Result, Failure>
            if let context = self.prepare(), let romArray = self.typedArray(rom, in: context), let patchArray = self.typedArray(patch, in: context) {
                self.lastError = nil
                let value = context.objectForKeyedSubscript("OmniPatcher")?.invokeMethod("apply", withArguments: [romArray, romName, patchArray, patchName, options])
                if let error = self.lastError {
                    if error.contains("OMNI_UNKNOWN_PATCH") {
                        outcome = .failure(.unknownPatch)
                    } else if error.contains("OMNI_INVALID_ROM") {
                        outcome = .failure(.invalidROM)
                    } else {
                        outcome = .failure(.failed(error.replacingOccurrences(of: "Error: ", with: "")))
                    }
                } else if let value, value.isObject, let dataValue = value.forProperty("data"), let data = self.bytes(of: dataValue, in: context) {
                    outcome = .success(Result(data: data, name: value.forProperty("name")?.toString() ?? romName,
                                              romMatched: value.forProperty("matched")?.toBool() ?? false))
                } else {
                    outcome = .failure(.failed("?"))
                }
                // Lo grande no se queda en la memoria del motor.
                JSGarbageCollect(context.jsGlobalContextRef)
            } else {
                outcome = .failure(.engineMissing)
            }
            DispatchQueue.main.async { completion(outcome) }
        }
    }
}

/// Una ROM de la biblioteca para elegirla directamente.
struct PatcherROM: Identifiable, Hashable {
    let id: String
    let name: String
    let platform: String
    let url: URL
}

// MARK: - Ventana

struct PatcherSheet: View {
    let lang: String
    @ObservedObject var pad: SheetPad
    /// Juegos de la biblioteca con archivo en OmniStation.
    let library: [PatcherROM]
    /// «Añadir a la biblioteca»: el archivo parcheado pasa por Importar.
    var onImport: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    private enum Pick { case rom, patch }
    private enum Row: Hashable { case romLibrary, romFiles, patch, validate, header, checksum, suffix, apply, addLibrary, save }

    @State private var romName: String = ""
    @State private var romData: Data? = nil
    @State private var patchName: String = ""
    @State private var patchData: Data? = nil
    @State private var patchInfo: RomPatcherEngine.PatchInfo? = nil
    @State private var patchUnknown = false
    @State private var canAddHeader = false
    @State private var isHeadered = false
    @State private var requireValidation = false
    @State private var headerOption = false
    @State private var fixChecksum = false
    @State private var outputSuffix = true
    @State private var working = false
    @State private var loading = false
    @State private var message: (text: String, good: Bool)? = nil
    @State private var resultURL: URL? = nil
    @State private var picking: Pick? = nil
    @State private var showImporter = false
    @State private var showLibrary = false
    @State private var libraryIndex = 0
    @State private var selected: Row = .romLibrary

    private func tr(_ key: String, _ args: CVarArg...) -> String {
        let base = L10n.tr(key, lang)
        return args.isEmpty ? base : String(format: base, arguments: args)
    }

    private var rows: [Row] {
        var list: [Row] = [.romLibrary, .romFiles, .patch, .validate]
        if canAddHeader || isHeadered { list.append(.header) }
        list += [.checksum, .suffix, .apply]
        if resultURL != nil { list += [.addLibrary, .save] }
        return list
    }

    private var ready: Bool { romData != nil && patchData != nil && !patchUnknown && !working }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 14) {
                        hero
                        stepCard(number: 1, title: tr("Juego"), symbol: "opticaldisc.fill", tint: Color.cyan) {
                            fileLine(name: romName, size: romData?.count, empty: tr("Elige la ROM que quieres parchear"))
                            HStack(spacing: 10) {
                                SheetActionButton(title: tr("Biblioteca"), selected: isSelected(.romLibrary), enabled: !library.isEmpty) { openLibrary() }
                                SheetActionButton(title: tr("Archivos"), tint: Color.white.opacity(0.85), selected: isSelected(.romFiles)) { pick(.rom) }
                            }
                        }
                        .id(Row.romLibrary)
                        stepCard(number: 2, title: tr("Parche"), symbol: "bandage.fill", tint: Color(red: 0.55, green: 0.42, blue: 1.0)) {
                            fileLine(name: patchName, size: patchData?.count, empty: tr("IPS, UPS, BPS, APS, PPF, RUP, BDF, PMSR o xdelta"))
                            if let info = patchInfo {
                                patchDetails(info)
                            } else if patchUnknown {
                                Label(tr("No es un parche que se pueda leer"), systemImage: "exclamationmark.triangle.fill")
                                    .font(AppFont.text(12, .semibold))
                                    .foregroundStyle(Color.orange)
                            }
                            SheetActionButton(title: patchData == nil ? tr("Elegir parche") : tr("Cambiar parche"), tint: Color(red: 0.62, green: 0.52, blue: 1.0), selected: isSelected(.patch)) { pick(.patch) }
                        }
                        .id(Row.patch)
                        optionsCard
                            .id(Row.validate)
                        applyButton
                            .id(Row.apply)
                        if let message {
                            Label(message.text, systemImage: message.good ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                .font(AppFont.text(13, .semibold))
                                .foregroundStyle(message.good ? Color.green : Color.orange)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        }
                        if resultURL != nil {
                            resultCard
                                .id(Row.addLibrary)
                        }
                        Text(tr("Motor: Rom Patcher JS de Marc Robledo (licencia MIT)."))
                            .font(AppFont.text(10))
                            .foregroundStyle(.white.opacity(0.35))
                            .padding(.top, 4)
                    }
                    .padding(16)
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: resultURL)
                    .animation(.easeInOut(duration: 0.2), value: patchInfo?.format)
                }
                .onChange(of: selected) { _, row in
                    withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(anchorRow(row), anchor: .center) }
                }
            }
            .navigationTitle(tr("Parcheador"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(tr("Listo")) { dismiss() }
                        .font(AppFont.text(14, .bold))
                        .foregroundStyle(Color.cyan)
                }
            }
        }
        .overlay { libraryOverlay }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            handlePick(result)
        }
        .padSheetStyle(large: true)
        .appSheetBackground()
        .preferredColorScheme(.dark)
        .onAppear {
            pad.handler = { action in
                handle(action)
                return true
            }
        }
        .onDisappear { pad.handler = nil }
    }

    // MARK: Partes

    private var hero: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color.cyan.opacity(0.35), .clear], center: .center, startRadius: 2, endRadius: 46))
                    .frame(width: 92, height: 92)
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [Color.cyan, Color(red: 0.55, green: 0.42, blue: 1.0)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: Color.cyan.opacity(0.6), radius: 8)
            }
            Text(tr("Traducciones, hacks y arreglos para tus juegos"))
                .font(AppFont.text(15, .semibold))
                .multilineTextAlignment(.center)
            Text(tr("Elige el juego y el parche: el resultado se guarda en Archivos → OmniStation Dock → Parcheados."))
                .font(AppFont.text(11))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private func stepCard<Content: View>(number: Int, title: String, symbol: String, tint: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                Text("\(number)")
                    .font(AppFont.text(12, .bold))
                    .foregroundStyle(.black)
                    .frame(width: 22, height: 22)
                    .background(tint, in: Circle())
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(AppFont.text(15, .bold))
                Spacer(minLength: 0)
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func fileLine(name: String, size: Int?, empty: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: name.isEmpty ? "doc.badge.plus" : "doc.fill")
                .foregroundStyle(name.isEmpty ? Color.white.opacity(0.35) : Color.cyan)
            VStack(alignment: .leading, spacing: 2) {
                Text(name.isEmpty ? empty : name)
                    .font(AppFont.text(13, name.isEmpty ? .regular : .semibold))
                    .foregroundStyle(name.isEmpty ? Color.white.opacity(0.45) : Color.white)
                    .lineLimit(2)
                if let size {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                        .font(AppFont.text(10))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            Spacer(minLength: 0)
            if loading && !name.isEmpty { ProgressView().tint(Color.cyan) }
        }
    }

    private func patchDetails(_ info: RomPatcherEngine.PatchInfo) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if !info.format.isEmpty {
                Text(info.format)
                    .font(AppFont.text(10, .bold))
                    .tracking(0.8)
                    .foregroundStyle(Color(red: 0.62, green: 0.52, blue: 1.0))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(red: 0.55, green: 0.42, blue: 1.0).opacity(0.16), in: Capsule())
            }
            if !info.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(info.description)
                    .font(AppFont.text(11))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(6)
            }
        }
    }

    private var optionsCard: some View {
        VStack(spacing: 0) {
            optionRow(.validate, tr("Comprobar que es la ROM correcta"), tr("Si el parche trae su firma (BPS, UPS…), no se aplica a otra ROM."), $requireValidation)
            if canAddHeader || isHeadered {
                IOSRowDivider()
                optionRow(.header, isHeadered ? tr("Quitar la cabecera antes") : tr("Añadir cabecera falsa antes"),
                          tr("Algunos parches de NES y SNES la necesitan (o no): pruébalo si no funciona."), $headerOption)
            }
            IOSRowDivider()
            optionRow(.checksum, tr("Corregir el checksum"), tr("Arregla la suma de comprobación de la cabecera (Game Boy, Mega Drive…)."), $fixChecksum)
            IOSRowDivider()
            optionRow(.suffix, tr("Nombre con «(patched)»"), tr("Si no, se llama como el parche."), $outputSuffix)
        }
        .glassCard()
    }

    private func optionRow(_ row: Row, _ title: String, _ detail: String, _ binding: Binding<Bool>) -> some View {
        Button {
            binding.wrappedValue.toggle()
            selected = row
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppFont.text(13, .semibold))
                        .foregroundStyle(.white)
                    Text(detail)
                        .font(AppFont.text(10))
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                Toggle("", isOn: .constant(binding.wrappedValue))
                    .labelsHidden()
                    .tint(Color.cyan)
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
            .iosRowHighlight(isSelected(row))
        }
        .buttonStyle(.plain)
    }

    private var applyButton: some View {
        let shape = Capsule()
        return Button {
            apply()
        } label: {
            HStack(spacing: 9) {
                if working {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "wand.and.rays")
                }
                Text(working ? tr("Parcheando…") : tr("Aplicar parche"))
            }
            .font(AppFont.text(16, .bold))
            .foregroundStyle(.white.opacity(ready || working ? 1 : 0.45))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background {
                shape.fill(LinearGradient(colors: ready ? [Color(red: 0.10, green: 0.42, blue: 1.0), Color(red: 0.0, green: 0.78, blue: 1.0)] : [Color.white.opacity(0.08), Color.white.opacity(0.05)],
                                          startPoint: .leading, endPoint: .trailing))
            }
            .shadow(color: ready ? Color.cyan.opacity(0.45) : .clear, radius: 12)
            .contentShape(shape)
            .padRing(isSelected(.apply), cornerRadius: 30)
        }
        .buttonStyle(ControllerFocusableButtonStyle())
        .disabled(!ready)
    }

    private var resultCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(Color.green)
                .symbolEffect(.bounce, value: resultURL)
            Text(resultURL?.lastPathComponent ?? "")
                .font(AppFont.text(13, .semibold))
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                SheetActionButton(title: tr("Añadir a la biblioteca"), selected: isSelected(.addLibrary)) {
                    if let resultURL { onImport(resultURL); dismiss() }
                }
                SheetActionButton(title: tr("Guardar en…"), tint: Color.white.opacity(0.85), selected: isSelected(.save)) {
                    if let resultURL { presentExport(resultURL) }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    /// Lista de juegos de la biblioteca (encima de la ventana).
    @ViewBuilder
    private var libraryOverlay: some View {
        if showLibrary {
            ZStack {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation { showLibrary = false } }
                VStack(spacing: 10) {
                    Text(tr("Elige el juego"))
                        .font(AppFont.text(14, .bold))
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(library.enumerated()), id: \.element.id) { index, rom in
                                    if index > 0 { IOSRowDivider(inset: 0) }
                                    Button {
                                        chooseLibrary(rom)
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: Platforms.symbol(for: rom.platform))
                                                .foregroundStyle(Platforms.tint(for: rom.platform))
                                                .frame(width: 22)
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(rom.name)
                                                    .font(AppFont.text(13, .semibold))
                                                    .lineLimit(1)
                                                Text(rom.platform + " · " + rom.url.lastPathComponent)
                                                    .font(AppFont.text(10))
                                                    .foregroundStyle(.white.opacity(0.45))
                                                    .lineLimit(1)
                                            }
                                            Spacer(minLength: 0)
                                        }
                                        .padding(.horizontal, 14)
                                        .frame(minHeight: 48)
                                        .contentShape(Rectangle())
                                        .iosRowHighlight(pad.gamepadConnected && index == libraryIndex)
                                    }
                                    .buttonStyle(.plain)
                                    .id(index)
                                }
                            }
                            .appSectionCard(cornerRadius: 14)
                        }
                        .frame(maxHeight: 420)
                        .onChange(of: libraryIndex) { _, value in
                            withAnimation(.easeInOut(duration: 0.18)) { proxy.scrollTo(value, anchor: .center) }
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: 380)
                .background {
                    ZStack {
                        Rectangle().fill(.regularMaterial)
                        AppPanelBackground().opacity(0.85)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.cyan.opacity(0.4), lineWidth: 0.8))
                .padding(24)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
    }

    // MARK: Acciones

    private func isSelected(_ row: Row) -> Bool { pad.gamepadConnected && selected == row }

    private func anchorRow(_ row: Row) -> Row {
        switch row {
        case .romLibrary, .romFiles: return .romLibrary
        case .validate, .header, .checksum, .suffix: return .validate
        case .addLibrary, .save: return .addLibrary
        default: return row
        }
    }

    private func pick(_ target: Pick) {
        picking = target
        showImporter = true
    }

    private func openLibrary() {
        libraryIndex = 0
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { showLibrary = true }
    }

    private func chooseLibrary(_ rom: PatcherROM) {
        withAnimation { showLibrary = false }
        loadROM(rom.url, name: rom.url.lastPathComponent)
    }

    private func handlePick(_ result: Swift.Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        switch picking {
        case .rom?: loadROM(url, name: url.lastPathComponent)
        case .patch?: loadPatch(url)
        case nil: break
        }
        picking = nil
    }

    private static func read(_ url: URL) -> Data? {
        let accessing: Bool = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        return try? Data(contentsOf: url, options: .mappedIfSafe)
    }

    private func loadROM(_ url: URL, name: String) {
        loading = true
        message = nil
        resultURL = nil
        romName = name
        Task {
            let data: Data? = await Task.detached(priority: .userInitiated) { Self.read(url) }.value
            loading = false
            guard let data else {
                romName = ""
                message = (tr("No se pudo leer la ROM"), false)
                return
            }
            // Más de 512 MB no cabe bien en memoria con su copia parcheada.
            if data.count > 512 * 1024 * 1024 {
                romName = ""
                message = (tr("La ROM es demasiado grande para parchearla en el iPhone (máximo 512 MB)."), false)
                return
            }
            romData = data
            RomPatcherEngine.shared.header(rom: data, name: name) { canAdd, headered in
                canAddHeader = canAdd
                isHeadered = headered
                headerOption = false
            }
        }
    }

    private func loadPatch(_ url: URL) {
        message = nil
        resultURL = nil
        patchName = url.lastPathComponent
        patchInfo = nil
        patchUnknown = false
        Task {
            let data: Data? = await Task.detached(priority: .userInitiated) { Self.read(url) }.value
            guard let data else {
                patchName = ""
                message = (tr("No se pudo leer el parche"), false)
                return
            }
            patchData = data
            RomPatcherEngine.shared.info(patch: data, name: url.lastPathComponent) { info in
                patchInfo = info
                patchUnknown = info == nil
            }
        }
    }

    private func apply() {
        guard ready, let romData, let patchData else { return }
        working = true
        message = nil
        resultURL = nil
        let options: [String: Bool] = [
            "requireValidation": requireValidation,
            "removeHeader": headerOption && isHeadered,
            "addHeader": headerOption && !isHeadered && canAddHeader,
            "fixChecksum": fixChecksum,
            "outputSuffix": outputSuffix
        ]
        RomPatcherEngine.shared.apply(rom: romData, romName: romName, patch: patchData, patchName: patchName, options: options) { outcome in
            working = false
            switch outcome {
            case .success(let result):
                let target: URL = PatcherFolders.output.appendingPathComponent(result.name)
                try? FileManager.default.removeItem(at: target)
                do {
                    try result.data.write(to: target)
                    resultURL = target
                    selected = .addLibrary
                    message = result.romMatched ? (tr("Parcheado. La ROM era la que pedía el parche."), true)
                                                : (tr("Parcheado (el parche no comprueba la ROM o es otra versión: si falla, prueba otra ROM)."), true)
                } catch {
                    message = (tr("No se pudo guardar el archivo parcheado"), false)
                }
            case .failure(let failure):
                switch failure {
                case .engineMissing: message = (tr("Falta el motor del parcheador en esta compilación."), false)
                case .unknownPatch: message = (tr("No es un parche que se pueda leer"), false)
                case .invalidROM: message = (tr("Esta ROM no es la que pide el parche (desactiva la comprobación para forzarlo)."), false)
                case .failed(let text): message = (tr("No se pudo parchear: %@", text), false)
                }
            }
        }
    }

    private func presentExport(_ url: URL) {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.filter { $0.session.role == .windowApplication }
        guard var top = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        top.present(picker, animated: true)
    }

    // MARK: Mando

    private func handle(_ action: PadAction) {
        if showLibrary {
            switch action {
            case .up: libraryIndex = max(0, libraryIndex - 1)
            case .down: libraryIndex = min(library.count - 1, libraryIndex + 1)
            case .accept: if library.indices.contains(libraryIndex) { chooseLibrary(library[libraryIndex]) }
            case .cancel: withAnimation { showLibrary = false }
            case .left, .right: break
            }
            return
        }
        let list: [Row] = rows
        let index: Int = list.firstIndex(of: selected) ?? 0
        switch action {
        case .up:
            if selected == .romFiles { selected = .romLibrary; return }
            if selected == .save { selected = .addLibrary; return }
            selected = list[max(0, index - (list.indices.contains(index - 1) && list[index - 1] == .romFiles ? 2 : 1))]
        case .down:
            if selected == .romLibrary { selected = .patch; return }
            if selected == .addLibrary { return }
            selected = list[min(list.count - 1, index + 1)]
        case .left:
            if selected == .romFiles { selected = .romLibrary }
            if selected == .save { selected = .addLibrary }
        case .right:
            if selected == .romLibrary { selected = .romFiles }
            if selected == .addLibrary { selected = .save }
        case .accept:
            switch selected {
            case .romLibrary: if !library.isEmpty { openLibrary() }
            case .romFiles: pick(.rom)
            case .patch: pick(.patch)
            case .validate: requireValidation.toggle()
            case .header: headerOption.toggle()
            case .checksum: fixChecksum.toggle()
            case .suffix: outputSuffix.toggle()
            case .apply: apply()
            case .addLibrary: if let resultURL { onImport(resultURL); dismiss() }
            case .save: if let resultURL { presentExport(resultURL) }
            }
        case .cancel:
            dismiss()
        }
    }
}
