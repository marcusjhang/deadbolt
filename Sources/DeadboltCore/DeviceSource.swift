import Foundation

/// A source of attached USB device identities. The real implementation
/// enumerates hardware; fixtures and tests inject a deterministic source so no
/// real hardware or system files are touched.
public protocol DeviceSource {
    func listDevices() throws -> [USBDeviceIdentity]
}

/// Combines the IOKit (USB) and DiskArbitration (storage) sources into one
/// hardware-backed source.
public struct SystemDeviceSource: DeviceSource {
    public init() {}

    public func listDevices() throws -> [USBDeviceIdentity] {
        var devices: [USBDeviceIdentity] = []
        devices.append(contentsOf: IOKitUSBDeviceSource().listDevices())
        devices.append(contentsOf: DiskArbitrationDeviceSource().listDevices())
        return devices
    }
}

/// Reads devices from a JSON fixture file: an array of `USBDeviceIdentity`
/// objects. Never touches real hardware.
public struct FixtureDeviceSource: DeviceSource {
    public let devices: [USBDeviceIdentity]

    public init(devices: [USBDeviceIdentity]) {
        self.devices = devices
    }

    public init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url)
        self.devices = try JSONDecoder().decode([USBDeviceIdentity].self, from: data)
    }

    public init(jsonData data: Data) throws {
        self.devices = try JSONDecoder().decode([USBDeviceIdentity].self, from: data)
    }

    public func listDevices() throws -> [USBDeviceIdentity] {
        devices
    }
}
