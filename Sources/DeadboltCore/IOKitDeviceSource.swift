import Foundation
import IOKit

/// Enumerates USB devices through IOKit's `IOUSBHostDevice` class, reading the
/// vendor/product id, serial number, container id, and vendor/product strings.
/// `locationID` is deliberately ignored: it changes with the port or hub the
/// device is plugged into.
public struct IOKitUSBDeviceSource {
    public init() {}

    public func listDevices() -> [USBDeviceIdentity] {
        var result: [USBDeviceIdentity] = []
        guard let matching = IOServiceMatching("IOUSBHostDevice") else { return result }

        var iterator: io_iterator_t = 0
        let status = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard status == KERN_SUCCESS else { return result }
        defer { IOObjectRelease(iterator) }

        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            if let identity = makeIdentity(service: service) {
                result.append(identity)
            }
            IOObjectRelease(service)
        }

        return result
    }

    private func makeIdentity(service: io_object_t) -> USBDeviceIdentity? {
        let vendorID = readNumber(service, key: "idVendor")
        let productID = readNumber(service, key: "idProduct")
        let serial = readString(service, key: "USB Serial Number")
        let containerID = readString(service, key: "kUSBContainerID")
        let vendorName = readString(service, key: "USB Vendor Name")
        let productName = readString(service, key: "USB Product Name")

        let hasIdentity = vendorID != nil || productID != nil
            || serial != nil || containerID != nil
        guard hasIdentity else { return nil }

        return USBDeviceIdentity(
            vendorID: vendorID,
            productID: productID,
            serialNumber: serial,
            volumeUUID: nil,
            containerID: containerID,
            vendorName: vendorName,
            productName: productName,
            isRemovable: true,
            name: productName ?? vendorName ?? serial,
            location: nil
        )
    }

    private func readProperty(_ service: io_object_t, key: String) -> CFTypeRef? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
    }

    private func readString(_ service: io_object_t, key: String) -> String? {
        guard let value = readProperty(service, key: key) else { return nil }
        return value as? String
    }

    private func readNumber(_ service: io_object_t, key: String) -> UInt32? {
        guard let value = readProperty(service, key: key) else { return nil }
        return (value as? NSNumber)?.uint32Value
    }
}
