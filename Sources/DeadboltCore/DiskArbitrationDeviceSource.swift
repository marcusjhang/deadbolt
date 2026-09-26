import Foundation
import DiskArbitration

/// Enumerates attached storage devices through DiskArbitration, reading the
/// volume UUID and marking non-removable/internal disks so they can be
/// excluded from key enrollment. Runs the current run loop briefly so the
/// disk-appeared callbacks can fire.
public struct DiskArbitrationDeviceSource {
    public init() {}

    public func listDevices() -> [USBDeviceIdentity] {
        guard let session = DASessionCreate(kCFAllocatorDefault) else { return [] }

        let collector = DiskCollector()

        let callback: DADiskAppearedCallback = { disk, context in
            guard let context = context else { return }
            let collector = Unmanaged<DiskCollector>.fromOpaque(context).takeUnretainedValue()
            if let identity = makeDiskIdentity(disk) {
                collector.devices.append(identity)
            }
        }

        let runLoop: CFRunLoop = CFRunLoopGetCurrent()
        let modeString = "kCFRunLoopDefaultMode" as CFString
        let runLoopMode = CFRunLoopMode(rawValue: modeString)

        DARegisterDiskAppearedCallback(
            session,
            nil,
            callback,
            Unmanaged.passUnretained(collector).toOpaque()
        )
        DASessionScheduleWithRunLoop(session, runLoop, modeString)

        let deadline = Date().addingTimeInterval(0.3)
        while Date() < deadline {
            CFRunLoopRunInMode(runLoopMode, 0.05, true)
        }

        DASessionUnscheduleFromRunLoop(session, runLoop, modeString)

        return collector.devices
    }
}

private final class DiskCollector {
    var devices: [USBDeviceIdentity] = []
}

private func makeDiskIdentity(_ disk: DADisk) -> USBDeviceIdentity? {
    guard let description = DADiskCopyDescription(disk) else { return nil }
    let dict = description as NSDictionary

    let volumeUUID = volumeUUIDString(from: dict)

    let removable = (dict[kDADiskDescriptionMediaRemovableKey as String] as? NSNumber)?.boolValue ?? false
    let internalDisk = (dict[kDADiskDescriptionDeviceInternalKey as String] as? NSNumber)?.boolValue ?? false
    let deviceProtocol = dict[kDADiskDescriptionDeviceProtocolKey as String] as? String
    let isRemovable = isRemovableStorage(
        mediaRemovable: removable,
        deviceInternal: internalDisk,
        deviceProtocol: deviceProtocol
    )

    let vendorName = dict[kDADiskDescriptionDeviceVendorKey as String] as? String
    let productName = dict[kDADiskDescriptionDeviceModelKey as String] as? String

    let hasIdentity = volumeUUID != nil || vendorName != nil || productName != nil
    guard hasIdentity else { return nil }

    return USBDeviceIdentity(
        vendorID: nil,
        productID: nil,
        serialNumber: nil,
        volumeUUID: volumeUUID,
        containerID: nil,
        vendorName: vendorName,
        productName: productName,
        isRemovable: isRemovable,
        name: productName ?? vendorName ?? volumeUUID,
        location: nil
    )
}

/// A storage device is a removable candidate only when its media is removable,
/// it is not an internal/fixed disk, and it is not a synthesized disk image
/// (e.g. a mounted `.dmg`, which reports a synthesized/virtual protocol).
/// Pure so the rule is unit-testable without hardware.
public func isRemovableStorage(
    mediaRemovable: Bool,
    deviceInternal: Bool,
    deviceProtocol: String?
) -> Bool {
    if deviceInternal { return false }
    if !mediaRemovable { return false }
    if let proto = deviceProtocol?.lowercased(),
       isSynthesizedProtocol(proto) {
        return false
    }
    return true
}

private func isSynthesizedProtocol(_ proto: String) -> Bool {
    let trimmed = proto.trimmingCharacters(in: .whitespacesAndNewlines)
    switch trimmed {
    case "dmg", "disk image", "virtual", "virtual disk":
        return true
    default:
        return false
    }
}

private func volumeUUIDString(from dict: NSDictionary) -> String? {
    guard let value = dict[kDADiskDescriptionVolumeUUIDKey as String] else { return nil }
    if CFGetTypeID(value as CFTypeRef) == CFUUIDGetTypeID() {
        let uuid = unsafeBitCast(value as AnyObject, to: CFUUID.self)
        return CFUUIDCreateString(kCFAllocatorDefault, uuid) as String
    }
    if let string = value as? String {
        return string
    }
    return nil
}
