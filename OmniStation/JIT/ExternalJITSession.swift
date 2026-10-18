import Foundation
import Darwin
import idevice

/// Una app instalada que se puede depurar (tiene `get-task-allow`): las que instala SideStore/AltStore.
struct DebuggableApp: Identifiable, Equatable {
    let bundleID: String
    let name: String
    var id: String { bundleID }
}

/// Conexión con el propio iPhone a través de la VPN LocalDevVPN (túnel RSD), con el archivo
/// de emparejamiento. Lanza otra app con el depurador, le activa el JIT y la suelta.
/// Sigue los mismos pasos que StikJIT (`JITSession`) añadiendo el lanzamiento por Bundle ID.
/// Todas las llamadas bloquean: se usan siempre desde la cola serie de `BuiltInJIT`.
final class ExternalJITSession {

    private struct Tunnel {
        var adapter: OpaquePointer?
        var handshake: OpaquePointer?
        func free() {
            if let handshake { rsd_handshake_free(handshake) }
            if let adapter { adapter_free(adapter) }
        }
    }

    private struct DebugSession {
        var remoteServer: OpaquePointer?
        var debugProxy: OpaquePointer?
        func free() {
            if let debugProxy { debug_proxy_free(debugProxy) }
            if let remoteServer { remote_server_free(remoteServer) }
        }
    }

    private let pairingFilePath: String
    private let configuration: StikJIT.Configuration

    init(pairingFilePath: String, configuration: StikJIT.Configuration = .default) {
        self.pairingFilePath = pairingFilePath
        self.configuration = configuration
    }

    // MARK: Lanzar con JIT

    /// Abre la app (en pausa), se conecta con el depurador, activa el JIT y la suelta.
    /// Con `script` (dispositivos con TXM), el script hace la conexión y prepara la memoria.
    /// Devuelve el PID de la app lanzada.
    func launchWithJIT(bundleID: String,
                       script: StikJIT.Script?,
                       progress: @escaping (String) -> Void) throws -> Int32 {
        let tunnel = try makeTunnel()
        defer { tunnel.free() }

        let session = try connectDebugSession(over: tunnel)
        defer { session.free() }

        guard let remoteServer = session.remoteServer, let debugProxy = session.debugProxy else {
            throw StikJITError.debugProxyUnavailable
        }

        let pid: Int32 = try launchSuspended(bundleID: bundleID, remoteServer: remoteServer)
        progress("Launched \(bundleID) (pid \(pid)).")

        debug_proxy_send_ack(debugProxy)
        debug_proxy_send_ack(debugProxy)
        _ = try? sendCommand("QStartNoAckMode", over: debugProxy)
        debug_proxy_set_ack_mode(debugProxy, 0)

        if let script {
            try ScriptRunner(targetPID: pid, debugProxy: debugProxy, script: script, progress: progress).run()
        } else {
            let hexPID: String = String(UInt32(bitPattern: pid), radix: 16)
            _ = try sendCommand("vAttach;" + hexPID, over: debugProxy)
            _ = try? sendCommand("D", over: debugProxy)
            progress("JIT enabled (debugger attached and detached).")
        }
        return pid
    }

    private func launchSuspended(bundleID: String, remoteServer: OpaquePointer) throws -> Int32 {
        var processControl: OpaquePointer?
        try IdeviceFFI.check("failed to open process control") {
            process_control_new(remoteServer, &processControl)
        }
        guard let processControl else { throw StikJITError.debugProxyUnavailable }
        defer { process_control_free(processControl) }

        var pid: UInt64 = 0
        try IdeviceFFI.check("failed to launch \(bundleID)") {
            bundleID.withCString { name in
                process_control_launch_app(processControl, name, nil, 0, nil, 0, true, true, &pid)
            }
        }
        guard pid > 0 else {
            throw StikJITError.device(code: -1, subCode: 0, message: "The app did not start (\(bundleID))")
        }
        return Int32(truncatingIfNeeded: pid)
    }

    // MARK: Apps instaladas

    /// Apps que se pueden depurar (las instaladas con SideStore/AltStore), por nombre.
    func debuggableApps() throws -> [DebuggableApp] {
        let tunnel = try makeTunnel()
        defer { tunnel.free() }

        var client: OpaquePointer?
        try IdeviceFFI.check("failed to connect to installation proxy") {
            installation_proxy_connect_rsd(tunnel.adapter, tunnel.handshake, &client)
        }
        guard let client else { throw StikJITError.debugProxyUnavailable }
        defer { installation_proxy_client_free(client) }

        var rawApps: UnsafeMutableRawPointer?
        var count: Int = 0
        try IdeviceFFI.check("failed to fetch installed apps") {
            installation_proxy_get_apps(client, nil, nil, 0, &rawApps, &count)
        }
        guard let rawApps, count > 0 else { return [] }

        let apps = rawApps.assumingMemoryBound(to: plist_t?.self)
        defer {
            for index in 0..<count {
                plist_free(apps[index])
            }
            idevice_data_free(rawApps.assumingMemoryBound(to: UInt8.self),
                              UInt(count * MemoryLayout<plist_t?>.stride))
        }

        var result: [DebuggableApp] = []
        for index in 0..<count {
            guard let dictionary = Self.dictionary(from: apps[index]),
                  Self.hasGetTaskAllow(dictionary),
                  let bundleID = dictionary["CFBundleIdentifier"] as? String, !bundleID.isEmpty else { continue }
            result.append(DebuggableApp(bundleID: bundleID, name: Self.appName(from: dictionary)))
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func dictionary(from plist: plist_t?) -> [String: Any]? {
        var binary: UnsafeMutablePointer<CChar>?
        var length: UInt32 = 0
        guard plist_to_bin(plist, &binary, &length) == PLIST_ERR_SUCCESS, let binary, length > 0 else { return nil }
        let data = Data(bytes: binary, count: Int(length))
        plist_mem_free(binary)
        guard let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else { return nil }
        return object as? [String: Any]
    }

    private static func appName(from dictionary: [String: Any]) -> String {
        if let name = dictionary["CFBundleDisplayName"] as? String, !name.isEmpty { return name }
        if let name = dictionary["CFBundleName"] as? String, !name.isEmpty { return name }
        return dictionary["CFBundleIdentifier"] as? String ?? "?"
    }

    private static func hasGetTaskAllow(_ dictionary: [String: Any]) -> Bool {
        guard let entitlements = dictionary["Entitlements"] as? [String: Any] else { return false }
        if let flag = entitlements["get-task-allow"] as? Bool { return flag }
        if let flag = entitlements["get-task-allow"] as? NSNumber { return flag.boolValue }
        return false
    }

    // MARK: Procesos en marcha

    /// ¿Sigue abierto el proceso con este PID?
    func isRunning(pid: Int32) throws -> Bool {
        let tunnel = try makeTunnel()
        defer { tunnel.free() }

        var service: OpaquePointer?
        try IdeviceFFI.check("failed to connect to app service") {
            app_service_connect_rsd(tunnel.adapter, tunnel.handshake, &service)
        }
        guard let service else { throw StikJITError.debugProxyUnavailable }
        defer { app_service_free(service) }

        var processes: UnsafeMutablePointer<ProcessTokenC>?
        var count: UInt = 0
        try IdeviceFFI.check("failed to list processes") {
            app_service_list_processes(service, &processes, &count)
        }
        guard let processes else { return false }
        defer { app_service_free_process_list(processes, count) }

        let wanted: UInt32 = UInt32(bitPattern: pid)
        for index in 0..<Int(count) where processes[index].pid == wanted {
            return true
        }
        return false
    }

    // MARK: Túnel y depurador (igual que StikJIT)

    private func openPairingFile() throws -> OpaquePointer {
        guard !pairingFilePath.isEmpty, FileManager.default.fileExists(atPath: pairingFilePath) else {
            throw StikJITError.pairingFile("not found at \(pairingFilePath)")
        }
        var handle: OpaquePointer?
        try IdeviceFFI.check("failed to read pairing file") {
            pairingFilePath.withCString { rp_pairing_file_read($0, &handle) }
        }
        guard let handle else { throw StikJITError.pairingFile("unreadable at \(pairingFilePath)") }
        return handle
    }

    private func makeTunnel() throws -> Tunnel {
        let pairing = try openPairingFile()
        defer { rp_pairing_file_free(pairing) }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = configuration.rsdPort.bigEndian
        _ = configuration.deviceAddress.withCString { inet_pton(AF_INET, $0, &address.sin_addr) }

        var tunnel = Tunnel()
        try IdeviceFFI.check("failed to create RSD tunnel") {
            "OmniStation".withCString { hostname in
                withUnsafePointer(to: &address) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        tunnel_create_rppairing(
                            sa, socklen_t(MemoryLayout<sockaddr_in>.stride),
                            hostname, pairing, nil, nil,
                            &tunnel.adapter, &tunnel.handshake)
                    }
                }
            }
        }
        guard tunnel.adapter != nil, tunnel.handshake != nil else {
            tunnel.free()
            throw StikJITError.device(code: -1, subCode: 0, message: "The RSD tunnel was created without valid handles")
        }
        return tunnel
    }

    private func connectDebugSession(over tunnel: Tunnel) throws -> DebugSession {
        var session = DebugSession()
        do {
            try IdeviceFFI.check("failed to connect remote server") {
                remote_server_connect_rsd(tunnel.adapter, tunnel.handshake, &session.remoteServer)
            }
            try IdeviceFFI.check("failed to connect debug proxy") {
                debug_proxy_connect_rsd(tunnel.adapter, tunnel.handshake, &session.debugProxy)
            }
        } catch {
            session.free()
            throw error
        }
        return session
    }

    @discardableResult
    private func sendCommand(_ command: String, over debugProxy: OpaquePointer) throws -> String? {
        guard let handle = command.withCString({ debugserver_command_new($0, nil, 0) }) else { return nil }
        defer { debugserver_command_free(handle) }
        var response: UnsafeMutablePointer<CChar>?
        try IdeviceFFI.check("debugserver command failed") {
            debug_proxy_send_command(debugProxy, handle, &response)
        }
        guard let response else { return nil }
        defer { idevice_string_free(response) }
        return String(cString: response)
    }
}
