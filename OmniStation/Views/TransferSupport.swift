import Foundation

// MARK: - Importar: qué es cada archivo y adónde va

/// Consola a la que va un juego (o algo suyo) al importarlo.
enum ImportTarget: Hashable {
    case retro(RetroSystem)
    case ps2
    case switchCore

    var title: String {
        switch self {
        case .retro(let system): return system.title
        case .ps2: return "PlayStation 2"
        case .switchCore: return "Nintendo Switch"
        }
    }

    /// Carpeta de juegos.
    var gamesFolder: URL {
        switch self {
        case .retro(let system): return RetroFolders.games(system)
        case .ps2: return ARMSX2CoreFolders.games
        case .switchCore: return MeloNXCoreFolders.games
        }
    }

    /// Carpeta de BIOS.
    var biosFolder: URL {
        switch self {
        case .retro(.dc): return RetroFolders.bios(.dc).appendingPathComponent("dc", isDirectory: true)
        case .retro(let system): return RetroFolders.bios(system)
        case .ps2: return ARMSX2CoreFolders.bios
        case .switchCore: return MeloNXCoreFolders.keys
        }
    }

    /// Ruta corta para enseñar («PS1/Juegos»).
    func shortPath(_ url: URL) -> String {
        let documents: String = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].path
        let path: String = url.path
        return path.hasPrefix(documents) ? String(path.dropFirst(documents.count + 1)) : url.lastPathComponent
    }

    var rescan: ImportRescan {
        switch self {
        case .retro: return .retro
        case .ps2: return .armsx2
        case .switchCore: return .melonx
        }
    }

    /// ¿Hay núcleo para esta consola en esta compilación?
    var available: Bool {
        switch self {
        case .retro(let system): return system.isAvailable
        case .ps2: return OSArmsx2Engine.coreBundled
        case .switchCore: return OSMeloNXEngine.runtimeBundled
        }
    }
}

/// Qué hay que volver a leer después de importar.
enum ImportRescan: Hashable {
    case retro, armsx2, melonx, skins, keys, firmware
}

/// Qué se hace con un archivo.
enum ImportAction {
    /// Copiar el archivo (o la carpeta) dentro de `folder`, con su nombre.
    case copy(into: URL)
    /// Copiar una carpeta en `destination` (con otro nombre o fusionándola).
    case copyFolder(to: URL)
    /// Sacar un zip en `folder` (quitando `strip` delante si lo trae).
    case extractZip(to: URL, strip: String?)
    /// Zip con juegos u otras cosas: se saca y cada archivo se vuelve a mirar.
    case expandZip
    /// Claves de Switch (prod.keys / title.keys).
    case switchKeys
    /// Firmware de Switch (zip con .nca): lo instala MeloNX.
    case switchFirmware
    /// seeddb.bin de 3DS.
    case seeds3DS
    /// Skin de Delta / ManicEMU (.deltaskin, .manicskin o zip con info.json).
    case skin
    /// Trucos de RetroArch (.cht): se pasan a los trucos de OmniStation del juego que se llame igual.
    case retroCheat
    /// Una carpeta con cosas sueltas: cada archivo se mira por separado.
    case expandFolder
}

struct ImportItem: Identifiable {
    let id = UUID()
    let url: URL
    /// Lo que es y adónde va (para enseñarlo).
    var label: String
    var action: ImportAction?
    var rescan: Set<ImportRescan> = []
    /// Juego que puede ser de varias consolas: se pregunta (vacío si ya se sabe).
    var choices: [ImportTarget] = []

    var name: String { url.lastPathComponent }
}

struct ImportOutcome {
    var done: [String] = []
    var failed: [String] = []
    var rescan: Set<ImportRescan> = []
    /// Firmware de Switch para que lo instale MeloNX.
    var firmware: URL?
    /// Archivos de dentro de un zip o una carpeta que hay que mirar otra vez (ya en la carpeta temporal).
    var expanded: [URL] = []
}

enum ImportRouter {
    static let fileManager = FileManager.default

    /// Carpeta temporal de Importar (arrastrados, zips sacados): se vacía al terminar.
    static var staging: URL {
        let url: URL = fileManager.temporaryDirectory.appendingPathComponent("OmniStationImport", isDirectory: true)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func cleanStaging() {
        try? fileManager.removeItem(at: staging)
    }

    private static var documents: URL { fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    // MARK: Nombres que dicen lo que son

    private static let ps1BIOS: Set<String> = ["scph1000", "scph1001", "scph1002", "scph3000", "scph3500", "scph5000",
                                               "scph5500", "scph5501", "scph5502", "scph5503", "scph5552", "scph7000",
                                               "scph7001", "scph7002", "scph7003", "scph7502", "scph9002", "scph100",
                                               "scph101", "scph102", "scph1000r", "psxonpsp660", "ps1_rom"]

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    /// Serie de PS2 («SLUS-20312», también con _ o .).
    static func ps2Serial(_ name: String) -> String? {
        let upper: String = name.uppercased()
        guard let range = upper.range(of: "^[A-Z]{4}[-_][0-9]{3}\\.?[0-9]{2}", options: .regularExpression) else { return nil }
        let raw: String = String(upper[range]).replacingOccurrences(of: "_", with: "-").replacingOccurrences(of: ".", with: "")
        return raw
    }

    static func pspID(_ name: String) -> String? {
        let upper: String = name.uppercased()
        guard let range = upper.range(of: "^[A-Z]{4}[0-9]{5}", options: .regularExpression) else { return nil }
        return String(upper[range])
    }

    /// Id de Dolphin (6 letras/números; G/D = GameCube, R/S/W = Wii).
    static func dolphinID(_ name: String) -> (id: String, system: RetroSystem)? {
        let upper: String = name.uppercased()
        guard matches(upper, "^[A-Z0-9]{6}$"), let first = upper.first else { return nil }
        if "GD".contains(first) { return (upper, .gc) }
        if "RSWH".contains(first) { return (upper, .wii) }
        return nil
    }

    /// Title ID de 16 cifras hexadecimales: 3DS (0004…) o Switch (01…).
    static func titleID(_ name: String) -> (id: String, target: ImportTarget)? {
        let upper: String = name.uppercased()
        guard matches(upper, "^[0-9A-F]{16}$") else { return nil }
        if upper.hasPrefix("0004") { return (upper, .retro(.n3ds)) }
        if upper.hasPrefix("01") { return (upper, .switchCore) }
        return nil
    }

    // MARK: Lo que trae cada consola en su carpeta

    static var ps2Data: URL { ARMSX2CoreFolders.data }
    static var switchRoot: URL { MeloNXCoreFolders.keys.deletingLastPathComponent() }
    static func dolphinUser(_ system: RetroSystem) -> URL { RetroFolders.saves(system).appendingPathComponent("User", isDirectory: true) }
    static var azahar: URL { RetroFolders.saves(.n3ds).appendingPathComponent("Azahar", isDirectory: true) }
    static var pspMemstick: URL { RetroFolders.saves(.psp).appendingPathComponent("PSP", isDirectory: true) }

    // MARK: Clasificar

    /// Qué es este archivo o carpeta (el acceso de Archivos ya debe estar abierto).
    static func classify(_ url: URL) -> ImportItem {
        var isDirectory: ObjCBool = false
        fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return isDirectory.boolValue ? classifyFolder(url) : classifyFile(url)
    }

    private static func item(_ url: URL, _ label: String, _ action: ImportAction?, _ rescan: Set<ImportRescan> = []) -> ImportItem {
        ImportItem(url: url, label: label, action: action, rescan: rescan)
    }

    private static func gameItem(_ url: URL, _ target: ImportTarget) -> ImportItem {
        let folder: URL = target.gamesFolder
        return item(url, L10n.tr("Juego de %@ → %@", lang).replacingFirst(target.title, target.shortPath(folder)), .copy(into: folder), [target.rescan])
    }

    /// Juego ya decidido (tras preguntar de qué consola es).
    static func gameItem(for url: URL, target: ImportTarget) -> ImportItem { gameItem(url, target) }

    private static func ask(_ url: URL, _ choices: [ImportTarget]) -> ImportItem {
        let available: [ImportTarget] = choices.filter(\.available)
        if available.count == 1, let only = available.first { return gameItem(url, only) }
        var result = item(url, L10n.tr("¿De qué consola es?", lang), nil)
        result.choices = available.isEmpty ? choices : available
        return result
    }

    private static var lang: String { L10n.resolve(UserDefaults.standard.string(forKey: "appLanguage") ?? "system") }

    private static func fileSize(_ url: URL) -> UInt64 {
        ((try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    private static func readBytes(_ url: URL, at offset: UInt64, count: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: offset)
            return try handle.read(upToCount: count)
        } catch {
            return nil
        }
    }

    private static func ascii(_ data: Data?) -> String {
        guard let data else { return "" }
        return String(decoding: data.map { (32...126).contains($0) ? $0 : 32 }, as: UTF8.self)
    }

    private static func classifyFile(_ url: URL) -> ImportItem {
        let name: String = url.lastPathComponent
        let lower: String = name.lowercased()
        let ext: String = url.pathExtension.lowercased()
        let stem: String = (lower as NSString).deletingPathExtension
        let size: UInt64 = fileSize(url)

        // Claves, seeds y BIOS por su nombre.
        if ext == "keys" { return item(url, L10n.tr("Claves de Switch → MeloNX", lang), .switchKeys, [.keys]) }
        if lower == "seeddb.bin" { return item(url, L10n.tr("seeddb.bin de 3DS → 3DS/BIOS", lang), .seeds3DS) }
        if ["deltaskin", "manicskin"].contains(ext) { return item(url, L10n.tr("Skin del mando táctil → Skins", lang), .skin, [.skins]) }
        if lower == "gba_bios.bin" { return biosItem(url, .retro(.gba)) }
        if ["bios7.bin", "bios9.bin", "firmware.bin", "dsi_bios7.bin", "dsi_bios9.bin", "dsi_firmware.bin", "dsi_nand.bin"].contains(lower) { return biosItem(url, .retro(.nds)) }
        if ["dc_boot.bin", "dc_flash.bin", "dc_bios.bin", "naomi_boot.bin"].contains(lower) { return biosItem(url, .retro(.dc)) }
        if ["gb_bios.bin", "gbc_bios.bin", "sgb_bios.bin", "dmg_boot.bin", "cgb_boot.bin"].contains(lower) { return biosItem(url, .retro(.gb)) }
        if lower == "disksys.rom" { return biosItem(url, .retro(.nes)) }
        if ext == "bin" || ext == "rom" {
            // BIOS de PS2: 4 MB (también 8 MB en algunos modelos).
            if (size == 4 * 1024 * 1024 || size == 8 * 1024 * 1024) && !lower.contains("track") { return biosItem(url, .ps2) }
            if ps1BIOS.contains(stem) || (size == 512 * 1024 && (stem.hasPrefix("scph") || stem.hasPrefix("psx"))) { return biosItem(url, .retro(.ps1)) }
        }

        // Trucos, texturas sueltas, tarjetas de memoria.
        if ext == "pnach" { return item(url, L10n.tr("Trucos de PS2 → ARMSX2/Datos/cheats", lang), .copy(into: ps2Data.appendingPathComponent("cheats", isDirectory: true)), [.armsx2]) }
        if ext == "ps2" { return item(url, L10n.tr("Tarjeta de memoria de PS2 → ARMSX2", lang), .copy(into: ARMSX2CoreFolders.memoryCards), [.armsx2]) }
        if ext == "cht" { return item(url, L10n.tr("Trucos de RetroArch → trucos del juego", lang), .retroCheat) }
        if ext == "ini", let id = pspID(stem.uppercased()), stem.count == 9 {
            return item(url, L10n.tr("Trucos de PSP (%@) → PSP/Partidas/PSP/Cheats", lang).replacingFirst(id), .copy(into: pspMemstick.appendingPathComponent("Cheats", isDirectory: true)), [.retro])
        }
        if ext == "ini", let dolphin = dolphinID(stem) {
            return item(url, L10n.tr("Ajustes y trucos de Dolphin (%@) → GameSettings", lang).replacingFirst(dolphin.id), .copy(into: dolphinUser(dolphin.system).appendingPathComponent("GameSettings", isDirectory: true)), [.retro])
        }
        if ext == "txt", let tid = titleID(stem), tid.target == .retro(.n3ds) {
            return item(url, L10n.tr("Trucos de 3DS → Azahar/cheats", lang), .copy(into: azahar.appendingPathComponent("cheats", isDirectory: true)), [.retro])
        }
        if ext == "zip" { return classifyZip(url) }
        if ["7z", "rar"].contains(ext) {
            return item(url, L10n.tr("Comprimido .%@: descomprímelo antes en Archivos (mantén pulsado → Descomprimir)", lang).replacingFirst(ext), nil)
        }

        // Juegos.
        switch ext {
        case "nes", "fds", "unf", "unif": return gameItem(url, .retro(.nes))
        case "sfc", "smc", "fig", "swc", "bs": return gameItem(url, .retro(.snes))
        case "gb", "gbc", "dmg", "sgb", "cgb": return gameItem(url, .retro(.gb))
        case "gba", "agb": return gameItem(url, .retro(.gba))
        case "nds", "dsi", "ids": return gameItem(url, .retro(.nds))
        case "z64", "n64", "v64": return gameItem(url, .retro(.n64))
        case "3ds", "cci", "cxi", "3dsx", "cia": return gameItem(url, .retro(.n3ds))
        case "gdi", "cdi": return gameItem(url, .retro(.dc))
        case "gcm", "dol": return gameItem(url, .retro(.gc))
        case "wbfs", "wad": return gameItem(url, .retro(.wii))
        case "nsp", "xci", "nro", "nsz", "xcz": return gameItem(url, .switchCore)
        case "zso": return gameItem(url, .ps2)
        case "cue", "ccd", "m3u", "img", "bin": return gameItem(url, .retro(.ps1))
        case "pbp": return gameItem(url, pbpIsPS1(url) ? .retro(.ps1) : .retro(.psp))
        case "cso": return csoItem(url, size: size)
        case "iso": return isoItem(url, size: size)
        case "chd": return chdItem(url)
        case "rvz", "gcz", "ciso", "wia": return dolphinDisc(url)
        default:
            return item(url, L10n.tr("No se sabe qué es: no se ha copiado", lang), nil)
        }
    }

    private static func biosItem(_ url: URL, _ target: ImportTarget) -> ImportItem {
        let folder: URL = target.biosFolder
        return item(url, L10n.tr("BIOS de %@ → %@", lang).replacingFirst(target.title, target.shortPath(folder)), .copy(into: folder), [target.rescan])
    }

    /// EBOOT.PBP: de PS1 (PSISOIMG / PSTITLEI) o de PSP.
    private static func pbpIsPS1(_ url: URL) -> Bool {
        guard let header = readBytes(url, at: 0, count: 0x28), header.count >= 0x28, header.prefix(4) == Data([0, 0x50, 0x42, 0x50]) else { return false }
        let psar: UInt64 = header.subdata(in: 0x24..<0x28).withUnsafeBytes { UInt64($0.loadUnaligned(as: UInt32.self).littleEndian) }
        let magic: String = ascii(readBytes(url, at: psar, count: 8))
        return magic.hasPrefix("PSISOIMG") || magic.hasPrefix("PSTITLEI")
    }

    /// CSO: PSP (hasta 1,8 GB, lo que cabe en un UMD) o PS2 (más grande).
    private static func csoItem(_ url: URL, size: UInt64) -> ImportItem {
        if let header = readBytes(url, at: 0, count: 16), header.count == 16, ascii(header.prefix(4)) == "CISO" {
            let total: UInt64 = header.subdata(in: 8..<16).withUnsafeBytes { $0.loadUnaligned(as: UInt64.self).littleEndian }
            return gameItem(url, total > 1_900_000_000 ? .ps2 : .retro(.psp))
        }
        return ask(url, [.retro(.psp), .ps2])
    }

    /// ISO: lo dice su cabecera (PSP, PlayStation, GameCube o Wii).
    private static func isoItem(_ url: URL, size: UInt64) -> ImportItem {
        if let disc = readBytes(url, at: 0, count: 0x20), disc.count == 0x20 {
            if disc.subdata(in: 0x1C..<0x20) == Data([0xC2, 0x33, 0x9F, 0x3D]) { return gameItem(url, .retro(.gc)) }
            if disc.subdata(in: 0x18..<0x1C) == Data([0x5D, 0x1C, 0x9E, 0xA3]) { return gameItem(url, .retro(.wii)) }
        }
        let system: String = ascii(readBytes(url, at: 0x8008, count: 32)).trimmingCharacters(in: .whitespaces)
        if system.hasPrefix("PSP GAME") { return gameItem(url, .retro(.psp)) }
        if system.hasPrefix("PLAYSTATION") {
            // Un DVD es de PS2; un CD puede ser de PS1 o de PS2.
            return size > 900_000_000 ? gameItem(url, .ps2) : ask(url, [.retro(.ps1), .ps2])
        }
        return ask(url, [.ps2, .retro(.psp), .retro(.gc), .retro(.wii), .retro(.ps1)])
    }

    /// CHD: por sus metadatos (GD-ROM = Dreamcast, CD o DVD).
    private static func chdItem(_ url: URL) -> ImportItem {
        guard let header = readBytes(url, at: 0, count: 124), header.count >= 64, ascii(header.prefix(8)) == "MComprHD" else {
            return ask(url, [.retro(.ps1), .ps2, .retro(.dc), .retro(.psp)])
        }
        func be64(_ offset: Int) -> UInt64 { header.subdata(in: offset..<(offset + 8)).reduce(0) { ($0 << 8) | UInt64($1) } }
        func be32(_ offset: Int) -> UInt32 { header.subdata(in: offset..<(offset + 4)).reduce(0) { ($0 << 8) | UInt32($1) } }
        let version: UInt32 = be32(12)
        // v5: tamaño en 32 y metadatos en 48; v3/v4: en 28 y 36.
        let logical: UInt64 = version >= 5 ? be64(32) : (version >= 3 ? be64(28) : 0)
        var metaOffset: UInt64 = version >= 5 ? be64(48) : (version >= 3 ? be64(36) : 0)
        var tags: Set<String> = []
        var guardCount: Int = 0
        while metaOffset != 0 && guardCount < 64, let entry = readBytes(url, at: metaOffset, count: 16), entry.count == 16 {
            tags.insert(ascii(entry.prefix(4)))
            metaOffset = entry.subdata(in: 8..<16).reduce(0) { ($0 << 8) | UInt64($1) }
            guardCount += 1
        }
        if tags.contains("CHGD") { return gameItem(url, .retro(.dc)) }
        if tags.contains("DVD ") { return logical > 1_900_000_000 ? gameItem(url, .ps2) : ask(url, [.retro(.psp), .ps2]) }
        if !tags.isDisjoint(with: ["CHCD", "CHTR", "CHT2"]) { return ask(url, [.retro(.ps1), .ps2]) }
        return ask(url, [.retro(.ps1), .ps2, .retro(.dc), .retro(.psp)])
    }

    /// RVZ / WIA / GCZ / CISO: la cabecera del disco (copiada al principio en RVZ y WIA).
    private static func dolphinDisc(_ url: URL) -> ImportItem {
        let ext: String = url.pathExtension.lowercased()
        let offset: UInt64 = (ext == "rvz" || ext == "wia") ? 0x58 : 0
        if offset > 0, let disc = readBytes(url, at: offset, count: 0x20), disc.count == 0x20 {
            if disc.subdata(in: 0x1C..<0x20) == Data([0xC2, 0x33, 0x9F, 0x3D]) { return gameItem(url, .retro(.gc)) }
            if disc.subdata(in: 0x18..<0x1C) == Data([0x5D, 0x1C, 0x9E, 0xA3]) { return gameItem(url, .retro(.wii)) }
        }
        return ask(url, [.retro(.gc), .retro(.wii)])
    }

    // MARK: Zips

    private static func classifyZip(_ url: URL) -> ImportItem {
        guard let entries = OSZipArchive.entries(atPath: url.path), !entries.isEmpty else {
            return item(url, L10n.tr("Zip que no se puede leer (¿cifrado?): descomprímelo en Archivos", lang), nil)
        }
        let paths: [String] = entries.map(\.path)
        if paths.contains(where: { $0 == "info.json" || $0.hasSuffix("/info.json") && $0.components(separatedBy: "/").count == 2 }) {
            return item(url, L10n.tr("Skin del mando táctil → Skins", lang), .skin, [.skins])
        }
        if paths.contains(where: { $0.lowercased().hasSuffix(".nca") }) {
            return item(url, L10n.tr("Firmware de Switch → lo instala MeloNX", lang), .switchFirmware, [.firmware])
        }
        let images: Set<String> = ["png", "dds", "jpg", "jpeg", "bmp", "ktx"]
        let imageCount: Int = paths.filter { images.contains(($0 as NSString).pathExtension.lowercased()) }.count
        let top: String? = paths.first?.components(separatedBy: "/").first
        let sameTop: Bool = top != nil && paths.allSatisfy { $0.hasPrefix(top! + "/") }
        let packName: String = sameTop ? (top ?? "") : (url.deletingPathExtension().lastPathComponent)
        if imageCount * 2 >= paths.count, let destination = textureFolder(named: packName) {
            return item(url, L10n.tr("Texturas (%@) → %@", lang).replacingFirst(packName, ImportTarget.ps2.shortPath(destination.folder)),
                        .extractZip(to: destination.folder, strip: sameTop ? (top ?? "") + "/" : nil), [destination.rescan])
        }
        // Switch: mods con contents/<title id>/…
        if let tidPath = paths.first(where: { matches($0.uppercased(), "(^|/)CONTENTS/[0-9A-F]{16}/") }) {
            let parts: [String] = tidPath.components(separatedBy: "/")
            if let index = parts.firstIndex(where: { $0.lowercased() == "contents" }) {
                let strip: String = parts[..<index].map { $0 + "/" }.joined() + "contents/"
                return item(url, L10n.tr("Mods de Switch → mods/contents", lang), .extractZip(to: switchRoot.appendingPathComponent("mods/contents", isDirectory: true), strip: strip), [.melonx])
            }
        }
        return item(url, L10n.tr("Zip: se saca y se coloca cada archivo", lang), .expandZip)
    }

    /// Carpeta de texturas de un pack por su nombre (serie de PS2, id de PSP, Dolphin o 3DS).
    static func textureFolder(named name: String) -> (folder: URL, rescan: ImportRescan)? {
        if let serial = ps2Serial(name), serial.count == 10 {
            return (ps2Data.appendingPathComponent("textures/" + serial, isDirectory: true), .armsx2)
        }
        if let id = pspID(name), name.count == 9 {
            return (pspMemstick.appendingPathComponent("TEXTURES/" + id, isDirectory: true), .retro)
        }
        if let dolphin = dolphinID(name) {
            return (dolphinUser(dolphin.system).appendingPathComponent("Load/Textures/" + dolphin.id, isDirectory: true), .retro)
        }
        if let tid = titleID(name), tid.target == .retro(.n3ds) {
            return (azahar.appendingPathComponent("load/textures/" + tid.id, isDirectory: true), .retro)
        }
        return nil
    }

    // MARK: Carpetas

    private static func classifyFolder(_ url: URL) -> ImportItem {
        let name: String = url.lastPathComponent
        let contents: [String] = (try? fileManager.contentsOfDirectory(atPath: url.path)) ?? []
        let lowerContents: Set<String> = Set(contents.map { $0.lowercased() })
        // Partida de PSP (carpeta de SAVEDATA con su PARAM.SFO).
        if pspID(name) != nil && lowerContents.contains("param.sfo") {
            return item(url, L10n.tr("Partida de PSP → PSP/Partidas/PSP/SAVEDATA", lang), .copy(into: pspMemstick.appendingPathComponent("SAVEDATA", isDirectory: true)), [.retro])
        }
        if let tid = titleID(name) {
            if tid.target == .switchCore {
                let destination: URL = switchRoot.appendingPathComponent("mods/contents/" + tid.id, isDirectory: true)
                // romfs/exefs sueltos: el mod va en una carpeta con nombre dentro.
                if lowerContents.contains("romfs") || lowerContents.contains("exefs") {
                    return item(url, L10n.tr("Mod de Switch (%@) → mods/contents", lang).replacingFirst(tid.id), .copyFolder(to: destination.appendingPathComponent("OmniStation", isDirectory: true)), [.melonx])
                }
                return item(url, L10n.tr("Mods de Switch (%@) → mods/contents", lang).replacingFirst(tid.id), .copyFolder(to: destination), [.melonx])
            }
            if lowerContents.contains("romfs") || lowerContents.contains("exefs") || lowerContents.contains("code.ips") {
                return item(url, L10n.tr("Mod de 3DS → Azahar/load/mods", lang), .copyFolder(to: azahar.appendingPathComponent("load/mods/" + tid.id, isDirectory: true)), [.retro])
            }
        }
        if ["contents", "atmosphere"].contains(name.lowercased()) {
            let inner: URL = name.lowercased() == "atmosphere" ? url.appendingPathComponent("contents", isDirectory: true) : url
            return item(inner, L10n.tr("Mods de Switch → mods/contents", lang), .copyFolder(to: switchRoot.appendingPathComponent("mods/contents", isDirectory: true)), [.melonx])
        }
        if let destination = textureFolder(named: name) {
            return item(url, L10n.tr("Texturas (%@) → %@", lang).replacingFirst(name, ImportTarget.ps2.shortPath(destination.folder)), .copyFolder(to: destination.folder), [destination.rescan])
        }
        return item(url, L10n.tr("Carpeta: se coloca cada archivo", lang), .expandFolder)
    }

    // MARK: Hacer

    /// Copia (o mueve, si viene de la carpeta temporal) lo importado a su sitio.
    static func perform(_ item: ImportItem) -> ImportOutcome {
        var outcome = ImportOutcome()
        let url: URL = item.url
        let temporary: Bool = url.path.hasPrefix(staging.path)
        guard let action = item.action else {
            outcome.failed.append(item.name + " — " + item.label)
            return outcome
        }
        func place(_ source: URL, _ target: URL) -> Bool {
            try? fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: target.path) { try? fileManager.removeItem(at: target) }
            do {
                if temporary { try fileManager.moveItem(at: source, to: target) } else { try fileManager.copyItem(at: source, to: target) }
                return true
            } catch {
                return false
            }
        }
        var ok: Bool = true
        switch action {
        case .copy(let folder):
            ok = place(url, folder.appendingPathComponent(url.lastPathComponent))
        case .copyFolder(let destination):
            // Se fusiona: cada cosa de dentro va a su sitio (lo que ya hubiera se queda).
            try? fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            let children: [String] = (try? fileManager.contentsOfDirectory(atPath: url.path)) ?? []
            for child in children where !child.hasPrefix(".") {
                if !place(url.appendingPathComponent(child), destination.appendingPathComponent(child)) { ok = false }
            }
        case .extractZip(let folder, let strip):
            ok = OSZipArchive.extractAll(fromPath: url.path, toFolder: folder.path, stripPrefix: strip) > 0
        case .expandZip:
            let folder: URL = staging.appendingPathComponent(UUID().uuidString, isDirectory: true)
            if OSZipArchive.extractAll(fromPath: url.path, toFolder: folder.path, stripPrefix: nil) > 0 {
                outcome.expanded = expandedFiles(in: folder)
                return outcome
            }
            ok = false
        case .expandFolder:
            outcome.expanded = expandedFiles(in: url)
            return outcome
        case .switchKeys:
            ok = MeloNXCoreFolders.importKeys([url]) > 0
        case .seeds3DS:
            ok = RetroFolders.import3DSSeeds([url])
        case .skin:
            var error: NSString? = nil
            ok = OSDeltaSkin.importArchive(at: url, error: &error) != nil
        case .switchFirmware:
            outcome.firmware = url
        case .retroCheat:
            ok = importRetroCheat(url)
        }
        if ok {
            outcome.done.append(item.name + " — " + item.label)
            outcome.rescan = item.rescan
        } else {
            outcome.failed.append(item.name + " — " + L10n.tr("no se pudo copiar", lang))
        }
        return outcome
    }

    /// Lo hecho de una vez y lo que queda por preguntar (de qué consola es un juego).
    struct Batch {
        var outcome = ImportOutcome()
        var pending: [ImportItem] = []
    }

    /// Mira y coloca todo (fuera del hilo principal). `decided`: juegos ya contestados.
    static func run(_ urls: [URL], decided: [(url: URL, target: ImportTarget)] = []) -> Batch {
        var batch = Batch()
        var queue: [URL] = urls
        func merge(_ outcome: ImportOutcome) {
            batch.outcome.done += outcome.done
            batch.outcome.failed += outcome.failed
            batch.outcome.rescan.formUnion(outcome.rescan)
            if let firmware = outcome.firmware { batch.outcome.firmware = firmware }
            queue += outcome.expanded
        }
        for answer in decided {
            let accessing: Bool = answer.url.startAccessingSecurityScopedResource()
            merge(perform(gameItem(for: answer.url, target: answer.target)))
            if accessing { answer.url.stopAccessingSecurityScopedResource() }
        }
        var guardCount: Int = 0
        while !queue.isEmpty && guardCount < 20000 {
            guardCount += 1
            let url: URL = queue.removeFirst()
            let accessing: Bool = url.startAccessingSecurityScopedResource()
            let found: ImportItem = classify(url)
            if !found.choices.isEmpty {
                // Se pregunta luego: se copia ya a la carpeta temporal (después no habría acceso a la
                // carpeta de Archivos de donde viene; desde ahí se mueve, así que no se copia dos veces).
                if url.path.hasPrefix(staging.path) {
                    batch.pending.append(found)
                } else {
                    let copy: URL = staging.appendingPathComponent(UUID().uuidString, isDirectory: true).appendingPathComponent(url.lastPathComponent)
                    try? fileManager.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if (try? fileManager.copyItem(at: url, to: copy)) != nil {
                        var moved: ImportItem = ImportItem(url: copy, label: found.label, action: found.action, rescan: found.rescan)
                        moved.choices = found.choices
                        batch.pending.append(moved)
                    } else {
                        batch.outcome.failed.append(found.name)
                    }
                }
            } else if case .switchFirmware? = found.action, !url.path.hasPrefix(staging.path) {
                // El firmware lo instala MeloNX luego: se copia antes de perder el acceso.
                let copy: URL = staging.appendingPathComponent(UUID().uuidString, isDirectory: true).appendingPathComponent(url.lastPathComponent)
                try? fileManager.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
                if (try? fileManager.copyItem(at: url, to: copy)) != nil {
                    batch.outcome.firmware = copy
                    batch.outcome.done.append(found.name + " — " + found.label)
                } else {
                    batch.outcome.failed.append(found.name)
                }
            } else {
                merge(perform(found))
            }
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        return batch
    }

    /// Lo de dentro de una carpeta (sin entrar en las que ya dicen lo que son, como un pack de texturas).
    private static func expandedFiles(in folder: URL, depth: Int = 0) -> [URL] {
        let children: [String] = ((try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []).filter { !$0.hasPrefix(".") && $0 != "__MACOSX" }
        var result: [URL] = []
        for child in children.prefix(4000) {
            let url: URL = folder.appendingPathComponent(child)
            var isDirectory: ObjCBool = false
            fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            if isDirectory.boolValue && depth < 4, case .expandFolder? = classifyFolder(url).action {
                result += expandedFiles(in: url, depth: depth + 1)
            } else {
                result.append(url)
            }
        }
        return result
    }

    // MARK: Trucos de RetroArch (.cht)

    /// cheatN_desc / cheatN_code / cheatN_enable → «<juego>.cheats.json» del juego que se llame igual.
    private static func importRetroCheat(_ url: URL) -> Bool {
        guard let text = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1)) else { return false }
        var values: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            let parts: [String] = line.components(separatedBy: "=")
            guard parts.count >= 2 else { continue }
            let key: String = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            var value: String = parts.dropFirst().joined(separator: "=").trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 { value = String(value.dropFirst().dropLast()) }
            values[key] = value
        }
        let count: Int = Int(values["cheats"] ?? "") ?? 0
        var cheats: [[String: Any]] = []
        for index in 0..<count {
            guard let code = values["cheat\(index)_code"], !code.isEmpty else { continue }
            cheats.append(["name": values["cheat\(index)_desc"] ?? code, "code": code, "enabled": values["cheat\(index)_enable"] == "true"])
        }
        guard !cheats.isEmpty else { return false }
        let wanted: String = normalized(url.deletingPathExtension().lastPathComponent)
        for system in RetroSystem.allCases {
            let folder: URL = RetroFolders.games(system)
            let names: [String] = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
            guard let match = names.first(where: { normalized(($0 as NSString).deletingPathExtension) == wanted }) else { continue }
            let target: URL = RetroFolders.saves(system).appendingPathComponent((match as NSString).deletingPathExtension + ".cheats.json")
            var existing: [[String: Any]] = []
            if let data = try? Data(contentsOf: target), let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] { existing = list }
            let known: Set<String> = Set(existing.compactMap { $0["code"] as? String })
            existing += cheats.filter { !known.contains($0["code"] as? String ?? "") }
            try? fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard let data = try? JSONSerialization.data(withJSONObject: existing, options: .prettyPrinted) else { return false }
            return (try? data.write(to: target)) != nil
        }
        return false
    }

    private static func normalized(_ name: String) -> String {
        name.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .replacingOccurrences(of: "[^a-z0-9]+", with: "", options: .regularExpression)
    }
}

// MARK: - Exportar

/// Lo que se puede exportar (se comprime en un zip y se guarda donde elijas).
enum ExportKind: String, CaseIterable, Identifiable {
    case saves, bios, extras, backup
    var id: String { rawValue }
}

/// Origen de lo exportado.
struct ExportSource: Identifiable, Hashable {
    let id: String
    let title: String
    let folders: [URL]
}

enum ExportBuilder {
    private static let fileManager = FileManager.default
    private static var documents: URL { fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    private static func exists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return false }
        if !isDirectory.boolValue { return true }
        return !((try? fileManager.contentsOfDirectory(atPath: url.path)) ?? []).filter { !$0.hasPrefix(".") }.isEmpty
    }

    /// De dónde se puede sacar cada cosa (solo lo que tiene algo dentro).
    static func sources(for kind: ExportKind) -> [ExportSource] {
        var list: [ExportSource] = []
        func add(_ id: String, _ title: String, _ folders: [URL]) {
            let present: [URL] = folders.filter(exists)
            if !present.isEmpty { list.append(ExportSource(id: id, title: title, folders: present)) }
        }
        switch kind {
        case .saves:
            add("ps2", "PlayStation 2", [ARMSX2CoreFolders.data.appendingPathComponent("Saves", isDirectory: true)])
            add("switch", "Nintendo Switch", [ImportRouter.switchRoot.appendingPathComponent("bis/user/save", isDirectory: true)])
            for system in RetroSystem.allCases { add("retro." + system.rawValue, system.title, [RetroFolders.saves(system)]) }
        case .bios:
            add("ps2", "PlayStation 2", [ARMSX2CoreFolders.bios])
            add("switch", "Nintendo Switch", [MeloNXCoreFolders.keys])
            for system in RetroSystem.allCases { add("retro." + system.rawValue, system.title, [RetroFolders.bios(system)]) }
        case .extras:
            add("ps2", "PlayStation 2", ["cheats", "patches", "textures"].map { ARMSX2CoreFolders.data.appendingPathComponent($0, isDirectory: true) })
            add("switch", "Nintendo Switch", [ImportRouter.switchRoot.appendingPathComponent("mods", isDirectory: true)])
            add("skins", "Skins", [documents.appendingPathComponent("Skins", isDirectory: true)])
            add("psp", "PSP", ["TEXTURES", "Cheats"].map { ImportRouter.pspMemstick.appendingPathComponent($0, isDirectory: true) })
            add("dolphin", "GameCube / Wii", [RetroSystem.gc, .wii].flatMap { system in
                ["Load/Textures", "GameSettings"].map { ImportRouter.dolphinUser(system).appendingPathComponent($0, isDirectory: true) }
            })
            add("3ds", "Nintendo 3DS", ["load", "cheats"].map { ImportRouter.azahar.appendingPathComponent($0, isDirectory: true) })
        case .backup:
            add("all", "OmniStation Dock", [documents])
        }
        if list.count > 1 && kind != .backup {
            list.insert(ExportSource(id: "all", title: "", folders: list.flatMap(\.folders)), at: 0)
        }
        return list
    }

    /// Hace el zip (en la carpeta temporal). Las carpetas van con su ruta desde Documentos.
    static func makeZip(named name: String, folders: [URL]) -> URL? {
        let stage: URL = fileManager.temporaryDirectory.appendingPathComponent("OmniStationExport", isDirectory: true)
        try? fileManager.removeItem(at: stage)
        let root: URL = stage.appendingPathComponent(name, isDirectory: true)
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let documentsPath: String = documents.path
        let folderList: [URL] = folders.count == 1 && folders[0].path == documentsPath ? [] : folders
        if folderList.isEmpty {
            // Copia de seguridad: todo Documentos (sin los juegos, que pesan mucho y ya los tienes).
            for child in ((try? fileManager.contentsOfDirectory(atPath: documentsPath)) ?? []) where !child.hasPrefix(".") {
                copyWithoutGames(documents.appendingPathComponent(child), to: root.appendingPathComponent(child))
            }
        } else {
            for folder in folderList {
                let relative: String = folder.path.hasPrefix(documentsPath) ? String(folder.path.dropFirst(documentsPath.count + 1)) : folder.lastPathComponent
                let target: URL = root.appendingPathComponent(relative)
                try? fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fileManager.copyItem(at: folder, to: target)
            }
        }
        var zipURL: URL? = nil
        var coordinatorError: NSError? = nil
        NSFileCoordinator().coordinate(readingItemAt: root, options: .forUploading, error: &coordinatorError) { zipped in
            let destination: URL = stage.appendingPathComponent(name + ".zip")
            try? fileManager.removeItem(at: destination)
            if (try? fileManager.copyItem(at: zipped, to: destination)) != nil { zipURL = destination }
        }
        try? fileManager.removeItem(at: root)
        return zipURL
    }

    private static func copyWithoutGames(_ source: URL, to target: URL) {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory) else { return }
        if !isDirectory.boolValue {
            try? fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fileManager.copyItem(at: source, to: target)
            return
        }
        if source.lastPathComponent == "Juegos" { return }
        try? fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        for child in ((try? fileManager.contentsOfDirectory(atPath: source.path)) ?? []) where !child.hasPrefix(".") {
            copyWithoutGames(source.appendingPathComponent(child), to: target.appendingPathComponent(child))
        }
    }
}

private extension String {
    /// Rellena los %@ de una traducción en orden.
    func replacingFirst(_ values: String...) -> String {
        var text: String = self
        for value in values {
            guard let range = text.range(of: "%@") else { break }
            text.replaceSubrange(range, with: value)
        }
        return text
    }
}
