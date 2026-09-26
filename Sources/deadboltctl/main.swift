import DeadboltCore
import Foundation

let args = Array(CommandLine.arguments.dropFirst())

if args.contains("--version") || args.first == "version" {
    print("Deadbolt \(Deadbolt.version)")
    exit(0)
}

print("deadboltctl (Deadbolt \(Deadbolt.version))")
print("usage: deadboltctl <devices|enroll|keys|status|lock|unlock|enforce> [options]")
