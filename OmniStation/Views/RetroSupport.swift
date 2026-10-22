import Foundation

// MARK: - Núcleos libretro integrados (sacados de ManicEMU)
//
// Cada sistema tiene su carpeta en Archivos → OmniStation Dock:
//   <Sistema>/Juegos    los juegos (también en subcarpetas)
//   <Sistema>/BIOS      la BIOS si el núcleo la usa
//   <Sistema>/Partidas  partidas (.srm) y estados guardados (.state)
// y uno o varios núcleos para elegir (Ajustes → el sistema → Núcleo, o por juego).
// Los núcleos van en Frameworks/<nombre>.libretro.framework; si una compilación no los trae,
// el sistema no sale.
//
// Fase 1: NES, SNES, Game Boy, GBA y NDS (imagen por CPU).
// Fase 2: PS1, N64, PSP y Dreamcast (imagen por GPU con OpenGL ES y JIT si OmniStation lo tiene).

struct RetroCore: Hashable {
    let id: String
    let name: String
    /// Carpeta del núcleo en Frameworks («snes9x.libretro.framework»).
    let framework: String
    /// Puede usar JIT (si OmniStation lo tiene; si no, va en modo intérprete).
    let jit: Bool
    /// Solo funciona con JIT (Flycast): sin él se usa otro núcleo del sistema.
    var requiresJIT: Bool = false
    /// Pinta con la GPU (OpenGL ES).
    var gpu: Bool = false
    /// Pinta con la GPU por Vulkan (MoltenVK): 3DS, GameCube y Wii.
    var vulkan: Bool = false
    /// Pide su memoria de JIT a OmniStation (RETRO_ENVIRONMENT_EXEC_MEM_ALLOC): usa el JIT
    /// permanente y no necesita el depurador en cada partida. Los compilados por OmniStation.
    var execMem: Bool = false
}

enum RetroSystem: String, CaseIterable, Identifiable {
    case nes, snes, gb, gba, nds, ps1, n64, psp, dc
    case n3ds = "3ds"
    case gc, wii

    var id: String { rawValue }

    /// Nombre en Ajustes.
    var title: String {
        switch self {
        case .nes: return "NES"
        case .snes: return "SNES"
        case .gb: return "Game Boy / Color"
        case .gba: return "Game Boy Advance"
        case .nds: return "Nintendo DS"
        case .ps1: return "PlayStation"
        case .n64: return "Nintendo 64"
        case .psp: return "PSP"
        case .dc: return "Dreamcast"
        case .n3ds: return "Nintendo 3DS"
        case .gc: return "GameCube"
        case .wii: return "Wii"
        }
    }

    /// Carpeta en Archivos.
    var folderName: String {
        switch self {
        case .nes: return "NES"
        case .snes: return "SNES"
        case .gb: return "Game Boy"
        case .gba: return "GBA"
        case .nds: return "NDS"
        case .ps1: return "PS1"
        case .n64: return "N64"
        case .psp: return "PSP"
        case .dc: return "Dreamcast"
        case .n3ds: return "3DS"
        case .gc: return "GameCube"
        case .wii: return "Wii"
        }
    }

    var extensions: Set<String> {
        switch self {
        case .nes: return ["nes", "fds", "unf", "unif"]
        case .snes: return ["sfc", "smc", "fig", "swc", "bs"]
        case .gb: return ["gb", "gbc", "dmg", "sgb", "cgb"]
        case .gba: return ["gba", "agb"]
        case .nds: return ["nds", "dsi", "ids"]
        case .ps1: return ["cue", "chd", "pbp", "m3u", "ccd", "iso", "img", "bin"]
        case .n64: return ["z64", "n64", "v64"]
        case .psp: return ["iso", "cso", "pbp", "chd"]
        case .dc: return ["gdi", "cdi", "chd", "cue", "m3u"]
        case .n3ds: return ["3ds", "cci", "cxi", "3dsx", "cia"]
        case .gc: return ["iso", "gcm", "gcz", "rvz", "ciso", "dol", "m3u"]
        case .wii: return ["iso", "wbfs", "rvz", "gcz", "wad", "ciso", "m3u"]
        }
    }

    /// Pistas de un disco (.bin, .img…): no son juegos si en su carpeta hay un .cue, .gdi o .ccd.
    var trackExtensions: Set<String> {
        switch self {
        case .ps1, .dc: return ["bin", "img", "raw"]
        default: return []
        }
    }

    /// Plataforma en la biblioteca (Game Boy Color se separa por la extensión).
    func platform(forExtension ext: String) -> String {
        switch self {
        case .nes: return "NES"
        case .snes: return "SNES"
        case .gb: return ext.lowercased() == "gbc" || ext.lowercased() == "cgb" ? "Game Boy Color" : "Game Boy"
        case .gba: return "GBA"
        case .nds: return "NDS"
        case .ps1: return "PS1"
        case .n64: return "N64"
        case .psp: return "PSP"
        case .dc: return "Dreamcast"
        case .n3ds: return "3DS"
        case .gc: return "GameCube"
        case .wii: return "Wii"
        }
    }

    /// Núcleos de ManicEMU para este sistema (el primero es el de por defecto).
    var cores: [RetroCore] {
        switch self {
        case .nes:
            return [RetroCore(id: "nestopia", name: "Nestopia", framework: "nestopia.libretro.framework", jit: false)]
        case .snes:
            return [RetroCore(id: "snes9x", name: "Snes9x", framework: "snes9x.libretro.framework", jit: false)]
        case .gb:
            return [RetroCore(id: "gambatte", name: "Gambatte", framework: "gambatte.libretro.framework", jit: false),
                    RetroCore(id: "mgba", name: "mGBA", framework: "mgba.libretro.framework", jit: false)]
        case .gba:
            return [RetroCore(id: "mgba", name: "mGBA", framework: "mgba.libretro.framework", jit: false),
                    RetroCore(id: "gpsp", name: "gpSP", framework: "gpsp.libretro.framework", jit: false),
                    RetroCore(id: "vbam", name: "VBA-M", framework: "vbam.libretro.framework", jit: false)]
        case .nds:
            // El compilado por OmniStation (JIT permanente) primero; el de ManicEMU, si el nuestro no está.
            return [RetroCore(id: "melondsds_omni", name: "melonDS DS", framework: "melondsds_omni.libretro.framework", jit: true, execMem: true),
                    RetroCore(id: "melondsds", name: "melonDS DS (ManicEMU)", framework: "melondsds.libretro.framework", jit: true),
                    RetroCore(id: "desmume", name: "DeSmuME", framework: "desmume.libretro.framework", jit: false)]
        case .ps1:
            // El nuestro, con dynarec (JIT permanente); el de ManicEMU va sin dynarec.
            return [RetroCore(id: "pcsx_rearmed_omni", name: "PCSX ReARMed", framework: "pcsx_rearmed_omni.libretro.framework", jit: true, execMem: true),
                    RetroCore(id: "pcsx_rearmed", name: "PCSX ReARMed (ManicEMU)", framework: "pcsx.rearmed.libretro.framework", jit: false),
                    RetroCore(id: "beetle_psx_hw", name: "Beetle PSX HW", framework: "mednafen.psx.hw.libretro.framework", jit: true, gpu: true)]
        case .n64:
            // El nuestro, con dynarec (JIT permanente); el de ManicEMU va sin dynarec.
            return [RetroCore(id: "mupen64plus_next_omni", name: "Mupen64Plus-Next", framework: "mupen64plus_next_omni.libretro.framework", jit: true, gpu: true, execMem: true),
                    RetroCore(id: "mupen64plus_next", name: "Mupen64Plus-Next (ManicEMU)", framework: "mupen64plus.next.libretro.framework", jit: true, gpu: true)]
        case .psp:
            // El compilado por OmniStation (JIT permanente) primero; el de ManicEMU, si el nuestro no está.
            return [RetroCore(id: "ppsspp_omni", name: "PPSSPP", framework: "ppsspp_omni.libretro.framework", jit: true, gpu: true, execMem: true),
                    RetroCore(id: "ppsspp", name: "PPSSPP (ManicEMU)", framework: "ppsspp.libretro.framework", jit: true, gpu: true)]
        case .dc:
            // El nuestro (JIT permanente) primero; sin JIT se usa el de ManicEMU sin JIT.
            return [RetroCore(id: "flycast_omni", name: "Flycast", framework: "flycast_omni.libretro.framework", jit: true, requiresJIT: true, gpu: true, execMem: true),
                    RetroCore(id: "flycast", name: "Flycast (JIT, ManicEMU)", framework: "flycast.libretro.framework", jit: true, requiresJIT: true, gpu: true),
                    RetroCore(id: "flycast_jitless", name: "Flycast (sin JIT)", framework: "flycast-jitless.libretro.framework", jit: false, gpu: true)]
        case .n3ds:
            // El compilado por OmniStation (JIT permanente) primero; el de ManicEMU, si el nuestro no está.
            return [RetroCore(id: "azahar_omni", name: "Azahar", framework: "azahar_omni.libretro.framework", jit: true, gpu: true, vulkan: true, execMem: true),
                    RetroCore(id: "azahar", name: "Azahar (ManicEMU)", framework: "azahar.libretro.framework", jit: true, gpu: true, vulkan: true)]
        case .gc, .wii:
            // El compilado por OmniStation (Dolphin de libretro, con JIT permanente).
            return [RetroCore(id: "dolphin_omni", name: "Dolphin", framework: "dolphin_omni.libretro.framework", jit: true, gpu: true, vulkan: true, execMem: true)]
        }
    }

    /// Núcleos que trae esta compilación (se mira una vez: los archivos de la app no cambian).
    var availableCores: [RetroCore] {
        if let known = RetroSystem.availableCache[self] { return known }
        let found: [RetroCore] = cores.filter { OSLibretroEngine.coreAvailable($0.framework) }
        RetroSystem.availableCache[self] = found
        return found
    }

    private static var availableCache: [RetroSystem: [RetroCore]] = [:]

    var isAvailable: Bool { !availableCores.isEmpty }

    /// ¿Alguno de sus núcleos puede usar JIT?
    var usesJIT: Bool { cores.contains { $0.jit } }

    /// Botones del mando táctil (lo entiende OSLibretroEngine).
    var touchLayout: String { rawValue }

    /// Sistema de un juego de la biblioteca por su «source».
    static func from(source: String) -> RetroSystem? {
        guard source.hasPrefix(RetroFolders.sourcePrefix) else { return nil }
        return RetroSystem(rawValue: String(source.dropFirst(RetroFolders.sourcePrefix.count)))
    }

    var source: String { RetroFolders.sourcePrefix + rawValue }

    /// Qué hace falta para la BIOS (vacío: nada).
    var biosHint: String {
        switch self {
        case .gba: return "Opcional: gba_bios.bin (mGBA y VBA-M van sin ella; gpSP la recomienda)."
        case .nds: return "Opcional: bios7.bin, bios9.bin y firmware.bin (melonDS DS va sin ellas)."
        case .ps1: return "PCSX ReARMed va sin BIOS. Beetle PSX HW la necesita: scph5501.bin (o scph5500.bin / scph5502.bin)."
        case .dc: return "Opcional: dc_boot.bin y dc_flash.bin dentro de BIOS → dc (sin ellas, Flycast usa su BIOS interna)."
        case .n3ds: return "Los juegos tienen que estar descifrados (.3ds, .cci, .cxi o .3dsx)."
        default: return ""
        }
    }
}

enum RetroFolders {
    static let sourcePrefix = "core:retro:"
    static let idPrefix = "Retro/"

    private static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func root(_ system: RetroSystem) -> URL { documents.appendingPathComponent(system.folderName, isDirectory: true) }
    static func games(_ system: RetroSystem) -> URL { root(system).appendingPathComponent("Juegos", isDirectory: true) }
    static func bios(_ system: RetroSystem) -> URL { root(system).appendingPathComponent("BIOS", isDirectory: true) }
    static func saves(_ system: RetroSystem) -> URL { root(system).appendingPathComponent("Partidas", isDirectory: true) }

    static func ensure(_ system: RetroSystem) {
        var folders: [URL] = [games(system), bios(system), saves(system)]
        if system == .dc { folders.append(bios(system).appendingPathComponent("dc", isDirectory: true)) }
        for folder in folders {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
    }

    /// Juegos de <Sistema>/Juegos. `fileName` es la ruta dentro de Juegos.
    static func scanGames(_ system: RetroSystem, limit: Int = 20000) -> [LibraryGame] {
        let base: URL = games(system).standardizedFileURL
        guard let enumerator = FileManager.default.enumerator(
            at: base,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        let baseCount: Int = base.pathComponents.count
        // Primero todos los archivos, por carpeta: las pistas y los discos de una lista .m3u no
        // son juegos sueltos.
        var files: [URL] = []
        var visited: Int = 0
        for case let url as URL in enumerator {
            visited += 1
            if visited > limit { break }
            if system.extensions.contains(url.pathExtension.lowercased()) { files.append(url) }
        }
        var sheetFolders: Set<String> = []
        var listed: Set<String> = []
        for url in files {
            let ext: String = url.pathExtension.lowercased()
            let folder: String = url.deletingLastPathComponent().standardizedFileURL.path
            if ext == "cue" || ext == "gdi" || ext == "ccd" { sheetFolders.insert(folder) }
            if ext == "m3u", let text = try? String(contentsOf: url, encoding: .utf8) {
                for line in text.components(separatedBy: .newlines) {
                    let entry: String = line.trimmingCharacters(in: .whitespaces)
                    if entry.isEmpty || entry.hasPrefix("#") { continue }
                    let name: String = (entry.replacingOccurrences(of: "\\", with: "/") as NSString).lastPathComponent
                    listed.insert(folder + "/" + name.lowercased())
                }
            }
        }
        var found: [String: LibraryGame] = [:]
        for url in files {
            let ext: String = url.pathExtension.lowercased()
            let folder: String = url.deletingLastPathComponent().standardizedFileURL.path
            if system.trackExtensions.contains(ext) && sheetFolders.contains(folder) { continue }
            if ext != "m3u" && listed.contains(folder + "/" + url.lastPathComponent.lowercased()) { continue }
            let parts: [String] = Array(url.standardizedFileURL.pathComponents.dropFirst(baseCount))
            guard !parts.isEmpty else { continue }
            let relative: String = parts.joined(separator: "/")
            let id: String = idPrefix + system.rawValue + "/" + relative
            found[id] = LibraryGame(id: id, name: url.deletingPathExtension().lastPathComponent,
                                    platform: system.platform(forExtension: ext), launchURL: nil,
                                    source: system.source, fileName: relative)
        }
        return found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func path(_ system: RetroSystem, fileName: String) -> String {
        games(system).appendingPathComponent(fileName).path
    }

    static func filesAppURL(_ system: RetroSystem) -> URL? {
        URL(string: "shareddocuments://" + root(system).path)
    }

    /// Lo que necesita el núcleo en su carpeta de sistema y va dentro de la app
    /// (PSP: los archivos de PPSSPP, en BIOS/PPSSPP). Se copia la primera vez y al actualizar.
    static func prepareSystemFiles(_ system: RetroSystem) {
        if system == .n3ds { prepare3DSKeys() }
        let folder: String
        switch system {
        case .psp: folder = "PPSSPP"
        case .gc, .wii: folder = "dolphin-emu"
        default: return
        }
        let source: URL = Bundle.main.bundleURL.appendingPathComponent("RetroSystem/" + folder, isDirectory: true)
        let manager = FileManager.default
        guard manager.fileExists(atPath: source.path) else { return }
        let target: URL = bios(system).appendingPathComponent(folder, isDirectory: true)
        let marker: URL = target.appendingPathComponent(".omnistation")
        let version: String = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "0"
        if let current = try? String(contentsOf: marker, encoding: .utf8), current == version { return }
        try? manager.createDirectory(at: target, withIntermediateDirectories: true)
        let items: [String] = (try? manager.contentsOfDirectory(atPath: source.path)) ?? []
        for item in items {
            let from: URL = source.appendingPathComponent(item)
            let to: URL = target.appendingPathComponent(item)
            try? manager.removeItem(at: to)
            try? manager.copyItem(at: from, to: to)
        }
        try? version.write(to: marker, atomically: true, encoding: .utf8)
    }

    /// 3DS: Azahar ya trae las claves para las ROMs cifradas. Solo hace falta seeddb.bin para algunos
    /// juegos (los de eShop o recientes): el que se pone en 3DS/BIOS se copia a donde lo lee Azahar
    /// (Partidas/Azahar/sysdata). Un aes_keys.txt o keys.txt que se copiara antes se aparta: con
    /// claves malas se cerraban los dos núcleos (también el de ManicEMU, que lee la misma carpeta).
    static func prepare3DSKeys() {
        let manager = FileManager.default
        let target: URL = saves(.n3ds).appendingPathComponent("Azahar/sysdata", isDirectory: true)
        for name in ["aes_keys.txt", "keys.txt"] {
            let file: URL = target.appendingPathComponent(name)
            guard manager.fileExists(atPath: file.path) else { continue }
            let aside: URL = target.appendingPathComponent(name + ".desactivado")
            try? manager.removeItem(at: aside)
            try? manager.moveItem(at: file, to: aside)
        }
        let source: URL = bios(.n3ds)
        let candidates: [URL] = [source.appendingPathComponent("seeddb.bin"),
                                 source.appendingPathComponent("sysdata/seeddb.bin")]
        guard let from = candidates.first(where: { manager.fileExists(atPath: $0.path) }) else { return }
        let to: URL = target.appendingPathComponent("seeddb.bin")
        let fromSize = (try? manager.attributesOfItem(atPath: from.path)[.size] as? NSNumber)?.intValue
        let toSize = (try? manager.attributesOfItem(atPath: to.path)[.size] as? NSNumber)?.intValue
        let fromDate = (try? manager.attributesOfItem(atPath: from.path)[.modificationDate]) as? Date
        let toDate = (try? manager.attributesOfItem(atPath: to.path)[.modificationDate]) as? Date
        if fromSize == toSize, let fromDate, let toDate, toDate >= fromDate { return }
        try? manager.createDirectory(at: target, withIntermediateDirectories: true)
        try? manager.removeItem(at: to)
        try? manager.copyItem(at: from, to: to)
    }

    /// Copia el seeddb.bin elegido a 3DS/BIOS. Devuelve si lo copió.
    static func import3DSSeeds(_ urls: [URL]) -> Bool {
        let manager = FileManager.default
        guard let url = urls.first(where: { $0.pathExtension.lowercased() == "bin" }) else { return false }
        let folder: URL = bios(.n3ds)
        try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let accessing: Bool = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let to: URL = folder.appendingPathComponent("seeddb.bin")
        try? manager.removeItem(at: to)
        guard (try? manager.copyItem(at: url, to: to)) != nil else { return false }
        prepare3DSKeys()
        return true
    }

    /// ¿Está seeddb.bin? (En 3DS/BIOS o ya copiado a donde lo lee Azahar.)
    static func has3DSSeeds() -> Bool {
        let manager = FileManager.default
        return [bios(.n3ds).appendingPathComponent("seeddb.bin"),
                bios(.n3ds).appendingPathComponent("sysdata/seeddb.bin"),
                saves(.n3ds).appendingPathComponent("Azahar/sysdata/seeddb.bin")].contains {
            manager.fileExists(atPath: $0.path)
        }
    }

    /// ¿Está la BIOS de Dreamcast? (Si no, Flycast usa la suya.)
    static func hasDreamcastBIOS() -> Bool {
        let folder: URL = bios(.dc)
        let manager = FileManager.default
        return manager.fileExists(atPath: folder.appendingPathComponent("dc/dc_boot.bin").path)
            || manager.fileExists(atPath: folder.appendingPathComponent("dc_boot.bin").path)
    }
}

// MARK: - Ajustes de los núcleos libretro

enum RetroConfig {
    private static func pick(_ id: String, _ tab: EmuTab, _ title: String, _ detail: String,
                             _ choices: [(String, String)], _ value: String) -> EmuOption {
        EmuOption(id: id, tab: tab, title: title, detail: detail,
                  choices: choices.map { EmuChoice(value: $0.0, label: $0.1) }, defaultValue: value)
    }

    private static let yesNo: [(String, String)] = [("true", "Sí"), ("false", "No")]

    /// Opciones de cada sistema. Las que empiezan por «opt.» van tal cual al núcleo (sus claves);
    /// el resto son de OmniStation (núcleo, imagen, HUD).
    static func options(_ system: RetroSystem) -> [EmuOption] {
        var list: [EmuOption] = []
        let cores: [RetroCore] = system.availableCores.isEmpty ? system.cores : system.availableCores
        if cores.count > 1 {
            list.append(pick("core", .system, "Núcleo", "Cuál emula este sistema. Si un juego va mal, prueba otro.",
                             cores.map { ($0.id, $0.name) }, cores[0].id).grouped("Núcleo"))
        }
        if system.usesJIT {
            list.append(pick("jit", .system, "Usar JIT", "Si OmniStation tiene JIT, el núcleo va mucho más rápido. Sin JIT va en modo intérprete.",
                             yesNo, "true").grouped("Núcleo"))
        }
        list.append(pick("filter", .graphics, "Imagen", "Nítida mantiene los píxeles; suave los difumina.",
                         [("nearest", "Nítida (píxeles)"), ("linear", "Suave")], system.cores.contains(where: { $0.gpu }) ? "linear" : "nearest").grouped("Pantalla"))
        list.append(pick("aspect", .graphics, "Proporción", "",
                         [("core", "La del juego"), ("stretch", "Estirar a la pantalla")], "core").grouped("Pantalla"))
        if system == .nds || system == .n3ds {
            list.append(pick("touchPointer", .input, "Pantalla táctil", "Tocar la pantalla de abajo del juego hace de lápiz.",
                             yesNo, "true").grouped("Controles"))
        }
        // Las de cada núcleo (las que él declara): las importantes en su pestaña y el resto en Avanzado.
        list += RetroCoreOptions.cachedOptions(system)
        list.append(pick("hud", .hud, "Indicador de rendimiento", "FPS, temperatura y RAM arriba a la derecha.", yesNo, "false"))
        list.append(pick("hudThermal", .hud, "Temperatura", "", yesNo, "true"))
        list.append(pick("hudMemory", .hud, "RAM usada y libre", "", yesNo, "true"))
        list.append(pick("hudBattery", .hud, "Batería", "", yesNo, "false"))
        return list
    }

    /// Núcleo de un juego (el elegido para él, el general o el primero que haya).
    /// Núcleo para la próxima partida de un juego (una vez): el Azahar de ManicEMU cuando el
    /// nuestro no pudo abrir una ROM cifrada (sin claves).
    static var onceCore: [String: String] = [:]

    static func core(for system: RetroSystem, gameID: String?) -> RetroCore? {
        let available: [RetroCore] = system.availableCores
        guard !available.isEmpty else { return nil }
        if let gameID, let once = onceCore[gameID], let core = available.first(where: { $0.id == once }) {
            return core
        }
        // Solo la opción «core» (sin montar todas las opciones de todos los núcleos: iba lento).
        let target: EmuConfigTarget = .retro(system)
        let own: String? = gameID.flatMap { EmulatorConfig.game(target, $0)["core"] }
        let chosen: String = own ?? EmulatorConfig.global(target)["core"] ?? ""
        return available.first { $0.id == chosen } ?? available[0]
    }

    /// Núcleo para jugar ahora: si el elegido solo va con JIT y no lo hay, otro del sistema.
    static func playableCore(for system: RetroSystem, gameID: String?, jit: Bool) -> RetroCore? {
        guard let chosen = core(for: system, gameID: gameID) else { return nil }
        if !chosen.requiresJIT || jit { return chosen }
        return system.availableCores.first { !$0.requiresJIT }
    }

    /// Memoria libre (MB) que conviene tener para abrir un juego del sistema sin que iOS cierre la
    /// app. Los núcleos se quedan cargados y algunos (GameCube/Wii, 3DS) no devuelven toda la
    /// memoria al salir: después de varios juegos puede no quedar bastante.
    static func memoryNeededMB(_ system: RetroSystem) -> Int {
        let estimate: Int
        switch system {
        case .gc, .wii: estimate = 1600
        case .n3ds: estimate = 1400
        case .psp, .dc: estimate = 700
        case .n64: estimate = 500
        case .ps1, .nds: estimate = 400
        default: estimate = 200
        }
        // Con lo que gastó de verdad en este iPhone (lo más alto visto), más un margen.
        let seen: Int = UserDefaults.standard.integer(forKey: "retroPeakMB." + system.rawValue)
        guard seen > 0 else { return estimate }
        return max(Int(Double(seen) * 1.15) + 150, estimate / 2)
    }

    /// Apunta cuánta memoria llegó a gastar una partida del sistema (se guarda la más alta).
    static func recordMemoryPeak(_ system: RetroSystem, megabytes: Int) {
        guard megabytes > 0 else { return }
        let key: String = "retroPeakMB." + system.rawValue
        if megabytes > UserDefaults.standard.integer(forKey: key) {
            UserDefaults.standard.set(megabytes, forKey: key)
        }
    }

    /// ¿Tendrá JIT de verdad esta partida? Con el depurador enganchado, o (los núcleos que piden su
    /// memoria a OmniStation) con el JIT permanente ya preparado.
    static func jitAvailable(for core: RetroCore) -> Bool {
        OSLibretroEngine.jitActive || (core.execMem && OSLibretroEngine.persistentJITReady)
    }

    /// ¿Quiere este juego usar el JIT? (Ajuste «Usar JIT»; por defecto sí.)
    static func wantsJIT(_ system: RetroSystem, gameID: String?) -> Bool {
        guard system.usesJIT else { return false }
        let target: EmuConfigTarget = .retro(system)
        let own: String? = gameID.flatMap { EmulatorConfig.game(target, $0)["jit"] }
        return (own ?? EmulatorConfig.global(target)["jit"]) != "false"
    }

    /// Opciones del núcleo («opt.<clave>» → clave) y de OmniStation para la partida.
    /// `jit`: si la partida va a tener JIT de verdad (y el juego lo quiere).
    static func launchOptions(_ system: RetroSystem, core: RetroCore, gameID: String?, jit: Bool) -> (core: [String: String], host: [String: String]) {
        // Que estén las opciones del núcleo que va a jugar (si no, se perderían los cambios).
        RetroCoreOptions.prepare(core)
        let wants: Bool = wantsJIT(system, gameID: gameID)
        let values: [String: String] = EmulatorConfig.effective(.retro(system), gameID: gameID)
        var coreOptions: [String: String] = [:]
        var host: [String: String] = [:]
        for (key, value) in values {
            if key.hasPrefix("opt.") {
                coreOptions[String(key.dropFirst(4))] = value
            } else {
                host[key] = value
            }
        }
        let useJIT: Bool = jit && core.jit && wants
        // «jit»: si el juego lo quiere (el motor mira si de verdad lo hay); «jitOption»: el menú lo enseña.
        host["jit"] = (core.jit && wants) ? "true" : "false"
        host["jitOption"] = core.jit ? "true" : "false"
        host["gpu"] = core.vulkan ? "vulkan" : (core.gpu ? "true" : "false")
        // Núcleo que pide su memoria de JIT a OmniStation: puede usar el JIT permanente.
        host["jitPool"] = core.execMem ? "true" : "false"
        // Lo que cada núcleo necesita para ir bien aquí (como lo deja ManicEMU), con o sin JIT.
        switch core.id {
        case "melondsds", "melondsds_omni":
            coreOptions["melonds_jit_enable"] = useJIT ? "enabled" : "disabled"
            coreOptions["melonds_number_of_screen_layouts"] = "1"
            coreOptions["melonds_show_cursor"] = "disabled"
            coreOptions["melonds_mic_input_active"] = "always"
            host["orient.key"] = "melonds_screen_layout1"
            host["orient.portrait"] = "top-bottom"
            host["orient.landscape"] = "left-right"
        case "desmume":
            coreOptions["desmume_pointer_type"] = "touch"
            coreOptions["desmume_pointer_device_l"] = "emulated"
            coreOptions["desmume_pointer_device_r"] = "emulated"
            host["orient.key"] = "desmume_screens_layout"
            host["orient.portrait"] = "top/bottom"
            host["orient.landscape"] = "left/right"
        case "pcsx_rearmed":
            coreOptions["pcsx_rearmed_drc"] = "disabled"
        case "pcsx_rearmed_omni":
            // Dynarec solo si OmniStation le da memoria de JIT (el núcleo lo vuelve a mirar).
            coreOptions["pcsx_rearmed_drc"] = useJIT ? "enabled" : "disabled"
        case "beetle_psx_hw":
            coreOptions["beetle_psx_hw_cpu_dynarec"] = useJIT ? "execute" : "disabled"
            coreOptions["beetle_psx_hw_renderer"] = "hardware_gl"
        case "mupen64plus_next", "mupen64plus_next_omni":
            // El nuestro además mira si OmniStation le da memoria de JIT (si no, intérprete con caché).
            coreOptions["mupen64plus-cpucore"] = useJIT ? "dynamic_recompiler" : "cached_interpreter"
            coreOptions["mupen64plus-rdp-plugin"] = "gliden64"
        case "ppsspp", "ppsspp_omni":
            // El nuestro además mira si OmniStation le da memoria de JIT (si no, intérprete IR).
            coreOptions["ppsspp_backend"] = "opengl"
            coreOptions["ppsspp_cpu_core"] = useJIT ? "JIT" : "IR JIT"
            coreOptions["ppsspp_software_rendering_jit"] = useJIT ? "enabled" : "disabled"
        case "flycast", "flycast_jitless", "flycast_omni":
            let jitless: Bool = core.id == "flycast_jitless"
            coreOptions["reicast_threaded_rendering"] = jitless ? "disabled" : "enabled"
            coreOptions["reicast_dynamic_cpu_ratio"] = "disabled"
            coreOptions["reicast_sh4clock"] = jitless ? "300" : "200"
            if !RetroFolders.hasDreamcastBIOS() { coreOptions["reicast_hle_bios"] = "enabled" }
        case "azahar", "azahar_omni":
            // El nuestro además mira si OmniStation le da memoria de JIT (si no, intérprete).
            coreOptions["citra_use_cpu_jit"] = useJIT ? "enabled" : "disabled"
            coreOptions["citra_use_shader_jit"] = useJIT ? "enabled" : "disabled"
            coreOptions["citra_input_type"] = "frontend"
            coreOptions["citra_enable_touch_touchscreen"] = "enabled"
            coreOptions["citra_enable_mouse_touchscreen"] = "disabled"
            coreOptions["citra_use_default_aes_key"] = "disabled"
            host["orient.key"] = "citra_layout_option"
            host["orient.portrait"] = "default"
            host["orient.landscape"] = "side_by_side"
        case "dolphin_omni":
            // Dolphin de libretro: él mismo mira si OmniStation le da memoria de JIT (si no, intérprete).
            coreOptions["dolphin_renderer"] = "Hardware"
            coreOptions["dolphin_cpu_core"] = useJIT ? "4" : "5"
            coreOptions["dolphin_osd_enabled"] = "disabled"
            coreOptions["dolphin_log_level"] = "1"
        default:
            break
        }
        // NDS y 3DS: la proporción sale del fotograma (cambia al poner las pantallas al lado).
        if system == .nds || system == .n3ds { host["frameAspect"] = "true" }
        return (coreOptions, host)
    }
}

/// El depurador que OmniStation se pide a sí misma para el JIT de un núcleo libretro: se suelta
/// al salir del juego.
/// JIT permanente: se prepara una vez al abrir la app (durante la bienvenida) y vale toda la
/// sesión para los núcleos que lo usan (Dolphin), aunque luego se vaya la VPN o el depurador.
/// - SideStore: se engancha el depurador un momento con la extensión de JIT (hace falta la VPN:
///   wifi o modo avión), se prepara el bloque y se suelta.
/// - LiveContainer: si la app se abrió con JIT (StikDebug), se prepara con ese depurador y se suelta.
final class PermanentJIT {
    static let shared = PermanentJIT()
    private(set) var busy: Bool = false
    private var triedAt: Date = .distantPast

    /// ¿Hace falta? (hay algún núcleo que lo use y aún no está preparado)
    var wanted: Bool {
        guard !OSLibretroEngine.persistentJITReady else { return false }
        // Dolphin y Azahar (núcleos con execMem) y ARMSX2 integrado.
        return OSArmsx2Engine.coreBundled || RetroSystem.allCases.contains { $0.availableCores.contains(where: \.execMem) }
    }

    /// Lo intenta (en el hilo principal). `completion(listo)`; si ya estaba, enseguida.
    func prepare(force: Bool = false, completion: @escaping (Bool) -> Void) {
        if OSLibretroEngine.persistentJITReady { completion(true); return }
        guard wanted, !busy, force || Date().timeIntervalSince(triedAt) > 20,
              !OSLibretroEngine.shared.busy, !OSArmsx2Engine.shared.busy, !OSMeloNXEngine.shared.busy else {
            completion(false)
            return
        }
        triedAt = Date()
        if DebugSupport.isInsideLiveContainer {
            // Solo con el depurador de StikDebug enganchado al abrir la app (y no el de otra partida).
            guard OSLibretroEngine.jitActive, RetroJIT.fresh else { completion(false); return }
            busy = true
            // Fuera del hilo principal (el depurador tarda en preparar el bloque y la app no se para).
            DispatchQueue.global(qos: .userInitiated).async {
                let ready: Bool = OSLibretroEngine.preparePersistentJIT()
                // Se suelta después (como en SideStore): con él puesto, los núcleos de ManicEMU no
                // preparaban bien su propia memoria. Cada uno lo vuelve a pedir en su partida.
                OSLibretroEngine.detachJITDebugger()
                DispatchQueue.main.async {
                    self.busy = false
                    completion(ready)
                }
            }
            return
        }
        let language: String = L10n.resolve(UserDefaults.standard.string(forKey: "appLanguage") ?? "system")
        guard OSArmsx2Engine.helperBundled, BuiltInJIT.preflightProblem(lang: language) == nil,
              let pairing = PairingFile.data() else {
            completion(false)
            return
        }
        busy = true
        OSMeloNXEngine.shared.prepareSharedJIT(withPairing: pairing, progress: nil) { success, _ in
            guard success else {
                self.busy = false
                completion(false)
                return
            }
            DispatchQueue.global(qos: .userInitiated).async {
                let ready: Bool = OSLibretroEngine.preparePersistentJIT()
                // Listo o no, el depurador se suelta y se cierra la extensión (no se queda nada enganchado).
                OSLibretroEngine.detachJITDebugger()
                DispatchQueue.main.async {
                    self.busy = false
                    RetroJIT.holding = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        OSMeloNXEngine.shared.releaseSharedJIT()
                    }
                    completion(ready)
                }
            }
        }
    }
}

enum RetroJIT {
    static var holding: Bool = false
    /// El depurador enganchado ahora sirve para los núcleos libretro: se enganchó para ellos (o con
    /// él se abrió la app). Los núcleos preparan su memoria de JIT al empezar cada partida y
    /// necesitan un depurador que la atienda; si lo usó ARMSX2 o MeloNX (con su propio guion), se
    /// suelta y se vuelve a enganchar antes de jugar.
    static var fresh: Bool = true
}
