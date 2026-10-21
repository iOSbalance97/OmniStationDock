import Foundation

// MARK: - Opciones propias de cada núcleo libretro
//
// Cada núcleo declara sus opciones (clave, nombre, valores y categoría; muchas traducidas al
// español). OmniStation se las pide sin abrir ningún juego (OSLibretroEngine) y las guarda.
// En los ajustes de cada sistema salen así:
// • Arriba, las generales de OmniStation (núcleo, JIT, imagen, proporción, HUD).
// • En cada pestaña, las importantes del núcleo elegido, con nombres claros.
// • En «Avanzado», todas las demás del núcleo, por sus categorías.
// No salen las que OmniStation pone siempre para que el núcleo funcione aquí (JIT, renderizador…).

/// Una opción importante: en qué pestaña va y cómo se llama aquí.
private struct CuratedOption {
    let key: String
    let tab: EmuTab
    let title: String
    var detail: String = ""
}

enum RetroCoreOptions {
    private static var memory: [String: [[String: Any]]] = [:]

    // MARK: Lo importante de cada núcleo

    private static func curated(_ coreID: String) -> [CuratedOption] {
        let g = EmuTab.graphics, s = EmuTab.system, i = EmuTab.input, a = EmuTab.audio
        switch coreID {
        case "nestopia":
            return [CuratedOption(key: "nestopia_palette", tab: g, title: "Paleta de colores"),
                    CuratedOption(key: "nestopia_aspect", tab: g, title: "Proporción del núcleo"),
                    CuratedOption(key: "nestopia_nospritelimit", tab: g, title: "Quitar el límite de sprites", detail: "Menos parpadeo cuando hay muchos objetos."),
                    CuratedOption(key: "nestopia_overscan_v", tab: g, title: "Recortar los bordes (vertical)"),
                    CuratedOption(key: "nestopia_overscan_h", tab: g, title: "Recortar los bordes (horizontal)"),
                    CuratedOption(key: "nestopia_blargg_ntsc_filter", tab: g, title: "Filtro de tele (NTSC)"),
                    CuratedOption(key: "nestopia_overclock", tab: s, title: "Overclock", detail: "Quita ralentizaciones en algunos juegos."),
                    CuratedOption(key: "nestopia_audio_type", tab: a, title: "Sonido")]
        case "snes9x":
            return [CuratedOption(key: "snes9x_aspect", tab: g, title: "Proporción del núcleo"),
                    CuratedOption(key: "snes9x_overscan", tab: g, title: "Recortar los bordes"),
                    CuratedOption(key: "snes9x_reduce_sprite_flicker", tab: g, title: "Reducir el parpadeo de sprites"),
                    CuratedOption(key: "snes9x_blargg", tab: g, title: "Filtro de tele (NTSC)"),
                    CuratedOption(key: "snes9x_overclock_superfx", tab: s, title: "Overclock del chip Super FX", detail: "Star Fox, Yoshi's Island… más fluidos."),
                    CuratedOption(key: "snes9x_overclock_cycles", tab: s, title: "Overclock de la CPU", detail: "Quita ralentizaciones; algún juego puede fallar."),
                    CuratedOption(key: "snes9x_region", tab: s, title: "Región")]
        case "gambatte":
            return [CuratedOption(key: "gambatte_gb_colorization", tab: g, title: "Colores (Game Boy)", detail: "Solo en juegos de Game Boy clásica."),
                    CuratedOption(key: "gambatte_gb_internal_palette", tab: g, title: "Paleta interna"),
                    CuratedOption(key: "gambatte_gbc_color_correction", tab: g, title: "Corrección de color (Color)"),
                    CuratedOption(key: "gambatte_mix_frames", tab: g, title: "Estela de la pantalla LCD", detail: "Como la pantalla de verdad; algunos juegos la usan para transparencias."),
                    CuratedOption(key: "gambatte_gb_hwmode", tab: s, title: "Modelo de consola"),
                    CuratedOption(key: "gambatte_gb_bootloader", tab: s, title: "Usar la BIOS")]
        case "mgba":
            return [CuratedOption(key: "mgba_color_correction", tab: g, title: "Corrección de color"),
                    CuratedOption(key: "mgba_interframe_blending", tab: g, title: "Estela de la pantalla LCD"),
                    CuratedOption(key: "mgba_gb_colors", tab: g, title: "Paleta (Game Boy)"),
                    CuratedOption(key: "mgba_gb_model", tab: s, title: "Modelo de Game Boy"),
                    CuratedOption(key: "mgba_use_bios", tab: s, title: "Usar la BIOS si está"),
                    CuratedOption(key: "mgba_skip_bios", tab: s, title: "Saltar la animación de la BIOS"),
                    CuratedOption(key: "mgba_frameskip", tab: s, title: "Saltar fotogramas"),
                    CuratedOption(key: "mgba_solar_sensor_level", tab: i, title: "Sensor solar (Boktai)")]
        case "gpsp":
            return [CuratedOption(key: "gpsp_color_correction", tab: g, title: "Corrección de color"),
                    CuratedOption(key: "gpsp_frame_mixing", tab: g, title: "Estela de la pantalla LCD"),
                    CuratedOption(key: "gpsp_bios", tab: s, title: "BIOS"),
                    CuratedOption(key: "gpsp_boot_mode", tab: s, title: "Arranque"),
                    CuratedOption(key: "gpsp_frameskip", tab: s, title: "Saltar fotogramas")]
        case "vbam":
            return [CuratedOption(key: "vbam_palettes", tab: g, title: "Paleta (Game Boy)"),
                    CuratedOption(key: "vbam_color_correction", tab: g, title: "Corrección de color"),
                    CuratedOption(key: "vbam_interframeblending", tab: g, title: "Estela de la pantalla LCD"),
                    CuratedOption(key: "vbam_usebios", tab: s, title: "Usar la BIOS si está"),
                    CuratedOption(key: "vbam_forceRTCenable", tab: s, title: "Reloj del cartucho (RTC)")]
        case "melondsds":
            return [CuratedOption(key: "melonds_screen_gap", tab: g, title: "Separación entre pantallas"),
                    CuratedOption(key: "melonds_hybrid_ratio", tab: g, title: "Tamaño en modo híbrido"),
                    CuratedOption(key: "melonds_console_mode", tab: s, title: "Consola (DS o DSi)"),
                    CuratedOption(key: "melonds_sysfile_mode", tab: s, title: "BIOS y firmware", detail: "Las tuyas (en BIOS) o las libres que trae el núcleo."),
                    CuratedOption(key: "melonds_boot_mode", tab: s, title: "Arranque", detail: "Directo al juego o por el menú de la consola."),
                    CuratedOption(key: "melonds_firmware_language", tab: s, title: "Idioma de la consola"),
                    CuratedOption(key: "melonds_firmware_username", tab: s, title: "Nombre de usuario"),
                    CuratedOption(key: "melonds_threaded_renderer", tab: s, title: "Imagen en otro hilo", detail: "Más rápido en casi todos los juegos."),
                    CuratedOption(key: "melonds_touch_mode", tab: i, title: "Pantalla táctil"),
                    CuratedOption(key: "melonds_mic_input", tab: i, title: "Micrófono"),
                    CuratedOption(key: "melonds_slot2_device", tab: i, title: "Accesorio del slot 2")]
        case "desmume":
            return [CuratedOption(key: "desmume_internal_resolution", tab: g, title: "Resolución interna"),
                    CuratedOption(key: "desmume_screens_gap", tab: g, title: "Separación entre pantallas"),
                    CuratedOption(key: "desmume_hybrid_layout_scale", tab: g, title: "Tamaño en modo híbrido"),
                    CuratedOption(key: "desmume_firmware_language", tab: s, title: "Idioma de la consola"),
                    CuratedOption(key: "desmume_frameskip", tab: s, title: "Saltar fotogramas"),
                    CuratedOption(key: "desmume_load_to_memory", tab: s, title: "Cargar el juego en memoria"),
                    CuratedOption(key: "desmume_mic_mode", tab: i, title: "Micrófono")]
        case "pcsx_rearmed":
            return [CuratedOption(key: "pcsx_rearmed_neon_enhancement_enable", tab: g, title: "Doble de resolución", detail: "Mejora NEON: imagen más nítida y gasta más."),
                    CuratedOption(key: "pcsx_rearmed_neon_interlace_enable", tab: g, title: "Entrelazado"),
                    CuratedOption(key: "pcsx_rearmed_dithering", tab: g, title: "Tramado (dithering)"),
                    CuratedOption(key: "pcsx_rearmed_screen_centering", tab: g, title: "Centrar la imagen"),
                    CuratedOption(key: "pcsx_rearmed_bios", tab: s, title: "BIOS", detail: "Automática usa la tuya si está; si no, la interna."),
                    CuratedOption(key: "pcsx_rearmed_show_bios_bootlogo", tab: s, title: "Logo de la BIOS al arrancar"),
                    CuratedOption(key: "pcsx_rearmed_region", tab: s, title: "Región"),
                    CuratedOption(key: "pcsx_rearmed_psxclock", tab: s, title: "Velocidad de la CPU"),
                    CuratedOption(key: "pcsx_rearmed_frameskip_type", tab: s, title: "Saltar fotogramas"),
                    CuratedOption(key: "pcsx_rearmed_memcard2", tab: s, title: "Segunda tarjeta de memoria"),
                    CuratedOption(key: "pcsx_rearmed_pad1type", tab: i, title: "Mando del jugador 1", detail: "Analógico/DualShock para los juegos que usan los sticks."),
                    CuratedOption(key: "pcsx_rearmed_vibration", tab: i, title: "Vibración")]
        case "beetle_psx_hw":
            return [CuratedOption(key: "beetle_psx_hw_internal_resolution", tab: g, title: "Resolución interna"),
                    CuratedOption(key: "beetle_psx_hw_filter", tab: g, title: "Filtro de texturas"),
                    CuratedOption(key: "beetle_psx_hw_pgxp_mode", tab: g, title: "PGXP (geometría precisa)", detail: "Quita el temblor de los polígonos de PS1."),
                    CuratedOption(key: "beetle_psx_hw_pgxp_texture", tab: g, title: "Texturas con perspectiva correcta (PGXP)"),
                    CuratedOption(key: "beetle_psx_hw_widescreen_hack", tab: g, title: "Pantalla panorámica (truco)"),
                    CuratedOption(key: "beetle_psx_hw_dither_mode", tab: g, title: "Tramado (dithering)"),
                    CuratedOption(key: "beetle_psx_hw_skip_bios", tab: s, title: "Saltar la BIOS"),
                    CuratedOption(key: "beetle_psx_hw_cd_fastload", tab: s, title: "Carga rápida del CD"),
                    CuratedOption(key: "beetle_psx_hw_cpu_freq_scale", tab: s, title: "Velocidad de la CPU"),
                    CuratedOption(key: "beetle_psx_hw_override_bios", tab: s, title: "Usar otra BIOS"),
                    CuratedOption(key: "beetle_psx_hw_analog_toggle", tab: i, title: "Modo analógico (DualShock)")]
        case "mupen64plus_next":
            return [CuratedOption(key: "mupen64plus-EnableNativeResFactor", tab: g, title: "Resolución interna", detail: "Veces la resolución de la N64."),
                    CuratedOption(key: "mupen64plus-aspect", tab: g, title: "Proporción"),
                    CuratedOption(key: "mupen64plus-BilinearMode", tab: g, title: "Filtro bilineal"),
                    CuratedOption(key: "mupen64plus-MultiSampling", tab: g, title: "Antialiasing (MSAA)"),
                    CuratedOption(key: "mupen64plus-EnableFBEmulation", tab: g, title: "Emulación del framebuffer", detail: "Necesaria para algunos efectos; si un juego va lento, prueba a quitarla."),
                    CuratedOption(key: "mupen64plus-txFilterMode", tab: g, title: "Filtro de texturas"),
                    CuratedOption(key: "mupen64plus-Framerate", tab: s, title: "Fotogramas", detail: "Completo da más fluidez en algunos juegos."),
                    CuratedOption(key: "mupen64plus-pak1", tab: i, title: "Accesorio del mando", detail: "Memoria, vibración o Transfer Pak."),
                    CuratedOption(key: "mupen64plus-astick-deadzone", tab: i, title: "Zona muerta del stick"),
                    CuratedOption(key: "mupen64plus-astick-sensitivity", tab: i, title: "Sensibilidad del stick")]
        case "ppsspp":
            return [CuratedOption(key: "ppsspp_internal_resolution", tab: g, title: "Resolución interna"),
                    CuratedOption(key: "ppsspp_texture_scaling_level", tab: g, title: "Escalado de texturas"),
                    CuratedOption(key: "ppsspp_texture_scaling_type", tab: g, title: "Tipo de escalado de texturas"),
                    CuratedOption(key: "ppsspp_texture_anisotropic_filtering", tab: g, title: "Filtro anisótropo"),
                    CuratedOption(key: "ppsspp_texture_filtering", tab: g, title: "Filtro de texturas"),
                    CuratedOption(key: "ppsspp_frameskip", tab: s, title: "Saltar fotogramas"),
                    CuratedOption(key: "ppsspp_fast_memory", tab: s, title: "Memoria rápida", detail: "Más rápido; algún juego puede fallar."),
                    CuratedOption(key: "ppsspp_language", tab: s, title: "Idioma de la consola"),
                    CuratedOption(key: "ppsspp_cheats", tab: s, title: "Trucos"),
                    CuratedOption(key: "ppsspp_button_preference", tab: i, title: "Botón para aceptar", detail: "✕ (Europa/América) o ○ (Japón).")]
        case "flycast", "flycast_jitless":
            return [CuratedOption(key: "reicast_internal_resolution", tab: g, title: "Resolución interna"),
                    CuratedOption(key: "reicast_widescreen_hack", tab: g, title: "Pantalla panorámica (truco)"),
                    CuratedOption(key: "reicast_widescreen_cheats", tab: g, title: "Panorámica por trucos"),
                    CuratedOption(key: "reicast_anisotropic_filtering", tab: g, title: "Filtro anisótropo"),
                    CuratedOption(key: "reicast_texupscale", tab: g, title: "Escalado de texturas"),
                    CuratedOption(key: "reicast_alpha_sorting", tab: g, title: "Ordenar transparencias"),
                    CuratedOption(key: "reicast_cable_type", tab: g, title: "Tipo de cable (VGA o tele)"),
                    CuratedOption(key: "reicast_region", tab: s, title: "Región"),
                    CuratedOption(key: "reicast_language", tab: s, title: "Idioma de la consola"),
                    CuratedOption(key: "reicast_frame_skipping", tab: s, title: "Saltar fotogramas"),
                    CuratedOption(key: "reicast_boot_to_bios", tab: s, title: "Arrancar en la BIOS"),
                    CuratedOption(key: "reicast_enable_dsp", tab: a, title: "DSP de sonido", detail: "Efectos de sonido más fieles; gasta más.")]
        case "azahar":
            return [CuratedOption(key: "citra_resolution_factor", tab: g, title: "Resolución interna"),
                    CuratedOption(key: "citra_texture_filter", tab: g, title: "Filtro de texturas"),
                    CuratedOption(key: "citra_texture_sampling", tab: g, title: "Muestreo de texturas"),
                    CuratedOption(key: "citra_use_hw_shader", tab: g, title: "Shaders por GPU"),
                    CuratedOption(key: "citra_swap_screen", tab: g, title: "Pantalla principal"),
                    CuratedOption(key: "citra_large_screen_proportion", tab: g, title: "Tamaño de la pantalla grande"),
                    CuratedOption(key: "citra_custom_textures", tab: g, title: "Texturas personalizadas"),
                    CuratedOption(key: "citra_region_value", tab: s, title: "Región"),
                    CuratedOption(key: "citra_language_value", tab: s, title: "Idioma de la consola"),
                    CuratedOption(key: "citra_cpu_clock_percentage", tab: s, title: "Velocidad de la CPU"),
                    CuratedOption(key: "citra_use_virtual_sd", tab: s, title: "Tarjeta SD virtual"),
                    CuratedOption(key: "citra_analog_deadzone", tab: i, title: "Zona muerta del stick"),
                    CuratedOption(key: "citra_enable_motion", tab: i, title: "Sensor de movimiento")]
        case "dolphin_omni":
            return [CuratedOption(key: "dolphin_efb_scale", tab: g, title: "Resolución interna"),
                    CuratedOption(key: "dolphin_widescreen", tab: g, title: "Panorámico (16:9)"),
                    CuratedOption(key: "dolphin_widescreen_hack", tab: g, title: "Panorámico (truco)"),
                    CuratedOption(key: "dolphin_max_anisotropy", tab: g, title: "Filtro anisótropo"),
                    CuratedOption(key: "dolphin_anti_aliasing", tab: g, title: "Antialiasing"),
                    CuratedOption(key: "dolphin_language", tab: s, title: "Idioma de la consola"),
                    CuratedOption(key: "dolphin_main_cpu_thread", tab: s, title: "Doble núcleo", detail: "Más rápido; algún juego puede fallar."),
                    CuratedOption(key: "dolphin_cheats_enabled", tab: s, title: "Trucos"),
                    CuratedOption(key: "dolphin_pal60", tab: s, title: "PAL a 60 Hz"),
                    CuratedOption(key: "dolphin_enable_rumble", tab: i, title: "Vibración")]
        default:
            return []
        }
    }

    /// Las que OmniStation pone siempre para que el núcleo funcione aquí (no se enseñan).
    private static func forced(_ coreID: String, key: String) -> Bool {
        let fixed: Set<String> = [
            "melonds_jit_enable", "melonds_number_of_screen_layouts", "melonds_show_cursor", "melonds_mic_input_active",
            "desmume_pointer_type", "desmume_pointer_device_l", "desmume_pointer_device_r", "desmume_screens_layout",
            "pcsx_rearmed_drc", "beetle_psx_hw_cpu_dynarec", "beetle_psx_hw_renderer",
            "mupen64plus-cpucore", "mupen64plus-rdp-plugin",
            "ppsspp_backend", "ppsspp_cpu_core", "ppsspp_software_rendering_jit",
            "reicast_threaded_rendering", "reicast_dynamic_cpu_ratio", "reicast_sh4clock", "reicast_hle_bios",
            "citra_use_cpu_jit", "citra_use_shader_jit", "citra_input_type", "citra_enable_touch_touchscreen",
            "citra_enable_mouse_touchscreen", "citra_use_default_aes_key", "citra_layout_option",
            "dolphin_cpu_core", "dolphin_cpu_clock_rate", "dolphin_osd_enabled", "dolphin_fast_disc_speed",
            "dolphin_gpu_texture_decoding", "dolphin_shader_compilation_mode", "dolphin_vi_skip",
            "dolphin_skip_gc_bios", "dolphin_log_level", "dolphin_renderer"
        ]
        if fixed.contains(key) { return true }
        // Las pantallas de NDS van con la orientación.
        return key.hasPrefix("melonds_screen_layout") || key == "melonds_custom_layout_config"
    }

    // MARK: Leer y guardar

    private static var folder: URL { AppFolders.folder("RetroOptions") }

    private static var appBuild: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "0"
    }

    private static func file(_ core: RetroCore) -> URL {
        folder.appendingPathComponent(core.framework + "-" + appBuild + ".json")
    }

    /// Lo que declara el núcleo (de la memoria o del disco; sin abrirlo).
    private static func cached(_ core: RetroCore) -> [[String: Any]]? {
        if let found = memory[core.framework] { return found }
        guard let data = try? Data(contentsOf: file(core)),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        memory[core.framework] = list
        return list
    }

    /// Se las pide al núcleo si aún no se tienen (en el hilo principal y sin partida abierta).
    static func prepare(_ core: RetroCore) {
        guard Thread.isMainThread, cached(core) == nil, OSLibretroEngine.coreAvailable(core.framework) else { return }
        let language: String = L10n.resolve(UserDefaults.standard.string(forKey: "appLanguage") ?? "system")
        guard let list = OSLibretroEngine.shared.options(forCore: core.framework, language: language) else { return }
        let clean: [[String: Any]] = list
        memory[core.framework] = clean
        if let data = try? JSONSerialization.data(withJSONObject: clean) {
            try? data.write(to: file(core), options: .atomic)
        }
    }

    /// Las que declaró el núcleo al jugar (los que solo las declaran al prepararse): se guardan si
    /// aún no se tenían.
    static func remember(_ core: RetroCore, list: [[String: Any]]?) {
        guard let list, !list.isEmpty else { return }
        if let known = cached(core), !known.isEmpty { return }
        memory[core.framework] = list
        if let data = try? JSONSerialization.data(withJSONObject: list) {
            try? data.write(to: file(core), options: .atomic)
        }
    }

    /// Las de todos los núcleos de un sistema (al abrir sus ajustes).
    static func prepare(_ system: RetroSystem) {
        for core in system.availableCores { prepare(core) }
    }

    // MARK: Opciones para los ajustes

    /// «enabled»/«disabled» sin traducir del núcleo → Sí/No.
    private static func label(_ text: String) -> String {
        switch text.lowercased() {
        case "enabled", "on", "true": return "Sí"
        case "disabled", "off", "false": return "No"
        case "auto", "automatic": return "Automático"
        default: return text
        }
    }

    private static func option(_ entry: [String: Any], core: RetroCore, tab: EmuTab, title: String?, detail: String?, group: String) -> EmuOption? {
        guard let key = entry["key"] as? String, let pairs = entry["values"] as? [[String]], !pairs.isEmpty else { return nil }
        let choices: [EmuChoice] = pairs.compactMap { pair in
            guard let value = pair.first else { return nil }
            let shown: String = pair.count > 1 ? pair[1] : value
            return EmuChoice(value: value, label: shown == value ? label(shown) : shown)
        }
        let fallback: String = (entry["default"] as? String) ?? choices[0].value
        let coreTitle: String = (entry["title"] as? String) ?? key
        var info: String = detail ?? ((entry["info"] as? String) ?? "")
        if info.count > 160 { info = String(info.prefix(157)) + "…" }
        var result = EmuOption(id: "opt." + key, tab: tab, title: title ?? coreTitle, detail: info,
                               choices: choices, defaultValue: fallback)
        result.group = group
        result.onlyCore = core.id
        return result
    }

    /// Las del núcleo: las importantes en su pestaña y el resto en Avanzado (por categorías).
    static func options(for core: RetroCore) -> [EmuOption] {
        guard let list = cached(core), !list.isEmpty else { return [] }
        var byKey: [String: [String: Any]] = [:]
        for entry in list {
            if let key = entry["key"] as? String { byKey[key] = entry }
        }
        var result: [EmuOption] = []
        var used: Set<String> = []
        for item in curated(core.id) {
            guard let entry = byKey[item.key], !forced(core.id, key: item.key) else { continue }
            if let made = option(entry, core: core, tab: item.tab, title: item.title, detail: item.detail.isEmpty ? nil : item.detail, group: core.name) {
                result.append(made)
                used.insert(item.key)
            }
        }
        for entry in list {
            guard let key = entry["key"] as? String, !used.contains(key), !forced(core.id, key: key) else { continue }
            let category: String = (entry["categoryTitle"] as? String) ?? ""
            let group: String = core.name + (category.isEmpty ? "" : " · " + category)
            if let made = option(entry, core: core, tab: .advanced, title: nil, detail: nil, group: group) {
                result.append(made)
            }
        }
        return result
    }

    /// Las del núcleo para el menú de la partida (clave, nombre, grupo, valores y el de ahora).
    static func menuOptions(for core: RetroCore, current: [String: String], language: String) -> [[String: Any]] {
        options(for: core).map { option -> [String: Any] in
            let key: String = String(option.id.dropFirst(4))
            let group: String = option.tab == .advanced ? option.group : L10n.tr(option.tab.title, language)
            let values: [[String]] = option.choices.map { [$0.value, L10n.tr($0.label, language)] }
            return ["key": key, "title": L10n.tr(option.title, language), "group": group,
                    "values": values, "value": current[key] ?? option.defaultValue]
        }
    }

    /// Las de todos los núcleos del sistema que ya se conocen (sin abrir ninguno).
    static func cachedOptions(_ system: RetroSystem) -> [EmuOption] {
        system.availableCores.flatMap { options(for: $0) }
    }
}
