// Extensión de JIT de OmniStation Dock para sus emuladores integrados.
//
// Basada en el ayudante de JIT de NeoStation iOS (TarbleFR, GPL-3.0-or-later):
// https://github.com/TarbleFR/neostation-ios — packages/armsx2_jit_helper.
//
// Una app no puede ser su propio depurador: mientras el depurador la detiene, se detiene
// también el código que habla con él. Esta extensión es un proceso aparte que iOS lanza a
// petición de OmniStation: se engancha a OmniStation con StikJIT (por LocalDevVPN) y atiende
// las peticiones de JIT del núcleo hasta que este pide soltarse.
import Foundation
import Network

private let jitRequestType = "com.omnistation.dock.jit-request"

@objc(OmniStationJITRequestHandler)
final class OmniStationJITRequestHandler: NSObject, NSExtensionRequestHandling {
    private let jitQueue = DispatchQueue(label: "com.omnistation.dock.jit-helper", qos: .userInitiated)

    func beginRequest(with context: NSExtensionContext) {
        guard let item = context.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first(where: { $0.hasItemConformingToTypeIdentifier(jitRequestType) }) else {
            context.cancelRequest(withError: HelperError.invalidRequest("Falta la petición de JIT."))
            return
        }
        provider.loadItem(forTypeIdentifier: jitRequestType, options: nil) { [weak self] item, error in
            guard let self else { return }
            if let error {
                context.cancelRequest(withError: error)
                return
            }
            let data: Data?
            if let value = item as? Data {
                data = value
            } else if let value = item as? NSData {
                data = value as Data
            } else if let url = item as? URL {
                data = try? Data(contentsOf: url)
            } else {
                data = nil
            }
            guard let data else {
                context.cancelRequest(withError: HelperError.invalidRequest("No se pudo leer la petición de JIT."))
                return
            }
            self.jitQueue.async {
                self.process(data: data, context: context)
            }
        }
    }

    private func process(data: Data, context: NSExtensionContext) {
        var reporter: HelperReporter?
        var temporaryFiles: [URL] = []
        defer {
            for url in temporaryFiles { try? FileManager.default.removeItem(at: url) }
        }
        do {
            let request: HelperRequest = try HelperRequest(data: data)
            let channel = try HelperReporter(port: request.port, token: request.token)
            reporter = channel
            try channel.connect()
            try channel.send(event: "helper_connected", message: "Ayudante de JIT conectado a OmniStation.")
            channel.log("StikJIT para OmniStation (PID \(request.targetPID)); iOS \(ProcessInfo.processInfo.operatingSystemVersionString); " +
                        (request.requiresCoreHandshake ? "protocolo universal." : "enganche clásico."))

            let folder: URL = FileManager.default.temporaryDirectory.appendingPathComponent("OmniStationJIT", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let pairingURL: URL = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension("plist")
            try request.pairingData.write(to: pairingURL, options: [.atomic, .completeFileProtection])
            temporaryFiles.append(pairingURL)

            let library: URL = try FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let stikRoot: URL = library.appendingPathComponent("OmniStationStikJIT", isDirectory: true)
            try FileManager.default.createDirectory(at: stikRoot, withIntermediateDirectories: true)
            let ddiPaths: DDIPaths = DDIPaths.default(in: stikRoot)
            let configuration = StikJIT.Configuration(deviceAddress: "10.7.0.1", rsdPort: 49152)

            let preparation: (StikJIT.PreparationStage) -> Void = { stage in
                channel.log(Self.describe(stage))
            }
            if request.requiresCoreHandshake {
                guard let resource = Bundle.main.url(forResource: "armsx2-universal", withExtension: "js") else {
                    throw HelperError.invalidRequest("Falta el script de JIT del núcleo.")
                }
                let source: String = try String(contentsOf: resource, encoding: .utf8)
                let scriptURL: URL = folder.appendingPathComponent(UUID().uuidString + ".js")
                try ("const neostationProbeNonce = \(request.probeNonce);\n" + source).write(to: scriptURL, atomically: true, encoding: .utf8)
                temporaryFiles.append(scriptURL)
                let attachedMarker: String = "NEOSTATION_DEBUGGER_ATTACHED_V1 pid=\(request.targetPID) nonce=\(request.probeNonce)"
                try StikJIT.enableJIT(
                    targetPID: request.targetPID,
                    pairingFile: pairingURL,
                    ddiPaths: ddiPaths,
                    configuration: configuration,
                    script: .custom(scriptURL),
                    forceScript: true,
                    preparationProgress: preparation,
                    progress: { message in
                        channel.log(message)
                        if message == attachedMarker {
                            try? channel.send(event: "pid_attached", message: "Depurador enganchado a OmniStation.", targetPID: request.targetPID)
                        }
                    }
                )
            } else {
                try StikJIT.enableJITClassic(
                    targetPID: request.targetPID,
                    pairingFile: pairingURL,
                    ddiPaths: ddiPaths,
                    configuration: configuration,
                    preparationProgress: preparation,
                    progress: { message in channel.log(message) }
                )
            }
            try channel.send(event: "complete", message: "JIT listo; el ayudante se ha soltado.", success: true)
            channel.close()
            context.completeRequest(returningItems: nil, completionHandler: nil)
        } catch {
            try? reporter?.send(event: "complete", message: error.localizedDescription, success: false)
            reporter?.close()
            context.cancelRequest(withError: error)
        }
    }

    private static func describe(_ stage: StikJIT.PreparationStage) -> String {
        switch stage {
        case .checkingReachability:
            return "StikJIT: comprobando la VPN LocalDevVPN."
        case .checkingDDI:
            return "StikJIT: comprobando la imagen de desarrollador."
        case .downloadingDDI(let fraction, let status):
            return "StikJIT: descargando la imagen de desarrollador \(Int(fraction * 100))% — \(status)"
        case .mountingDDI(let fraction):
            return "StikJIT: montando la imagen de desarrollador \(Int(fraction * 100))%."
        case .verifyingDDI:
            return "StikJIT: verificando la imagen de desarrollador."
        case .ready:
            return "StikJIT: listo; enganchando el depurador a OmniStation."
        }
    }
}

/// Lo que manda OmniStation (JSON).
private struct HelperRequest {
    let targetPID: Int32
    let port: UInt16
    let token: String
    let pairingData: Data
    let probeNonce: UInt64
    let requiresCoreHandshake: Bool

    init(data: Data) throws {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (object["protocolVersion"] as? NSNumber)?.intValue == 1,
              let pid = object["targetPID"] as? NSNumber, pid.int32Value > 0,
              let port = object["port"] as? NSNumber, port.intValue > 0, port.intValue <= 65_535,
              let token = object["token"] as? String, !token.isEmpty,
              let pairingText = object["pairingData"] as? String,
              let pairing = Data(base64Encoded: pairingText),
              (128...(5 * 1024 * 1024)).contains(pairing.count),
              let nonce = object["probeNonce"] as? NSNumber,
              nonce.uint64Value > 0, nonce.uint64Value <= UInt64(UInt32.max) else {
            throw HelperError.invalidRequest("Petición de JIT no válida.")
        }
        // Archivo RPPairing: identificador y claves de 32 bytes.
        guard let plist = try PropertyListSerialization.propertyList(from: pairing, options: [], format: nil) as? [String: Any],
              let identifier = plist["identifier"] as? String, !identifier.isEmpty,
              let publicKey = plist["public_key"] as? Data, publicKey.count == 32,
              let privateKey = plist["private_key"] as? Data, privateKey.count == 32 else {
            throw HelperError.invalidRequest("El archivo de emparejamiento no es RPPairing: crea uno con iloader.")
        }
        targetPID = pid.int32Value
        self.port = port.uint16Value
        self.token = token
        pairingData = pairing
        probeNonce = nonce.uint64Value
        requiresCoreHandshake = object["requiresCoreHandshake"] as? Bool ?? false
    }
}

/// Canal con OmniStation por 127.0.0.1. Los avisos de registro nunca esperan: mientras se
/// atiende un JIT, OmniStation está detenida y no podría leerlos.
private final class HelperReporter {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "com.omnistation.dock.jit-helper-reporter")
    private let token: String
    private let sendLock = NSLock()
    private var started = false
    private var pendingLogs = 0

    init(port: UInt16, token: String) throws {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw HelperError.connection("Puerto de OmniStation no válido.")
        }
        self.token = token
        connection = NWConnection(host: NWEndpoint.Host("127.0.0.1"), port: endpointPort, using: .tcp)
    }

    func connect() throws {
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var failure: Error?
        var ready = false
        connection.stateUpdateHandler = { state in
            lock.lock()
            defer { lock.unlock() }
            switch state {
            case .ready:
                ready = true
                semaphore.signal()
            case .failed(let error), .waiting(let error):
                failure = error
                semaphore.signal()
            default:
                break
            }
        }
        connection.start(queue: queue)
        started = true
        guard semaphore.wait(timeout: .now() + 20) == .success else {
            throw HelperError.connection("No se pudo conectar con OmniStation.")
        }
        lock.lock()
        defer { lock.unlock() }
        if let failure { throw failure }
        if !ready { throw HelperError.connection("El canal con OmniStation no está listo.") }
    }

    func log(_ message: String) {
        guard let data = payload(event: "log", message: message, success: nil, targetPID: nil) else { return }
        sendLock.lock()
        guard pendingLogs < 32 else {
            sendLock.unlock()
            return
        }
        pendingLogs += 1
        connection.send(content: data, completion: .contentProcessed { [weak self] _ in
            guard let self else { return }
            self.sendLock.lock()
            self.pendingLogs -= 1
            self.sendLock.unlock()
        })
        sendLock.unlock()
    }

    /// Avisos de control: en orden y confirmados.
    func send(event: String, message: String, success: Bool? = nil, targetPID: Int32? = nil) throws {
        guard let data = payload(event: event, message: message, success: success, targetPID: targetPID) else { return }
        let semaphore = DispatchSemaphore(value: 0)
        var sendError: Error?
        sendLock.lock()
        connection.send(content: data, completion: .contentProcessed { error in
            sendError = error
            semaphore.signal()
        })
        sendLock.unlock()
        guard semaphore.wait(timeout: .now() + 20) == .success else {
            throw HelperError.connection("OmniStation no recibió el aviso.")
        }
        if let sendError { throw sendError }
    }

    private func payload(event: String, message: String, success: Bool?, targetPID: Int32?) -> Data? {
        var object: [String: Any] = ["token": token, "event": event, "message": String(message.prefix(4096))]
        if let success { object["success"] = success }
        if let targetPID { object["targetPID"] = NSNumber(value: targetPID) }
        guard var data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        data.append(0x0A)
        return data
    }

    func close() {
        if started { connection.cancel() }
        started = false
    }
}

private enum HelperError: LocalizedError {
    case invalidRequest(String)
    case connection(String)

    var errorDescription: String? {
        switch self {
        case .invalidRequest(let message), .connection(let message):
            return message
        }
    }
}
