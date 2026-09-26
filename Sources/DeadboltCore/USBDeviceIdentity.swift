import Foundation

/// The strength tier a USB device identity resolves to, strongest first.
/// A = unique non-placeholder serial + VID/PID
/// B = volume UUID (hidden token-file key)
/// C = containerID + VID/PID
/// D = VID/PID + vendor/product strings (weak)
/// E = placeholder only (refused)
public enum IdentityTier: String, Codable, Sendable, CaseIterable, Comparable {
    case A, B, C, D, E

    public static func < (lhs: IdentityTier, rhs: IdentityTier) -> Bool {
        rank(lhs) < rank(rhs)
    }

    private static func rank(_ tier: IdentityTier) -> Int {
        switch tier {
        case .A: return 0
        case .B: return 1
        case .C: return 2
        case .D: return 3
        case .E: return 4
        }
    }
}

/// The outcome of evaluating a device identity: its tier, a human-readable
/// reason, and whether the device should be refused outright.
public struct IdentityAssessment: Equatable, Hashable, Codable, Sendable {
    public let tier: IdentityTier
    public let reason: String
    public let refused: Bool

    public init(tier: IdentityTier, reason: String, refused: Bool) {
        self.tier = tier
        self.reason = reason
        self.refused = refused
    }
}

/// A USB device identity. `location` is present for display/selection only and
/// is intentionally ignored by identity strength computation, because a
/// physical `locationID`/port changes with the port or hub the device is
/// plugged into.
public struct USBDeviceIdentity: Equatable, Hashable, Codable, Sendable {
    public var vendorID: UInt32?
    public var productID: UInt32?
    public var serialNumber: String?
    public var volumeUUID: String?
    public var containerID: String?
    public var vendorName: String?
    public var productName: String?
    public var isRemovable: Bool
    public var name: String?
    public var location: String?

    public init(
        vendorID: UInt32? = nil,
        productID: UInt32? = nil,
        serialNumber: String? = nil,
        volumeUUID: String? = nil,
        containerID: String? = nil,
        vendorName: String? = nil,
        productName: String? = nil,
        isRemovable: Bool = true,
        name: String? = nil,
        location: String? = nil
    ) {
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = serialNumber
        self.volumeUUID = volumeUUID
        self.containerID = containerID
        self.vendorName = vendorName
        self.productName = productName
        self.isRemovable = isRemovable
        self.name = name
        self.location = location
    }

    private enum CodingKeys: String, CodingKey {
        case vendorID, productID, serialNumber, volumeUUID, containerID
        case vendorName, productName, isRemovable, name, location
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        vendorID = try c.decodeIfPresent(UInt32.self, forKey: .vendorID)
        productID = try c.decodeIfPresent(UInt32.self, forKey: .productID)
        serialNumber = try c.decodeIfPresent(String.self, forKey: .serialNumber)
        volumeUUID = try c.decodeIfPresent(String.self, forKey: .volumeUUID)
        containerID = try c.decodeIfPresent(String.self, forKey: .containerID)
        vendorName = try c.decodeIfPresent(String.self, forKey: .vendorName)
        productName = try c.decodeIfPresent(String.self, forKey: .productName)
        isRemovable = try c.decodeIfPresent(Bool.self, forKey: .isRemovable) ?? true
        name = try c.decodeIfPresent(String.self, forKey: .name)
        location = try c.decodeIfPresent(String.self, forKey: .location)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(vendorID, forKey: .vendorID)
        try c.encodeIfPresent(productID, forKey: .productID)
        try c.encodeIfPresent(serialNumber, forKey: .serialNumber)
        try c.encodeIfPresent(volumeUUID, forKey: .volumeUUID)
        try c.encodeIfPresent(containerID, forKey: .containerID)
        try c.encodeIfPresent(vendorName, forKey: .vendorName)
        try c.encodeIfPresent(productName, forKey: .productName)
        try c.encode(isRemovable, forKey: .isRemovable)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(location, forKey: .location)
    }
}

/// Returns true when `serial` is a placeholder that must never contribute to
/// identity strength: empty, all zeros, a single repeated character, shorter
/// than 4 characters, or numerically/string equal to the vendor or product id.
public func isPlaceholderSerial(
    _ serial: String,
    vendorID: UInt32? = nil,
    productID: UInt32? = nil
) -> Bool {
    let s = serial.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.isEmpty { return true }
    if s.count < 4 { return true }
    if Set(s).count == 1 { return true }

    if let value = UInt32(s) {
        if let vid = vendorID, value == vid { return true }
        if let pid = productID, value == pid { return true }
    }

    if let vid = vendorID, matchesString(s, id: vid) { return true }
    if let pid = productID, matchesString(s, id: pid) { return true }

    return false
}

private func matchesString(_ serial: String, id: UInt32) -> Bool {
    let upper = serial.uppercased()
    if upper == String(id) { return true }
    if upper == String(id, radix: 16).uppercased() { return true }
    return false
}

public extension USBDeviceIdentity {
    /// Compute the device's identity strength tier, strongest match first.
    /// `location` is deliberately never consulted.
    var assessment: IdentityAssessment {
        let serial = usableSerial

        if let s = serial, vendorID != nil, productID != nil {
            return IdentityAssessment(
                tier: .A,
                reason: "unique non-placeholder serial with vendor/product id",
                refused: false
            )
        }

        if let uuid = volumeUUID, !uuid.isEmpty {
            return IdentityAssessment(
                tier: .B,
                reason: "volume UUID (hidden token-file key)",
                refused: false
            )
        }

        if let cid = containerID, !cid.isEmpty, vendorID != nil, productID != nil {
            return IdentityAssessment(
                tier: .C,
                reason: "container id with vendor/product id",
                refused: false
            )
        }

        if vendorID != nil, productID != nil,
           hasNonEmpty(vendorName) || hasNonEmpty(productName) {
            return IdentityAssessment(
                tier: .D,
                reason: "vendor/product id with vendor/product strings (weak)",
                refused: false
            )
        }

        return IdentityAssessment(
            tier: .E,
            reason: "placeholder or insufficient identity — refused",
            refused: true
        )
    }

    var tier: IdentityTier { assessment.tier }

    /// The serial only when it is a usable, non-placeholder identifier.
    var usableSerial: String? {
        guard let s = serialNumber else { return nil }
        return isPlaceholderSerial(s, vendorID: vendorID, productID: productID) ? nil : s
    }

    var displayName: String {
        if let n = name, !n.isEmpty { return n }
        if let p = productName, !p.isEmpty { return p }
        if let v = vendorName, !v.isEmpty { return v }
        if let s = serialNumber, !s.isEmpty { return "serial \(s)" }
        if let u = volumeUUID { return "volume \(u)" }
        if let c = containerID { return "container \(c)" }
        return "unknown device"
    }

    private func hasNonEmpty(_ value: String?) -> Bool {
        guard let v = value else { return false }
        return !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// A device paired with its computed assessment, used for machine-readable
/// listing output.
public struct DeviceRecord: Codable, Sendable, Equatable {
    public let identity: USBDeviceIdentity
    public let tier: IdentityTier
    public let reason: String

    public init(identity: USBDeviceIdentity) {
        self.identity = identity
        let assessment = identity.assessment
        self.tier = assessment.tier
        self.reason = assessment.reason
    }
}
