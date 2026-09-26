import DeadboltCore
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.contains("--version") || arguments.first == "version" {
    print("Deadbolt \(Deadbolt.version)")
    exit(0)
}

guard let command = arguments.first else {
    printUsage()
    exit(0)
}

switch command {
case "devices":
    runDevices(Array(arguments.dropFirst()))
case "identify":
    runIdentify(Array(arguments.dropFirst()))
case "enroll":
    runEnroll(Array(arguments.dropFirst()))
case "keys":
    runKeys(Array(arguments.dropFirst()))
case "unenroll":
    runUnenroll(Array(arguments.dropFirst()))
case "lock":
    runLock()
case "unlock":
    runUnlock(Array(arguments.dropFirst()))
case "status":
    runStatus(Array(arguments.dropFirst()))
case "reset":
    runReset(Array(arguments.dropFirst()))
default:
    printUsage()
    exit(2)
}

func printUsage() {
    print("deadboltctl (Deadbolt \(Deadbolt.version))")
    print("usage: deadboltctl <command> [options]")
    print("  devices [--json] [--fake <fixture.json>]")
    print("  identify <selector> [--fake <fixture.json>]")
    print("  enroll <selector> [--label NAME] [--allow-weak] [--allow-internal] [--fake <fixture.json>]")
    print("  keys [--json]")
    print("  unenroll <selector-or-label>")
    print("  lock")
    print("  unlock [--fake <fixture.json>]")
    print("  status [--json] [--fake <fixture.json>]")
    print("  reset --force")
    print("environment: DEADBOLT_FAKE_DEVICES=<fixture.json>, DEADBOLT_STATE_DIR=<dir>")
}

func resolveSource(arguments: [String]) throws -> DeviceSource {
    if let index = arguments.firstIndex(of: "--fake") {
        let path: String
        if index + 1 < arguments.count {
            path = arguments[index + 1]
        } else {
            throw CLIError.missingFakePath
        }
        return try FixtureDeviceSource(contentsOf: URL(fileURLWithPath: path))
    }

    if let envPath = ProcessInfo.processInfo.environment["DEADBOLT_FAKE_DEVICES"],
       !envPath.isEmpty {
        return try FixtureDeviceSource(contentsOf: URL(fileURLWithPath: envPath))
    }

    return SystemDeviceSource()
}

func runDevices(_ arguments: [String]) {
    let json = arguments.contains("--json")
    do {
        let source = try resolveSource(arguments: arguments)
        let devices = try source.listDevices()
        if json {
            let records = devices.map(DeviceRecord.init(identity:))
            let data = try DeadboltJSON.encoder.encode(records)
            print(String(data: data, encoding: .utf8) ?? "")
        } else {
            for (index, device) in devices.enumerated() {
                let assessment = device.assessment
                let refused = assessment.refused ? " [refused]" : ""
                print("\(index + 1)\t\(assessment.tier.rawValue)\t\(device.displayName)\t\(assessment.reason)\(refused)")
            }
        }
    } catch {
        fputs("error: \(error)\n", stderr)
        exit(1)
    }
}

func runIdentify(_ arguments: [String]) {
    guard let selectorValue = extractSelector(arguments) else {
        fputs("error: identify requires a selector\n", stderr)
        exit(2)
    }

    do {
        let source = try resolveSource(arguments: arguments)
        let devices = try source.listDevices()
        guard let device = selectDevice(selectorValue, from: devices) else {
            fputs("error: no device matches selector '\(selectorValue)'\n", stderr)
            exit(1)
        }
        let assessment = device.assessment
        print("name: \(device.displayName)")
        print("tier: \(assessment.tier.rawValue)")
        print("reason: \(assessment.reason)")
        if assessment.refused {
            print("refused: true")
        }
    } catch {
        fputs("error: \(error)\n", stderr)
        exit(1)
    }
}

func runEnroll(_ arguments: [String]) {
    guard let selectorValue = extractSelector(arguments) else {
        fputs("error: enroll requires a selector\n", stderr)
        exit(2)
    }

    let allowWeak = arguments.contains("--allow-weak")
    let allowInternal = arguments.contains("--allow-internal")

    do {
        let source = try resolveSource(arguments: arguments)
        let devices = try source.listDevices()
        guard let device = selectDevice(selectorValue, from: devices) else {
            fputs("error: no device matches selector '\(selectorValue)'\n", stderr)
            exit(1)
        }
        try EnrollmentPolicy.validate(device, allowWeak: allowWeak, allowInternal: allowInternal)

        let label = value(for: "--label", in: arguments) ?? device.displayName
        let assessment = device.assessment
        let record = KeyRecord(
            fingerprint: device.fingerprint,
            tier: assessment.tier,
            label: label,
            createdAt: Date()
        )
        try KeyRegistry(directory: StateDirectory.resolve()).enroll(record)
        print("enrolled \(record.label) (tier \(record.tier.rawValue)) \(record.fingerprint)")
    } catch {
        fputs("error: \(error)\n", stderr)
        exit(1)
    }
}

func runKeys(_ arguments: [String]) {
    let json = arguments.contains("--json")
    do {
        let keys = try KeyRegistry(directory: StateDirectory.resolve()).load()
        if json {
            let data = try DeadboltJSON.encoder.encode(keys)
            print(String(data: data, encoding: .utf8) ?? "")
        } else {
            if keys.isEmpty {
                print("no keys enrolled")
            } else {
                let formatter = ISO8601DateFormatter()
                for (index, key) in keys.enumerated() {
                    print("\(index + 1)\t\(key.tier.rawValue)\t\(key.label)\t\(key.fingerprint)\t\(formatter.string(from: key.createdAt))")
                }
            }
        }
    } catch {
        fputs("error: \(error)\n", stderr)
        exit(1)
    }
}

func runUnenroll(_ arguments: [String]) {
    guard let selectorValue = extractSelector(arguments) else {
        fputs("error: unenroll requires a selector or label\n", stderr)
        exit(2)
    }
    do {
        let removed = try KeyRegistry(directory: StateDirectory.resolve()).unenroll(selectorValue)
        if removed == 0 {
            fputs("error: no enrolled key matches '\(selectorValue)'\n", stderr)
            exit(1)
        }
        print("unenrolled \(removed) key(s)")
    } catch {
        fputs("error: \(error)\n", stderr)
        exit(1)
    }
}

func runLock() {
    do {
        try LockStore(directory: StateDirectory.resolve()).write(.locked)
        print("locked")
    } catch {
        fputs("error: \(error)\n", stderr)
        exit(1)
    }
}

func runUnlock(_ arguments: [String]) {
    do {
        let source = try resolveSource(arguments: arguments)
        let devices = try source.listDevices()
        let keys = try KeyRegistry(directory: StateDirectory.resolve()).load()
        guard LockMachine.canUnlock(devices: devices, keys: keys) else {
            fputs("error: no enrolled key attached\n", stderr)
            exit(1)
        }
        try LockStore(directory: StateDirectory.resolve()).write(.unlocked)
        print("unlocked")
    } catch {
        fputs("error: \(error)\n", stderr)
        exit(1)
    }
}

func runStatus(_ arguments: [String]) {
    let json = arguments.contains("--json")
    do {
        let state = try LockStore(directory: StateDirectory.resolve()).read()
        let keys = try KeyRegistry(directory: StateDirectory.resolve()).load()
        let source = try resolveSource(arguments: arguments)
        let devices = try source.listDevices()
        let attached = LockMachine.attachedKey(devices: devices, keys: keys)

        if json {
            let report = StatusReport(state: state.rawValue, attachedKey: attached?.label)
            let data = try DeadboltJSON.encoder.encode(report)
            print(String(data: data, encoding: .utf8) ?? "")
        } else {
            print("state: \(state.rawValue)")
            print("attachedKey: \(attached?.label ?? "none")")
        }
    } catch {
        fputs("error: \(error)\n", stderr)
        exit(1)
    }
}

func runReset(_ arguments: [String]) {
    guard arguments.contains("--force") else {
        fputs("error: reset requires --force\n", stderr)
        exit(2)
    }
    do {
        try KeyRegistry(directory: StateDirectory.resolve()).removeAll()
        try LockStore(directory: StateDirectory.resolve()).remove()
        print("reset complete")
    } catch {
        fputs("error: \(error)\n", stderr)
        exit(1)
    }
}

private struct StatusReport: Encodable {
    let state: String
    let attachedKey: String?
}

func extractSelector(_ arguments: [String]) -> String? {
    let valueFlags: Set<String> = ["--fake", "--label"]
    var skipNext = false
    for argument in arguments {
        if valueFlags.contains(argument) {
            skipNext = true
            continue
        }
        if skipNext {
            skipNext = false
            continue
        }
        if argument.hasPrefix("--") { continue }
        return argument
    }
    return nil
}

func value(for flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
        return nil
    }
    return arguments[index + 1]
}

func selectDevice(_ selector: String, from devices: [USBDeviceIdentity]) -> USBDeviceIdentity? {
    if let index = Int(selector), (1...devices.count).contains(index) {
        return devices[index - 1]
    }

    let needle = selector.lowercased()
    let exact = devices.filter { device in
        candidateFields(device).contains { $0.lowercased() == needle }
    }
    if exact.count == 1 { return exact[0] }
    if exact.count > 1 { return nil }

    let substring = devices.filter { device in
        candidateFields(device).contains { $0.lowercased().contains(needle) }
    }
    return substring.count == 1 ? substring[0] : nil
}

func candidateFields(_ device: USBDeviceIdentity) -> [String] {
    [
        device.name,
        device.serialNumber,
        device.volumeUUID,
        device.containerID,
        device.vendorName,
        device.productName,
    ].compactMap { $0 }
}

enum CLIError: Error, CustomStringConvertible {
    case missingFakePath

    var description: String {
        switch self {
        case .missingFakePath:
            return "--fake requires a fixture path"
        }
    }
}
