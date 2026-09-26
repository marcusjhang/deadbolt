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
default:
    printUsage()
    exit(2)
}

func printUsage() {
    print("deadboltctl (Deadbolt \(Deadbolt.version))")
    print("usage: deadboltctl <devices|identify> [options]")
    print("  devices [--json] [--fake <fixture.json>]")
    print("  identify <selector> [--fake <fixture.json>]")
    print("environment: DEADBOLT_FAKE_DEVICES=<fixture.json>")
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
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(records)
            if let text = String(data: data, encoding: .utf8) {
                print(text)
            }
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

func extractSelector(_ arguments: [String]) -> String? {
    var skipNext = false
    for argument in arguments {
        if argument == "--fake" {
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
