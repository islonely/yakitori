import Foundation
import IOKit

/// A stable, machine-specific identifier, used only to keep the free trial to
/// one per Mac.
public protocol MachineIdentifying: Sendable {
    /// Returns the machine's hardware UUID, or nil if it cannot be read.
    func machineIdentifier() -> String?
}

/// Reads `IOPlatformUUID` from IOKit (the same value `ioreg` reports).
///
/// Used solely for trial anti-abuse: the raw value is sent over TLS and the
/// server stores only an HMAC of it. Licenses are never tied to it.
public struct IOKitMachineIdentity: MachineIdentifying {
    public init() {}

    public func machineIdentifier() -> String? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        guard let property = IORegistryEntryCreateCFProperty(
            service,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0
        ), let value = property.takeRetainedValue() as? String, !value.isEmpty else {
            return nil
        }
        return value
    }
}

/// Test/preview stand-in.
public struct StaticMachineIdentity: MachineIdentifying {
    private let value: String?

    public init(_ value: String?) {
        self.value = value
    }

    public func machineIdentifier() -> String? { value }
}
