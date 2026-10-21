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
            return [RetroCore(id: "melondsds", name: "melonDS DS", framework: "melondsds.libretro.framework", jit: true),
                    RetroCore(id: "desmume", name: "DeSmuME", framework: "desmume.libretro.framework", jit: false)]
        case .ps1:
            return [RetroCore(id: "pcsx_rearmed", name: "PCSX ReARMed", framework: "pcsx.rearmed.libretro.framework", jit: false),
                    RetroCore(id: "beetle_psx_hw", name: "Beetle PSX HW", framework: "mednafen.psx.hw.libretro.framework", jit: true, gpu: true)]
        case .n64:
            return [RetroCore(id: "mupen64plus_next", name: "Mupen64Plus-Next", framework: "mupen64plus.next.libretro.framework", jit: true, gpu: true)]
        case .psp:
            return [RetroCore(id: "ppsspp", name: "PPSSPP", framework: "ppsspp.libretro.framework", jit: true, gpu: true)]
        case .dc:
            return [RetroCore(id: "flycast", name: "Flycast (JIT)", framework: "flycast.libretro.framework", jit: true, requiresJIT: true, gpu: true),
                    RetroCore(id: "flycast_jitless", name: "Flycast (sin JIT)", framework: "flycast-jitless.libretro.framework", jit: false, gpu: true)]
        case .n3ds:
            return [RetroCore(id: "azahar", name: "Azahar", framework: "azahar.libretro.framework", jit: true, gpu: true, vulkan: true)]
        case .gc, .wii:
            return [RetroCore(id: "dolphin", name: "Dolphin", framework: "dolphin.libretro.framework", jit: true, gpu: true, vulkan: true)]
        }
    }

    /// Núcleos que trae esta compilación.
    var availableCores: [RetroCore] {
        cores.filter { OSLibretroEngine.coreAvailable($0.framework) }
    }

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
    static func core(for system: RetroSystem, gameID: String?) -> RetroCore? {
        let available: [RetroCore] = system.availableCores
        guard !available.isEmpty else { return nil }
        let chosen: String = EmulatorConfig.effective(.retro(system), gameID: gameID)["core"] ?? ""
        return available.first { $0.id == chosen } ?? available[0]
    }

    /// Núcleo para jugar ahora: si el elegido solo va con JIT y no lo hay, otro del sistema.
    static func playableCore(for system: RetroSystem, gameID: String?, jit: Bool) -> RetroCore? {
        guard let chosen = core(for: system, gameID: gameID) else { return nil }
        if !chosen.requiresJIT || jit { return chosen }
        return system.availableCores.first { !$0.requiresJIT }
    }

    /// ¿Quiere este juego usar el JIT? (Ajuste «Usar JIT»; por defecto sí.)
    static func wantsJIT(_ system: RetroSystem, gameID: String?) -> Bool {
        guard system.usesJIT else { return false }
        return EmulatorConfig.effective(.retro(system), gameID: gameID)["jit"] != "false"
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
        // Lo que cada núcleo necesita para ir bien aquí (como lo deja ManicEMU), con o sin JIT.
        switch core.id {
        case "melondsds":
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
        case "beetle_psx_hw":
            coreOptions["beetle_psx_hw_cpu_dynarec"] = useJIT ? "execute" : "disabled"
            coreOptions["beetle_psx_hw_renderer"] = "hardware_gl"
        case "mupen64plus_next":
            coreOptions["mupen64plus-cpucore"] = useJIT ? "dynamic_recompiler" : "cached_interpreter"
            coreOptions["mupen64plus-rdp-plugin"] = "gliden64"
        case "ppsspp":
            coreOptions["ppsspp_backend"] = "opengl"
            coreOptions["ppsspp_cpu_core"] = useJIT ? "JIT" : "IR JIT"
            coreOptions["ppsspp_software_rendering_jit"] = useJIT ? "enabled" : "disabled"
        case "flycast", "flycast_jitless":
            let jitless: Bool = core.id == "flycast_jitless"
            coreOptions["reicast_threaded_rendering"] = jitless ? "disabled" : "enabled"
            coreOptions["reicast_dynamic_cpu_ratio"] = "disabled"
            coreOptions["reicast_sh4clock"] = jitless ? "300" : "200"
            if !RetroFolders.hasDreamcastBIOS() { coreOptions["reicast_hle_bios"] = "enabled" }
        case "azahar":
            coreOptions["citra_use_cpu_jit"] = useJIT ? "enabled" : "disabled"
            coreOptions["citra_use_shader_jit"] = useJIT ? "enabled" : "disabled"
            coreOptions["citra_input_type"] = "frontend"
            coreOptions["citra_enable_touch_touchscreen"] = "enabled"
            coreOptions["citra_enable_mouse_touchscreen"] = "disabled"
            coreOptions["citra_use_default_aes_key"] = "disabled"
            host["orient.key"] = "citra_layout_option"
            host["orient.portrait"] = "default"
            host["orient.landscape"] = "side_by_side"
        case "dolphin":
            // Lo mismo que deja ManicEMU con y sin JIT (4: JIT ARM64; 6: su intérprete rápido).
            coreOptions["dolphin_cpu_core"] = useJIT ? "4" : "6"
            coreOptions["dolphin_cpu_clock_rate"] = useJIT ? "1.00" : "0.40"
            coreOptions["dolphin_osd_enabled"] = "disabled"
            coreOptions["dolphin_fast_disc_speed"] = useJIT ? "disabled" : "enabled"
            coreOptions["dolphin_gpu_texture_decoding"] = useJIT ? "disabled" : "enabled"
            coreOptions["dolphin_shader_compilation_mode"] = useJIT ? "0" : "3"
            coreOptions["dolphin_vi_skip"] = useJIT ? "disabled" : "enabled"
            coreOptions["dolphin_skip_gc_bios"] = "disabled"
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
enum RetroJIT {
    static var holding: Bool = false
}
