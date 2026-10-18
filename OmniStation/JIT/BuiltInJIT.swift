import Foundation
import UIKit
import AVFoundation

// MARK: - Qué activa el JIT con SideStore/AltStore

enum JITEnabler: String, CaseIterable {
    /// StikJIT dentro de OmniStation: no hace falta ninguna otra app.
    case builtIn = "builtin"
    /// La app StikDebug.
    case stikDebug = "stikdebug"

    static let storageKey = "jitEnabler"

    static var current: JITEnabler {
        let raw: String = UserDefaults.standard.string(forKey: storageKey) ?? ""
        return JITEnabler(rawValue: raw) ?? .builtIn
    }
}

/// Script de JIT para dispositivos con TXM (iOS 26 en A15/M2 o posteriores).
enum JITScriptChoice: String, CaseIterable {
    case automatic = "auto"
    case universal = "universal"
    case legacy = "legacy"
    case noScript = "none"

    init(stored: String?) {
        self = JITScriptChoice(rawValue: stored ?? "") ?? .automatic
    }

    /// Apps conocidas y su script (la misma tabla que usa StikDebug, por nombre de la app).
    private static let knownApps: [String: JITScriptChoice] = [
        "Amethyst": .universal, "MeloNX": .universal, "XeniOS": .universal, "MeloCafé": .universal,
        "Manic EMU": .universal, "DukeX": .universal, "TachyonU": .universal, "touchHLE": .universal,
        "HyperHLE": .universal, "Applesauce": .universal, "RPCS3": .universal, "AetherPS4": .universal,
        "Husk": .universal,
        "UTM": .legacy, "DolphiniOS": .legacy, "Flycast": .legacy, "ARMSX2 iOS": .legacy
    ]

    /// Script que se usará de verdad (nil = conectar y soltar, sin script).
    func resolved(appName: String?) -> StikJIT.Script? {
        switch self {
        case .universal: return .universal
        case .legacy: return .legacy
        case .noScript: return nil
        case .automatic:
            guard let appName, let known = Self.knownApps[appName] else { return nil }
            return known == .legacy ? .legacy : .universal
        }
    }
}

// MARK: - StikJIT integrado

/// Activa el JIT de apps instaladas con SideStore/AltStore sin StikDebug: OmniStation abre la app
/// con el depurador por la VPN LocalDevVPN usando el archivo de emparejamiento.
enum BuiltInJIT {
    static let forceScriptKey = "stikjitForceScript"

    /// Todo el trabajo de StikJIT va en una sola cola serie (así lo pide su documentación).
    private static let queue = DispatchQueue(label: "omnistation.builtin-jit", qos: .userInitiated)
    private static let lookupQueue = DispatchQueue(label: "omnistation.builtin-jit.lookup", qos: .userInitiated)

    /// PID de la última app abierta con JIT, por Bundle ID.
    private static let pidsKey = "builtinJITPids"

    static var isSupportedOS: Bool {
        if #available(iOS 17.4, *) { return true }
        return false
    }

    /// Dentro de LiveContainer no se usa (allí el JIT lo pide LiveContainer).
    static var isAvailable: Bool {
        isSupportedOS && !DebugSupport.isInsideLiveContainer
    }

    static var ddiPaths: DDIPaths {
        let library: URL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        return DDIPaths.default(in: library.appendingPathComponent("StikJIT"))
    }

    static var forceScript: Bool {
        UserDefaults.standard.bool(forKey: forceScriptKey)
    }

    /// "Presente", "No presente" o nil si no se sabe.
    static var txmPresent: Bool? {
        StikJIT.isTXMPresent
    }

    // MARK: Comprobaciones previas

    /// Motivo por el que no se puede usar ahora (nil = se puede intentar).
    static func preflightProblem(lang: String) -> String? {
        guard isSupportedOS else { return L10n.tr("El JIT integrado necesita iOS 17.4 o posterior.", lang) }
        guard !DebugSupport.isInsideLiveContainer else {
            return L10n.tr("Dentro de LiveContainer el JIT lo activa LiveContainer.", lang)
        }
        guard PairingFile.exists else { return L10n.tr("Importa tu archivo de emparejamiento en Ajustes → Depuración.", lang) }
        guard PairingFile.info()?.kind == .remotePairing else {
            return L10n.tr("Tu archivo de emparejamiento es del tipo antiguo. Crea uno nuevo con iloader.", lang)
        }
        return nil
    }

    // MARK: Preparar

    enum Readiness {
        case ready(txm: Bool?)
        case unreachable(String)
        case notReady(String)
    }

    /// Comprueba la VPN y monta la imagen de desarrollador si hace falta.
    static func prepare(progress: @escaping (String) -> Void, completion: @escaping (Readiness) -> Void) {
        let pairing: URL = PairingFile.url
        let paths: DDIPaths = ddiPaths
        queue.async {
            let result = StikJIT.prepareDevice(pairingFile: pairing, paths: paths) { stage in
                let text: String = describe(stage)
                DispatchQueue.main.async { progress(text) }
            }
            let readiness: Readiness
            switch result {
            case .ready(let state): readiness = .ready(txm: state.isTXMPresent)
            case .unreachable(let reason): readiness = .unreachable(reason)
            case .preparationFailed(let reason): readiness = .notReady(reason)
            }
            DispatchQueue.main.async { completion(readiness) }
        }
    }

    static func resetDiskImage() throws {
        try StikJIT.resetCachedDDI(at: ddiPaths)
    }

    private static func describe(_ stage: StikJIT.PreparationStage) -> String {
        switch stage {
        case .checkingReachability: return "VPN…"
        case .checkingDDI: return "DDI…"
        case .downloadingDDI(let fraction, _): return "DDI ↓ \(Int(fraction * 100))%"
        case .mountingDDI(let fraction): return "DDI ⏏ \(Int(fraction * 100))%"
        case .verifyingDDI: return "DDI ✓…"
        case .ready: return "OK"
        }
    }

    // MARK: Abrir una app con JIT

    /// Prepara el dispositivo, abre la app con el depurador y le deja el JIT activado.
    static func launch(bundleID: String,
                       script choice: JITScriptChoice,
                       progress: @escaping (String) -> Void,
                       completion: @escaping (Result<Int32, Error>) -> Void) {
        let pairing: URL = PairingFile.url
        let paths: DDIPaths = ddiPaths
        let force: Bool = forceScript
        let keepAlive = JITKeepAlive()
        queue.async {
            let outcome: Result<Int32, Error>
            do {
                let readiness = StikJIT.prepareDevice(pairingFile: pairing, paths: paths) { stage in
                    let text: String = describe(stage)
                    DispatchQueue.main.async { progress(text) }
                }
                var txm: Bool? = nil
                switch readiness {
                case .ready(let state): txm = state.isTXMPresent
                case .unreachable(let reason), .preparationFailed(let reason):
                    throw StikJITError.deviceNotReady(reason)
                }
                let session = ExternalJITSession(pairingFilePath: pairing.path)
                let script: StikJIT.Script? = try scriptToUse(choice, txm: txm, force: force, bundleID: bundleID, session: session)
                let pid: Int32 = try session.launchWithJIT(bundleID: bundleID, script: script) { _ in }
                remember(pid: pid, for: bundleID)
                outcome = .success(pid)
            } catch {
                outcome = .failure(error)
            }
            DispatchQueue.main.async {
                keepAlive.invalidate()
                completion(outcome)
            }
        }
    }

    /// Con TXM hace falta el script que use la app; sin TXM basta con conectar y soltar.
    private static func scriptToUse(_ choice: JITScriptChoice,
                                    txm: Bool?,
                                    force: Bool,
                                    bundleID: String,
                                    session: ExternalJITSession) throws -> StikJIT.Script? {
        guard force || txm != false else { return nil }
        if txm == nil && !force && choice == .automatic {
            throw StikJITError.txmDetectionUnavailable
        }
        var name: String? = nil
        if choice == .automatic {
            name = (try? session.debuggableApps())?.first(where: { $0.bundleID == bundleID })?.name
        }
        return choice.resolved(appName: name)
    }

    // MARK: Abrir el juego y después dar el JIT

    /// Apps con una sesión de JIT en marcha (con TXM el script espera a que el juego arranque).
    private static var activeSessions: Set<String> = []
    private static let sessionLock = NSLock()

    static func isSessionActive(for bundleID: String) -> Bool {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        return activeSessions.contains(bundleID)
    }

    private static func setSession(_ bundleID: String, active: Bool) {
        sessionLock.lock()
        if active { activeSessions.insert(bundleID) } else { activeSessions.remove(bundleID) }
        sessionLock.unlock()
    }

    /// Para emuladores que esperan al JIT por su cuenta (MeloNX): la app ya se ha abierto con el
    /// enlace del juego; aquí se busca su proceso y se le activa el JIT sin relanzarla.
    static func attachWhenRunning(bundleID: String,
                                  appName: String,
                                  script choice: JITScriptChoice,
                                  timeout: TimeInterval = 20,
                                  completion: @escaping (Result<Int32, Error>) -> Void) {
        let pairing: URL = PairingFile.url
        let paths: DDIPaths = ddiPaths
        let force: Bool = forceScript
        let keepAlive = JITKeepAlive()
        setSession(bundleID, active: true)
        queue.async {
            let outcome: Result<Int32, Error>
            do {
                let readiness = StikJIT.prepareDevice(pairingFile: pairing, paths: paths)
                var txm: Bool? = nil
                switch readiness {
                case .ready(let state): txm = state.isTXMPresent
                case .unreachable(let reason), .preparationFailed(let reason):
                    throw StikJITError.deviceNotReady(reason)
                }
                let session = ExternalJITSession(pairingFilePath: pairing.path)
                guard let path = try session.bundlePath(of: bundleID) else {
                    throw StikJITError.device(code: -1, subCode: 0, message: "\(bundleID) is not installed")
                }
                let pid: Int32 = try waitForProcess(session: session, bundlePath: path, timeout: timeout)
                var script: StikJIT.Script? = nil
                if force || txm != false {
                    script = choice.resolved(appName: appName)
                }
                remember(pid: pid, for: bundleID)
                try session.attachJIT(pid: pid, script: script) { _ in }
                outcome = .success(pid)
            } catch {
                outcome = .failure(error)
            }
            setSession(bundleID, active: false)
            DispatchQueue.main.async {
                keepAlive.invalidate()
                completion(outcome)
            }
        }
    }

    private static func waitForProcess(session: ExternalJITSession, bundlePath: String, timeout: TimeInterval) throws -> Int32 {
        let deadline: Date = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let pid = try? session.runningPID(bundlePath: bundlePath) { return pid }
            Thread.sleep(forTimeInterval: 0.5)
        }
        throw StikJITError.device(code: -1, subCode: 0, message: "The app did not open in time")
    }

    // MARK: Apps instaladas

    static func debuggableApps(completion: @escaping (Result<[DebuggableApp], Error>) -> Void) {
        let pairing: URL = PairingFile.url
        queue.async {
            let outcome: Result<[DebuggableApp], Error>
            do {
                outcome = .success(try ExternalJITSession(pairingFilePath: pairing.path).debuggableApps())
            } catch {
                outcome = .failure(error)
            }
            DispatchQueue.main.async { completion(outcome) }
        }
    }

    // MARK: ¿Sigue abierta con JIT?

    /// ¿La última app que se abrió con JIT sigue abierta? (entonces conserva el JIT).
    static func isStillRunningWithJIT(bundleID: String, completion: @escaping (Bool) -> Void) {
        if isSessionActive(for: bundleID) {
            completion(true)
            return
        }
        guard let pid = rememberedPID(for: bundleID) else {
            completion(false)
            return
        }
        let pairing: URL = PairingFile.url
        // Cola aparte: la principal puede estar ocupada esperando a que arranque un juego.
        lookupQueue.async {
            let running: Bool = (try? ExternalJITSession(pairingFilePath: pairing.path).isRunning(pid: pid)) ?? false
            DispatchQueue.main.async { completion(running) }
        }
    }

    private static func remember(pid: Int32, for bundleID: String) {
        var pids: [String: Int] = UserDefaults.standard.dictionary(forKey: pidsKey) as? [String: Int] ?? [:]
        pids[bundleID] = Int(pid)
        UserDefaults.standard.set(pids, forKey: pidsKey)
    }

    private static func rememberedPID(for bundleID: String) -> Int32? {
        let pids: [String: Int] = UserDefaults.standard.dictionary(forKey: pidsKey) as? [String: Int] ?? [:]
        guard let value = pids[bundleID], value > 0 else { return nil }
        return Int32(truncatingIfNeeded: value)
    }

    /// Texto claro para un error de StikJIT.
    static func message(for error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription { return localized }
        return error.localizedDescription
    }
}

// MARK: - Mantener la app despierta mientras se activa el JIT

/// La app que recibe el JIT pasa a primer plano y OmniStation queda detrás. Para que iOS no la
/// congele a mitad (con TXM el script tarda unos segundos), se pide tiempo en segundo plano y
/// suena un audio en silencio, como hace StikDebug.
final class JITKeepAlive {
    private var task: UIBackgroundTaskIdentifier = .invalid
    private var player: AVAudioPlayer?
    private var active = true

    init() {
        task = UIApplication.shared.beginBackgroundTask(withName: "OmniStationJIT") { [weak self] in
            self?.invalidate()
        }
        startSilence()
    }

    func invalidate() {
        guard active else { return }
        active = false
        player?.stop()
        player = nil
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        if task != .invalid {
            UIApplication.shared.endBackgroundTask(task)
            task = .invalid
        }
    }

    private func startSilence() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            let silent = try AVAudioPlayer(data: Self.silentWAV)
            silent.numberOfLoops = -1
            silent.volume = 0
            silent.play()
            player = silent
        } catch {
            player = nil
        }
    }

    /// Un segundo de silencio en WAV (16 bits, mono, 8 kHz).
    private static let silentWAV: Data = {
        let sampleRate: UInt32 = 8000
        let samples: UInt32 = sampleRate
        let dataSize: UInt32 = samples * 2
        var data = Data()
        func append(_ text: String) { data.append(contentsOf: Array(text.utf8)) }
        func append32(_ value: UInt32) {
            var little: UInt32 = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        func append16(_ value: UInt16) {
            var little: UInt16 = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        append("RIFF")
        append32(36 + dataSize)
        append("WAVE")
        append("fmt ")
        append32(16)
        append16(1)
        append16(1)
        append32(sampleRate)
        append32(sampleRate * 2)
        append16(2)
        append16(16)
        append("data")
        append32(dataSize)
        data.append(Data(count: Int(dataSize)))
        return data
    }()
}

// MARK: - Preparación automática

/// Estado del JIT integrado, compartido por toda la app. Se prepara solo al abrir la app y al
/// volver a ella; la imagen de desarrollador queda montada hasta reiniciar el iPhone, así que
/// las siguientes veces solo se comprueba la VPN (un instante).
final class JITStatusCenter: ObservableObject {
    static let shared = JITStatusCenter()

    enum State: Equatable {
        case idle
        case preparing(String)
        case ready
        case unreachable(String)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    private var lastReady: Date?

    var isReady: Bool { state == .ready }
    var isPreparing: Bool {
        if case .preparing = state { return true }
        return false
    }

    /// Prepara sin preguntar. Con `force` repite aunque esté listo hace poco.
    func autoPrepare(force: Bool = false) {
        guard BuiltInJIT.isAvailable, PairingFile.info()?.kind == .remotePairing else { return }
        guard !isPreparing else { return }
        if !force, state == .ready, let lastReady, Date().timeIntervalSince(lastReady) < 120 { return }
        state = .preparing("")
        BuiltInJIT.prepare(progress: { [weak self] text in
            guard let self, self.isPreparing else { return }
            self.state = .preparing(text)
        }, completion: { [weak self] readiness in
            guard let self else { return }
            switch readiness {
            case .ready:
                self.state = .ready
                self.lastReady = Date()
            case .unreachable(let reason):
                self.state = .unreachable(reason)
            case .notReady(let reason):
                self.state = .failed(reason)
            }
        })
    }

    /// Tras abrir una app con JIT correctamente, el dispositivo está listo.
    func markReady() {
        state = .ready
        lastReady = Date()
    }

    /// Al cambiar el archivo de emparejamiento o borrar la imagen, hay que volver a comprobar.
    func invalidate() {
        guard !isPreparing else { return }
        state = .idle
        lastReady = nil
    }
}
