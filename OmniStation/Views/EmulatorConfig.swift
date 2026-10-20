import Foundation

// MARK: - Ajustes de emulación de los núcleos integrados
//
// Cada emulador tiene sus ajustes generales (Ajustes → su sección) y, encima, los de cada juego
// (Opciones del juego → Configuración del emulador), como en el «Per-Game» de ARMSX2 y MeloNX.
// Solo están los que tocan la emulación: nada de apariencia ni de la interfaz de cada app.
//
// Se guardan como texto en UserDefaults. Al jugar:
// • ARMSX2: se escriben en ARMSX2/Datos/inis/PCSX2.ini (el núcleo lo lee al prepararse).
// • MeloNX: van a OSMeloNXEngine, que rellena las opciones de main_ryujinx_sdl.

struct EmuChoice: Hashable {
    let value: String
    let label: String
}

enum EmuTab: String, CaseIterable, Identifiable {
    case graphics, input, misc, system, audio, hud, advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .graphics: return "Gráficos"
        case .input: return "Mando"
        case .misc: return "Varios"
        case .system: return "Sistema"
        case .audio: return "Sonido"
        case .hud: return "HUD"
        case .advanced: return "Avanzado"
        }
    }

    var symbol: String {
        switch self {
        case .graphics: return "sparkles.tv"
        case .input: return "gamecontroller.fill"
        case .misc: return "square.grid.2x2.fill"
        case .system: return "cpu"
        case .audio: return "speaker.wave.2.fill"
        case .hud: return "speedometer"
        case .advanced: return "wrench.and.screwdriver.fill"
        }
    }
}

struct EmuOption: Identifiable {
    let id: String
    let tab: EmuTab
    let title: String
    let detail: String
    let choices: [EmuChoice]
    let defaultValue: String
    /// ARMSX2: sección y clave de PCSX2.ini (nil: no va al INI).
    var section: String? = nil
    var key: String? = nil
    /// Grupo dentro de la pestaña (como las secciones de los ajustes de MeloNX).
    var group: String = ""

    func grouped(_ name: String) -> EmuOption {
        var copy: EmuOption = self
        copy.group = name
        return copy
    }

    var isToggle: Bool {
        choices.count == 2 && choices[0].value == "true" && choices[1].value == "false"
    }

    func label(for value: String) -> String {
        choices.first(where: { $0.value == value })?.label ?? value
    }
}

enum EmulatorConfig {
    // MARK: Definiciones

    private static let yesNo: [EmuChoice] = [EmuChoice(value: "true", label: "Sí"), EmuChoice(value: "false", label: "No")]

    private static func toggle(_ id: String, _ tab: EmuTab, _ title: String, _ detail: String, _ value: Bool,
                               ini: (String, String)? = nil) -> EmuOption {
        EmuOption(id: id, tab: tab, title: title, detail: detail, choices: yesNo, defaultValue: value ? "true" : "false",
                  section: ini?.0, key: ini?.1)
    }

    private static func pick(_ id: String, _ tab: EmuTab, _ title: String, _ detail: String,
                             _ choices: [(String, String)], _ value: String, ini: (String, String)? = nil) -> EmuOption {
        EmuOption(id: id, tab: tab, title: title, detail: detail,
                  choices: choices.map { EmuChoice(value: $0.0, label: $0.1) }, defaultValue: value,
                  section: ini?.0, key: ini?.1)
    }

    /// ARMSX2 (PCSX2): claves de PCSX2.ini con los valores por defecto de ARMSX2 iOS 2.6.
    static let armsx2: [EmuOption] = {
        let gs = "EmuCore/GS"
        let hacks = "EmuCore/Speedhacks"
        return [
            EmulatorConfig.pick("upscale_multiplier", .graphics, "Resolución interna", "Más resolución se ve mejor y gasta más. Nativa es la de la PS2.",
                 [("1", "Nativa (PS2)"), ("2", "2x (720p)"), ("3", "3x (1080p)"), ("4", "4x (1440p)")], "1", ini: (gs, "upscale_multiplier")),
            EmulatorConfig.pick("AspectRatio", .graphics, "Relación de aspecto", "Automático usa la del juego (4:3 casi siempre).",
                 [("Auto 4:3/3:2", "Automático"), ("4:3", "4:3"), ("16:9", "16:9"), ("10:7", "10:7"), ("Stretch", "Estirar")], "Auto 4:3/3:2", ini: (gs, "AspectRatio")),
            EmulatorConfig.pick("filter", .graphics, "Filtro de texturas", "Bilineal (PS2) es lo normal.",
                 [("2", "Bilineal (PS2)"), ("1", "Bilineal forzado"), ("3", "Bilineal sin sprites"), ("0", "Más cercano")], "2", ini: (gs, "filter")),
            EmulatorConfig.pick("TriFilter", .graphics, "Filtro trilineal", "",
                 [("-1", "Automático"), ("0", "No"), ("1", "Trilineal (PS2)"), ("2", "Trilineal forzado")], "-1", ini: (gs, "TriFilter")),
            EmulatorConfig.pick("MaxAnisotropy", .graphics, "Filtro anisótropo", "Texturas más nítidas en ángulo.",
                 [("0", "No"), ("2", "2x"), ("4", "4x"), ("8", "8x"), ("16", "16x")], "0", ini: (gs, "MaxAnisotropy")),
            EmulatorConfig.pick("accurate_blending_unit", .graphics, "Precisión de la mezcla", "Más precisión arregla efectos y gasta más GPU.",
                 [("0", "Mínima"), ("1", "Básica"), ("2", "Media"), ("3", "Alta"), ("4", "Completa"), ("5", "Máxima")], "1", ini: (gs, "accurate_blending_unit")),
            EmulatorConfig.pick("dithering_ps2", .graphics, "Tramado (dithering)", "",
                 [("2", "Sin escalar"), ("1", "Escalado"), ("0", "No")], "2", ini: (gs, "dithering_ps2")),
            EmulatorConfig.pick("texture_preloading", .graphics, "Precarga de texturas", "Completa va más fluido en casi todos los juegos.",
                 [("2", "Completa"), ("1", "Parcial"), ("0", "No")], "2", ini: (gs, "texture_preloading")),
            EmulatorConfig.toggle("hw_mipmap", .graphics, "Mipmapping por hardware", "", true, ini: (gs, "hw_mipmap")),
            EmulatorConfig.pick("deinterlace_mode", .graphics, "Desentrelazado", "",
                 [("0", "Automático"), ("1", "No"), ("8", "Adaptativo"), ("4", "Bob"), ("6", "Mezcla")], "0", ini: (gs, "deinterlace_mode")),
            EmulatorConfig.pick("HWDownloadMode", .graphics, "Lecturas de la GPU", "«Sin lecturas» acelera algunos juegos pero puede romper efectos.",
                 [("0", "Precisas"), ("2", "Sin lecturas"), ("3", "Sin sincronizar"), ("4", "Desactivadas")], "0", ini: (gs, "HWDownloadMode")),
            EmulatorConfig.toggle("SkipDuplicateFrames", .graphics, "Saltar fotogramas repetidos", "Ahorra GPU cuando el juego repite imagen.", true, ini: (gs, "SkipDuplicateFrames")),
            EmulatorConfig.toggle("fxaa", .graphics, "FXAA", "Suaviza los bordes.", false, ini: (gs, "fxaa")),
            EmulatorConfig.pick("CASMode", .graphics, "Nitidez (CAS)", "",
                 [("0", "No"), ("1", "Solo nitidez"), ("2", "Nitidez y escalado")], "0", ini: (gs, "CASMode")),
            EmulatorConfig.toggle("LoadTextureReplacements", .graphics, "Texturas personalizadas", "Carga los packs de ARMSX2/Datos/textures.", false, ini: (gs, "LoadTextureReplacements")),
            EmulatorConfig.toggle("UserHacks", .graphics, "Correcciones manuales", "Deja aplicar las correcciones de abajo.", true, ini: (gs, "UserHacks")),
            EmulatorConfig.pick("UserHacks_HalfPixelOffset", .graphics, "Desplazamiento de medio píxel", "Corrige líneas y bordes borrosos al subir la resolución.",
                 [("0", "No"), ("1", "Normal"), ("2", "Especial"), ("3", "Especial (agresivo)"), ("4", "Alinear a nativo")], "0", ini: (gs, "UserHacks_HalfPixelOffset")),
            EmulatorConfig.pick("UserHacks_round_sprite_offset", .graphics, "Redondear sprites", "",
                 [("0", "No"), ("1", "Mitad"), ("2", "Completo")], "0", ini: (gs, "UserHacks_round_sprite_offset")),
            EmulatorConfig.pick("UserHacks_native_scaling", .graphics, "Escalado nativo", "Arregla efectos que se ven mal al subir la resolución.",
                 [("0", "No"), ("1", "Normal"), ("2", "Agresivo")], "0", ini: (gs, "UserHacks_native_scaling")),
            EmulatorConfig.toggle("UserHacks_CPU_FB_Conversion", .graphics, "Conversión del framebuffer en CPU", "", false, ini: (gs, "UserHacks_CPU_FB_Conversion")),
            EmulatorConfig.toggle("preload_frame_with_gs_data", .graphics, "Precargar datos del fotograma", "", false, ini: (gs, "preload_frame_with_gs_data")),
            EmulatorConfig.toggle("paltex", .graphics, "Conversión de paletas en GPU", "", false, ini: (gs, "paltex")),

            EmulatorConfig.pick("EECycleRate", .system, "Velocidad del EE", "Bajarla acelera juegos pesados; subirla quita tirones en algunos.",
                 [("-3", "50 %"), ("-2", "60 %"), ("-1", "75 %"), ("0", "Normal (100 %)"), ("1", "130 %"), ("2", "180 %"), ("3", "300 %")], "0", ini: (hacks, "EECycleRate")),
            EmulatorConfig.pick("EECycleSkip", .system, "Saltar ciclos del EE", "Acelera, pero puede dar fallos.",
                 [("0", "No"), ("1", "Suave"), ("2", "Moderado"), ("3", "Máximo")], "0", ini: (hacks, "EECycleSkip")),
            EmulatorConfig.toggle("vuThread", .system, "VU1 en otro hilo (MTVU)", "Mucho más rápido en casi todos los juegos.", true, ini: (hacks, "vuThread")),
            EmulatorConfig.toggle("vu1Instant", .system, "VU1 instantáneo", "", true, ini: (hacks, "vu1Instant")),
            EmulatorConfig.toggle("vuFlagHack", .system, "Atajo de banderas del VU", "", true, ini: (hacks, "vuFlagHack")),
            EmulatorConfig.toggle("IntcStat", .system, "Detección de esperas (INTC)", "", true, ini: (hacks, "IntcStat")),
            EmulatorConfig.toggle("WaitLoop", .system, "Detección de bucles de espera", "", true, ini: (hacks, "WaitLoop")),
            EmulatorConfig.toggle("fastCDVD", .system, "Lectura rápida del disco", "Carga antes; algún juego no la soporta.", false, ini: (hacks, "fastCDVD")),
            EmulatorConfig.toggle("EnableFastBoot", .system, "Arranque rápido", "Salta la animación de la BIOS.", true, ini: ("EmuCore", "EnableFastBoot")),
            EmulatorConfig.toggle("EnableGameFixes", .system, "Correcciones de cada juego", "Las de la base de datos de PCSX2.", true, ini: ("EmuCore", "EnableGameFixes")),
            EmulatorConfig.toggle("EnablePatches", .system, "Parches", "", true, ini: ("EmuCore", "EnablePatches")),
            EmulatorConfig.toggle("EnableCheats", .system, "Trucos", "Los de ARMSX2/Datos/cheats.", false, ini: ("EmuCore", "EnableCheats")),

            EmulatorConfig.pick("StandardVolume", .audio, "Volumen", "",
                 [("100", "100 %"), ("75", "75 %"), ("50", "50 %"), ("25", "25 %"), ("0", "Silencio")], "100", ini: ("SPU2/Output", "StandardVolume")),

            EmulatorConfig.toggle("OsdShowFPS", .hud, "FPS", "HUD propio de ARMSX2, arriba a la derecha.", false, ini: (gs, "OsdShowFPS")),
            EmulatorConfig.toggle("OsdShowSpeed", .hud, "Velocidad", "", false, ini: (gs, "OsdShowSpeed")),
            EmulatorConfig.toggle("OsdShowFrameTimes", .hud, "Tiempos de fotograma", "", false, ini: (gs, "OsdShowFrameTimes")),
            EmulatorConfig.toggle("OsdShowCPU", .hud, "Uso de CPU", "", false, ini: (gs, "OsdShowCPU")),
            EmulatorConfig.toggle("OsdShowGPU", .hud, "Uso de GPU", "", false, ini: (gs, "OsdShowGPU")),
            EmulatorConfig.toggle("OsdShowResolution", .hud, "Resolución", "", false, ini: (gs, "OsdShowResolution")),
            EmulatorConfig.toggle("hudSystem", .hud, "Temperatura y RAM", "Recuadro de OmniStation, arriba a la izquierda.", false),
            EmulatorConfig.toggle("hudBattery", .hud, "Batería", "En el recuadro de OmniStation.", false)
        ]
    }()

    /// MeloNX 2.7: sus ajustes de emulación con las mismas pestañas y grupos que la app MeloNX
    /// (Graphics, Input, Misc, System y Advanced), sin los de su interfaz.
    static let melonx: [EmuOption] = {
        let resolution = "Resolución"
        let filtering = "Filtrado"
        let scaling = "Opciones de escalado"
        let display = "Pantalla"
        let overlay = "Indicador de rendimiento"
        let aspect = "Relación de aspecto"
        let controller = "Mando"
        let network = "Red"
        let interface = "Interfaz"
        let sound = "Sonido"
        let language = "Idioma y región"
        let cpu = "Configuración de la CPU"
        let logs = "Registros de depuración"
        let behaviour = "Comportamiento"
        let memory = "Memoria"
        return [
            EmulatorConfig.pick("resScale", .graphics, "Resolución interna", "Por encima de 1x se ve mejor y gasta más. Algunos juegos fallan por debajo de 1x.",
                 [("0.5", "0,5x"), ("0.75", "0,75x"), ("1", "1x (nativa)"), ("1.5", "1,5x"), ("2", "2x"), ("3", "3x")], "1").grouped(resolution),
            EmulatorConfig.pick("maxAnisotropy", .graphics, "Filtro anisótropo", "Automático deja decidir al juego.",
                 [("-1", "Automático"), ("2", "2x"), ("4", "4x"), ("8", "8x"), ("16", "16x")], "-1").grouped(filtering),
            EmulatorConfig.pick("antiAliasing", .graphics, "Antialiasing", "",
                 [("0", "No"), ("1", "FXAA"), ("2", "SMAA bajo"), ("3", "SMAA medio"), ("4", "SMAA alto")], "0").grouped(scaling),
            EmulatorConfig.pick("scalingFilter", .graphics, "Filtro de escalado", "MetalFX y FSR suben la imagen con más nitidez.",
                 [("0", "Bilineal"), ("1", "Más cercano"), ("2", "FSR"), ("3", "Área"), ("4", "MetalFX")], "0").grouped(scaling),
            EmulatorConfig.pick("scalingFilterLevel", .graphics, "Nitidez de FSR", "Solo con el filtro FSR.",
                 [("40", "40 %"), ("60", "60 %"), ("80", "80 %"), ("100", "100 %")], "60").grouped(scaling),
            EmulatorConfig.pick("metalFxUpscaleFactor", .graphics, "Escala de MetalFX", "Solo con el filtro MetalFX.",
                 [("1.5", "1,5x"), ("2", "2x"), ("3", "3x")], "2").grouped(scaling),
            EmulatorConfig.toggle("shaderCache", .graphics, "Caché de shaders", "Guarda los shaders y los carga al abrir el juego. Si dudas, apagado.", false).grouped(display),
            EmulatorConfig.toggle("textureRecompression", .graphics, "Recompresión de texturas", "Gasta mucha menos memoria. Si dudas, encendido.", true).grouped(display),
            EmulatorConfig.pick("vsyncMode", .graphics, "Sincronización (VSync)", "Ilimitado quita el límite de 60 FPS (los juegos pueden ir acelerados).",
                 [("0", "Switch (60 FPS)"), ("1", "Ilimitado")], "0").grouped(display),
            EmulatorConfig.toggle("docked", .graphics, "Modo dock (TV)", "Más resolución; si no, modo portátil.", false).grouped(display),
            EmulatorConfig.toggle("macroHLE", .graphics, "Macro HLE", "Más rápido; algún juego puede verse mal.", true).grouped(display),
            EmulatorConfig.toggle("asyncShaders", .graphics, "Shaders en segundo plano (experimental)", "Menos tirones; puede romper gráficos o cerrar algún juego.", false).grouped(display),
            EmulatorConfig.toggle("memoryBudget", .graphics, "Límite de memoria de la GPU", "Apágalo si un juego se ve en blanco o pierde geometría.", true).grouped(display),
            EmulatorConfig.toggle("hud", .graphics, "Indicador de rendimiento", "FPS y el resto encima del juego.", false).grouped(overlay),
            EmulatorConfig.toggle("hudBattery", .graphics, "Batería", "", false).grouped(overlay),
            EmulatorConfig.toggle("hudFrameTime", .graphics, "Tiempo de fotograma", "", true).grouped(overlay),
            EmulatorConfig.toggle("hudMemory", .graphics, "RAM usada y libre", "", true).grouped(overlay),
            EmulatorConfig.toggle("hudFifo", .graphics, "FIFO", "", false).grouped(overlay),
            EmulatorConfig.toggle("hudThermal", .graphics, "Temperatura", "Estado térmico de iOS (normal, templado, caliente, crítico).", true).grouped(overlay),
            EmulatorConfig.pick("hudPosition", .graphics, "Posición", "",
                 [("topLeft", "Arriba a la izquierda"), ("topCenter", "Arriba en el centro"), ("topRight", "Arriba a la derecha"),
                  ("bottomLeft", "Abajo a la izquierda"), ("bottomCenter", "Abajo en el centro"), ("bottomRight", "Abajo a la derecha")], "topRight").grouped(overlay),
            EmulatorConfig.pick("aspectRatio", .graphics, "Relación de aspecto", "",
                 [("1", "16:9"), ("0", "4:3"), ("2", "16:10"), ("3", "21:9"), ("4", "32:9"), ("5", "Estirar")], "1").grouped(aspect),

            EmulatorConfig.pick("controllerType", .input, "Tipo de mando", "Cómo ve el juego al jugador 1. Algunos juegos piden Joy-Con o portátil.",
                 [("pro", "Mando Pro"), ("handheld", "Portátil"), ("joyconPair", "Pareja de Joy-Con")], "pro").grouped(controller),

            EmulatorConfig.pick("networkInterface", .misc, "Interfaz de red", "La red por la que juega en LAN.",
                 [("auto", "Automática"), ("en0", "Wi‑Fi (en0)"), ("bridge100", "Compartir internet (bridge100)")], "auto").grouped(network),
            EmulatorConfig.toggle("internet", .misc, "Internet del juego / modo LAN", "Deja al juego conectarse y jugar en LAN con otros dispositivos de la misma red. Nunca se conecta a Nintendo. Puede cerrar algún juego.", false).grouped(network),
            EmulatorConfig.toggle("ldnMitm", .misc, "ldn_mitm", "Convierte el modo local inalámbrico en LAN para jugar con otros Ryujinx o consolas con ldn_mitm. Todos con la misma versión del juego.", false).grouped(network),
            EmulatorConfig.toggle("disableTouch", .misc, "Desactivar la pantalla táctil", "El juego no recibe toques en la pantalla (el mando táctil sigue).", false).grouped(interface),
            EmulatorConfig.pick("audioVolume", .misc, "Volumen", "",
                 [("1", "100 %"), ("0.75", "75 %"), ("0.5", "50 %"), ("0.25", "25 %"), ("0", "Silencio")], "1").grouped(sound),

            EmulatorConfig.pick("systemLanguage", .system, "Idioma de la consola", "",
                 [("auto", "Según OmniStation"), ("5", "Español"), ("14", "Español (Latinoamérica)"), ("1", "Inglés (EE. UU.)"),
                  ("12", "Inglés (Reino Unido)"), ("2", "Francés"), ("3", "Alemán"), ("4", "Italiano"), ("9", "Portugués"),
                  ("17", "Portugués (Brasil)"), ("0", "Japonés"), ("7", "Coreano"), ("15", "Chino simplificado"),
                  ("16", "Chino tradicional"), ("10", "Ruso"), ("8", "Neerlandés"), ("18", "Polaco")], "auto").grouped(language),
            EmulatorConfig.pick("systemRegion", .system, "Región", "",
                 [("auto", "Según OmniStation"), ("2", "Europa"), ("1", "EE. UU."), ("0", "Japón"), ("3", "Australia"),
                  ("5", "Corea"), ("4", "China"), ("6", "Taiwán")], "auto").grouped(language),
            EmulatorConfig.pick("memoryManager", .system, "Gestor de memoria", "«Host sin comprobar» es el más rápido.",
                 [("2", "Host sin comprobar"), ("1", "Host"), ("0", "Software (lento)")], "2").grouped(cpu),
            EmulatorConfig.toggle("pptc", .system, "Caché de traducción (PPTC)", "Los juegos cargan mucho antes la segunda vez.", true).grouped(cpu),

            EmulatorConfig.toggle("debugLogs", .advanced, "Registros de depuración", "Solo si te lo piden para un fallo: gasta rendimiento.", false).grouped(logs),
            EmulatorConfig.toggle("traceLogs", .advanced, "Registros de traza", "No afecta al rendimiento.", false).grouped(logs),
            EmulatorConfig.toggle("fsIntegrity", .advanced, "Comprobar los archivos", "Busca archivos dañados al arrancar.", true).grouped(behaviour),
            EmulatorConfig.toggle("expandRAM", .advanced, "Ampliar la RAM de la consola", "8 GB como una Switch de desarrollo. Solo para packs de texturas HD o mods 4K; no da más rendimiento.", false).grouped(memory),
            EmulatorConfig.toggle("ignoreMissingServices", .advanced, "Ignorar servicios que faltan", "Puede evitar que se cierren algunos juegos.", false).grouped(memory),
            EmulatorConfig.toggle("donateGuestMemory", .advanced, "Donar la RAM de la consola", "Guarda la RAM de la Switch en procesos de ayuda, que cuentan aparte del límite de OmniStation. Si iOS los cierra por falta de memoria, se cierra el juego.", true).grouped(memory),
            EmulatorConfig.toggle("donateGpuBuffers", .advanced, "Donar búferes de la GPU", "Reserva hasta 512 MB en los procesos de ayuda para búferes de la GPU. Experimental.", false).grouped(memory),
            EmulatorConfig.toggle("killDonorsAfterMapping", .advanced, "Cerrar los ayudantes al mapear", "Cierra los procesos de ayuda en cuanto su memoria está mapeada y sigue con ella. Si dudas, encendido.", true).grouped(memory)
        ]
    }()

    static func options(_ emulator: Emulator) -> [EmuOption] {
        emulator == .melonx ? melonx : armsx2
    }

    static func tabs(_ emulator: Emulator) -> [EmuTab] {
        let used: Set<EmuTab> = Set(options(emulator).map(\.tab))
        return EmuTab.allCases.filter { used.contains($0) }
    }

    // MARK: Guardado

    private static func globalKey(_ emulator: Emulator) -> String {
        "emuConfig." + emulator.rawValue
    }

    private static func gameKey(_ emulator: Emulator, _ gameID: String) -> String {
        "emuConfig." + emulator.rawValue + ".game." + gameID
    }

    static func global(_ emulator: Emulator) -> [String: String] {
        (UserDefaults.standard.dictionary(forKey: globalKey(emulator)) as? [String: String]) ?? [:]
    }

    static func game(_ emulator: Emulator, _ gameID: String) -> [String: String] {
        (UserDefaults.standard.dictionary(forKey: gameKey(emulator, gameID)) as? [String: String]) ?? [:]
    }

    /// Cambia un ajuste general (nil: vuelve al valor por defecto).
    static func setGlobal(_ emulator: Emulator, _ id: String, _ value: String?) {
        var values: [String: String] = global(emulator)
        values[id] = value
        UserDefaults.standard.set(values, forKey: globalKey(emulator))
    }

    /// Cambia un ajuste de un juego (nil: usa el general).
    static func setGame(_ emulator: Emulator, _ gameID: String, _ id: String, _ value: String?) {
        var values: [String: String] = game(emulator, gameID)
        values[id] = value
        if values.isEmpty {
            UserDefaults.standard.removeObject(forKey: gameKey(emulator, gameID))
        } else {
            UserDefaults.standard.set(values, forKey: gameKey(emulator, gameID))
        }
    }

    static func resetGlobal(_ emulator: Emulator) {
        UserDefaults.standard.removeObject(forKey: globalKey(emulator))
    }

    static func resetGame(_ emulator: Emulator, _ gameID: String) {
        UserDefaults.standard.removeObject(forKey: gameKey(emulator, gameID))
    }

    static func hasGameSettings(_ emulator: Emulator, _ gameID: String) -> Bool {
        !game(emulator, gameID).isEmpty
    }

    /// Valor general: el guardado o el de por defecto.
    static func globalValue(_ option: EmuOption, _ emulator: Emulator) -> String {
        global(emulator)[option.id] ?? option.defaultValue
    }

    /// Lo que se usa al jugar: por defecto, encima los generales y encima los del juego.
    static func effective(_ emulator: Emulator, gameID: String?) -> [String: String] {
        let general: [String: String] = global(emulator)
        let own: [String: String] = gameID.map { game(emulator, $0) } ?? [:]
        var result: [String: String] = [:]
        for option in options(emulator) {
            result[option.id] = own[option.id] ?? general[option.id] ?? option.defaultValue
        }
        return result
    }

    // MARK: ARMSX2 → PCSX2.ini

    /// Escribe en PCSX2.ini los ajustes de la partida (todos, para que no quede nada de otro juego).
    static func writeARMSX2(gameID: String?, buttonMap: [String: String] = [:]) {
        let values: [String: String] = effective(.armsx2, gameID: gameID)
        var entries: [(section: String, key: String, value: String)] = []
        for option in armsx2 {
            guard let section = option.section, let key = option.key else { continue }
            entries.append((section, key, values[option.id] ?? option.defaultValue))
        }
        // ARMSX2 vuelve a encender MTVU al arrancar salvo que se haya elegido a mano.
        entries.append(("ARMSX2iOS/Speedhacks", "ManualMTVU", "true"))
        entries.append(("ARMSX2iOS/Speedhacks", "ManualMTVUVersion", "3"))
        // El arranque rápido también se lee de aquí.
        entries.append(("GameISO", "FastBoot", values["EnableFastBoot"] ?? "true"))
        // HUD propio de ARMSX2 arriba a la derecha (el de OmniStation va a la izquierda).
        entries.append(("EmuCore/GS", "OsdPerformancePos", "3"))
        // Mapa de botones del juego (lo lee el núcleo al prepararse). Sin mapa: los de siempre.
        for (index, value) in armsx2GamepadMapping(buttonMap).enumerated() {
            entries.append(("ARMSX2iOS/GamepadMapping", "Button\(index)", String(value)))
        }
        let file: URL = ARMSX2CoreFolders.data.appendingPathComponent("inis", isDirectory: true).appendingPathComponent("PCSX2.ini")
        PCSX2Ini.apply(entries, to: file)
    }

    /// Índice de cada botón de PS2 en el mapa del núcleo (arriba, abajo, izquierda, derecha, ✕, ○,
    /// □, △, L1, R1, L2, R2, Start, Select, L3, R3) y su botón SDL de serie.
    private static let armsx2PadIndex: [String: Int] = [
        "a": 4, "b": 5, "x": 6, "y": 7, "l1": 8, "r1": 9, "l2": 10, "r2": 11,
        "menu": 12, "options": 13, "l3": 14, "r3": 15
    ]
    /// Botones SDL3 (SDL_GamepadButton): sur, este, oeste, norte, back, guide, start, sticks y hombros.
    private static let sdlButton: [String: Int] = [
        "a": 0, "b": 1, "x": 2, "y": 3, "options": 4, "menu": 6, "l3": 7, "r3": 8, "l1": 9, "r1": 10
    ]
    private static let armsx2DefaultMap: [Int] = [11, 12, 13, 14, 0, 1, 2, 3, 9, 10, -1, -1, 6, 4, 7, 8]

    /// Botón SDL de cada botón de PS2 con el mapa del juego («físico → el que manda»).
    /// L2 y R2 son gatillos analógicos en ARMSX2: no se pueden mover a otro sitio.
    static func armsx2GamepadMapping(_ map: [String: String]) -> [Int] {
        var result: [Int] = armsx2DefaultMap
        let changes = map.filter { entry in
            guard entry.key != entry.value, sdlButton[entry.key] != nil, let index = armsx2PadIndex[entry.value] else { return false }
            return index != 10 && index != 11
        }
        guard !changes.isEmpty else { return result }
        // Los botones de PS2 que recibe un botón movido dejan de venir de su botón de serie.
        for (physical, _) in changes {
            if let index = armsx2PadIndex[physical], result[index] == sdlButton[physical] { result[index] = -1 }
        }
        for (physical, target) in changes.sorted(by: { $0.key < $1.key }) {
            guard let index = armsx2PadIndex[target], let sdl = sdlButton[physical] else { continue }
            result[index] = sdl
        }
        return result
    }

    /// Opciones de OmniStation para la partida de ARMSX2 (no van al INI).
    static func armsx2HostOptions(gameID: String?, touchHaptics: Bool) -> [String: String] {
        let values: [String: String] = effective(.armsx2, gameID: gameID)
        return [
            "hudSystem": values["hudSystem"] ?? "false",
            "hudBattery": values["hudBattery"] ?? "false",
            "aspectRatio": values["AspectRatio"] ?? "Auto 4:3/3:2",
            "touchHaptics": touchHaptics ? "true" : "false"
        ]
    }
}

// MARK: - PCSX2.ini

/// Cambia claves de un INI sin tocar el resto (PCSX2 escribe «Clave = Valor»).
enum PCSX2Ini {
    static func apply(_ entries: [(section: String, key: String, value: String)], to url: URL) {
        let existing: String = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var lines: [String] = existing.isEmpty ? [] : existing.components(separatedBy: "\n")
        for entry in entries {
            set(&lines, section: entry.section, key: entry.key, value: entry.value)
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func set(_ lines: inout [String], section: String, key: String, value: String) {
        let header: String = "[" + section + "]"
        let entry: String = key + " = " + value
        var start: Int? = nil
        var index: Int = 0
        while index < lines.count {
            let trimmed: String = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                if start != nil { break }
                if trimmed == header { start = index }
            } else if start != nil, !trimmed.hasPrefix(";"), !trimmed.hasPrefix("#"),
                      let equals = trimmed.firstIndex(of: "=") {
                let name: String = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
                if name == key {
                    lines[index] = entry
                    return
                }
            }
            index += 1
        }
        if let start {
            var insertAt: Int = index
            while insertAt > start + 1, lines[insertAt - 1].trimmingCharacters(in: .whitespaces).isEmpty {
                insertAt -= 1
            }
            lines.insert(entry, at: insertAt)
        } else {
            if let last = lines.last, !last.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append("")
            }
            lines.append(header)
            lines.append(entry)
        }
    }
}
