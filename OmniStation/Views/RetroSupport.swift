import Foundation

// MARK: - Núcleos libretro integrados (sacados de ManicEMU)
//
// Cada sistema (NES, SNES, Game Boy, GBA, NDS) tiene su carpeta en Archivos → OmniStation Dock:
//   <Sistema>/Juegos    los juegos (también en subcarpetas)
//   <Sistema>/BIOS      la BIOS si el núcleo la usa (la de GBA o NDS es opcional)
//   <Sistema>/Partidas  partidas (.srm) y estados guardados (.state)
// y uno o varios núcleos para elegir (Ajustes → el sistema → Núcleo, o por juego).
// Los núcleos van en Frameworks/<nombre>.libretro.framework; si una compilación no los trae,
// el sistema no sale.

struct RetroCore: Hashable {
    let id: String
    let name: String
    /// Carpeta del núcleo en Frameworks («snes9x.libretro.framework»).
    let framework: String
    /// Usa JIT (fase 2: de momento todos van sin él).
    let jit: Bool
}

enum RetroSystem: String, CaseIterable, Identifiable {
    case nes, snes, gb, gba, nds

    var id: String { rawValue }

    /// Nombre en Ajustes.
    var title: String {
        switch self {
        case .nes: return "NES"
        case .snes: return "SNES"
        case .gb: return "Game Boy / Color"
        case .gba: return "Game Boy Advance"
        case .nds: return "Nintendo DS"
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
        }
    }

    var extensions: Set<String> {
        switch self {
        case .nes: return ["nes", "fds", "unf", "unif"]
        case .snes: return ["sfc", "smc", "fig", "swc", "bs"]
        case .gb: return ["gb", "gbc", "dmg", "sgb", "cgb"]
        case .gba: return ["gba", "agb"]
        case .nds: return ["nds", "dsi", "ids"]
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
            return [RetroCore(id: "melondsds", name: "melonDS DS", framework: "melondsds.libretro.framework", jit: false),
                    RetroCore(id: "desmume", name: "DeSmuME", framework: "desmume.libretro.framework", jit: false)]
        }
    }

    /// Núcleos que trae esta compilación.
    var availableCores: [RetroCore] {
        cores.filter { OSLibretroEngine.coreAvailable($0.framework) }
    }

    var isAvailable: Bool { !availableCores.isEmpty }

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
        for folder in [games(system), bios(system), saves(system)] {
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
        var found: [String: LibraryGame] = [:]
        var visited: Int = 0
        for case let url as URL in enumerator {
            visited += 1
            if visited > limit { break }
            let ext: String = url.pathExtension.lowercased()
            guard system.extensions.contains(ext) else { continue }
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
        list.append(pick("filter", .graphics, "Imagen", "Nítida mantiene los píxeles; suave los difumina.",
                         [("nearest", "Nítida (píxeles)"), ("linear", "Suave")], "nearest").grouped("Pantalla"))
        list.append(pick("aspect", .graphics, "Proporción", "",
                         [("core", "La del juego"), ("stretch", "Estirar a la pantalla")], "core").grouped("Pantalla"))
        switch system {
        case .gb:
            list.append(pick("opt.gambatte_gb_colorization", .graphics, "Colores (Game Boy)", "Solo con Gambatte, en juegos de Game Boy clásica.",
                             [("auto", "Automático"), ("GBC", "Paleta de Game Boy Color"), ("SGB", "Paleta de Super Game Boy"),
                              ("internal", "Paleta interna"), ("disabled", "Verde original")], "auto").grouped("Pantalla"))
        case .nds:
            list.append(pick("touchPointer", .system, "Pantalla táctil", "Tocar la pantalla de abajo del juego hace de lápiz.",
                             yesNo, "true").grouped("Controles"))
        default:
            break
        }
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

    /// Opciones del núcleo («opt.<clave>» → clave) y de OmniStation para la partida.
    static func launchOptions(_ system: RetroSystem, gameID: String?) -> (core: [String: String], host: [String: String]) {
        let values: [String: String] = EmulatorConfig.effective(.retro(system), gameID: gameID)
        var core: [String: String] = [:]
        var host: [String: String] = [:]
        for (key, value) in values {
            if key.hasPrefix("opt.") {
                core[String(key.dropFirst(4))] = value
            } else {
                host[key] = value
            }
        }
        return (core, host)
    }
}
