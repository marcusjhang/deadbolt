import CryptoKit
import Foundation

/// An enrolled key: the stable fingerprint of a USB device, its identity tier,
/// a human-readable label, and when it was enrolled.
public struct KeyRecord: Codable, Equatable, Sendable {
    public let fingerprint: String
    public let tier: IdentityTier
    public let label: String
    public let createdAt: Date

    public init(fingerprint: String, tier: IdentityTier, label: String, createdAt: Date) {
        self.fingerprint = fingerprint
        self.tier = tier
        self.label = label
        self.createdAt = createdAt
    }
}

public extension USBDeviceIdentity {
    /// A stable fingerprint derived only from identity fields. `location`,
    /// `name`, and `isRemovable` are deliberately excluded so the fingerprint
    /// never changes across ports, hubs, replugs, or display-only edits.
    var fingerprint: String {
        let canonical: String
        switch assessment.tier {
        case .A:
            canonical = "A|\(vendorID.map(String.init) ?? "")|\(productID.map(String.init) ?? "")|\(usableSerial ?? "")"
        case .B:
            canonical = "B|\(volumeUUID ?? "")"
        case .C:
            canonical = "C|\(vendorID.map(String.init) ?? "")|\(productID.map(String.init) ?? "")|\(containerID ?? "")"
        case .D:
            canonical = "D|\(vendorID.map(String.init) ?? "")|\(productID.map(String.init) ?? "")|\(vendorName ?? "")|\(productName ?? "")"
        case .E:
            canonical = "E"
        }
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// Errors raised when a device is refused enrollment.
public enum EnrollmentError: Error, Equatable, CustomStringConvertible {
    case refusedIdentity
    case weakKeyRequiresAllowWeak
    case nonRemovableRequiresAllowInternal

    public var description: String {
        switch self {
        case .refusedIdentity:
            return "device identity is refused (Tier E)"
        case .weakKeyRequiresAllowWeak:
            return "weak key (Tier D) requires --allow-weak"
        case .nonRemovableRequiresAllowInternal:
            return "non-removable/internal device requires --allow-internal"
        }
    }
}

/// Enrollment rules applied before a key is persisted.
public enum EnrollmentPolicy {
    public static func validate(
        _ identity: USBDeviceIdentity,
        allowWeak: Bool,
        allowInternal: Bool
    ) throws {
        let assessment = identity.assessment
        if assessment.refused || assessment.tier == .E {
            throw EnrollmentError.refusedIdentity
        }
        if assessment.tier == .D && !allowWeak {
            throw EnrollmentError.weakKeyRequiresAllowWeak
        }
        if !identity.isRemovable && !allowInternal {
            throw EnrollmentError.nonRemovableRequiresAllowInternal
        }
    }
}

/// Shared JSON codecs so the CLI and stores agree on the on-disk format
/// (ISO-8601 timestamps, stable key ordering).
public enum DeadboltJSON {
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
