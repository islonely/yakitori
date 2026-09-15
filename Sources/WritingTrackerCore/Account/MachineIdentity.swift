import CryptoKit
import Foundation
import IOKit

/// A stable, one-way digest of the machine's hardware UUID, used only to keep
/// the free trial to one per Mac.
public protocol MachineIdentifying: Sendable {
    /// Returns a hex SHA-256 digest of the hardware UUID, or nil if unavailable.
    func machineDigest() -> String?
}

/// Reads `IOPlatformUUID` from IOKit and hashes it **on the device**.
///
/// The raw UUID never leaves the Mac: only this digest is sent to the server.
/// Licenses are never tied to it.
public struct IOKitMachineIdentity: MachineIdentifying {
    public init() {}

    public func machineDigest() -> String? {
        guard let uuid = Self.platformUUID() else { return nil }
        return Self.digest(of: uuid)
    }

    /// The device-computed digest sent to the server.
    ///
    /// A fixed namespace prefix avoids the digest matching a plain
    /// `SHA256(uuid)` computed elsewhere, and the UUID's own entropy makes the
    /// digest infeasible to reverse.
    static func digest(of uuid: String) -> String {
        let data = Data("Yakitori/machine/1:\(uuid)".utf8)
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func platformUUID() -> String? {
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

/// Test/preview stand-in. The value is returned verbatim (assumed to already be
/// a digest).
public struct StaticMachineIdentity: MachineIdentifying {
    private let value: String?

    public init(_ value: String?) {
        self.value = value
    }

    public func machineDigest() -> String? { value }
}
