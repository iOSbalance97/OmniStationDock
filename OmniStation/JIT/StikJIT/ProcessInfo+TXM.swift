// Basado en StikJIT (MPL-2.0). Los umbrales de modelo son los que usa StikDebug.
// StikJIT lee el árbol de IOKit para saber si hay TXM; aquí se deduce por el modelo y la
// versión de iOS (como hace StikDebug) para no depender de las cabeceras privadas de IOKit.
import Foundation
import Darwin

enum TXMPresence {
    case present
    case absent
    case unknown

    init(isPresent: Bool?) {
        guard let isPresent else {
            self = .unknown
            return
        }
        self = isPresent ? .present : .absent
    }

    var isPresent: Bool? {
        switch self {
        case .present: return true
        case .absent: return false
        case .unknown: return nil
        }
    }
}

extension ProcessInfo {
    var txmPresence: TXMPresence {
        guard let hardware = Self.stikHardwareIdentifier() else { return .unknown }
        if #available(iOS 27.0, *) {
            let exempt: Bool = hardware == "iPad8,11" || hardware == "iPad8,12"
            return exempt ? .absent : .present
        }
        if #available(iOS 26.0, *) {
            guard let version = Self.stikDeviceVersion(from: hardware) else { return .unknown }
            let first: Double = hardware.hasPrefix("iPad") ? 14.5 : 14.2
            return version >= first ? .present : .absent
        }
        return .absent
    }

    /// Identificador del modelo, por ejemplo "iPhone16,2".
    static func stikHardwareIdentifier() -> String? {
        var info = utsname()
        guard uname(&info) == 0 else { return nil }
        let capacity: Int = MemoryLayout.size(ofValue: info.machine)
        let machine: String = withUnsafePointer(to: &info.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
        }
        guard machine.hasPrefix("iPhone") || machine.hasPrefix("iPad") else { return nil }
        return machine
    }

    /// "iPhone16,2" → 16.2 (para comparar generaciones).
    static func stikDeviceVersion(from identifier: String) -> Double? {
        let digits: String = String(identifier.drop(while: { !$0.isNumber }))
        let parts: [Substring] = digits.split(separator: ",")
        guard parts.count == 2, let major = Double(parts[0]), let minorValue = Int(parts[1]) else { return nil }
        let divisor: Double = pow(10.0, Double(String(minorValue).count))
        return major + Double(minorValue) / divisor
    }
}
