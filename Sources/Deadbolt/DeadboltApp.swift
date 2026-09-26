import AppKit
import DeadboltCore
import SwiftUI

@main
struct DeadboltApp: App {
    @StateObject private var viewModel: DeadboltViewModel

    init() {
        let arguments = Array(CommandLine.arguments.dropFirst())

        if arguments.contains("--version") {
            print("Deadbolt \(Deadbolt.version)")
            exit(0)
        }

        if arguments.contains("--diagnostics") {
            let report = Diagnostics.report(
                stateDirectory: StateDirectory.resolve(),
                hostsPath: HostsPath.resolve(
                    explicit: nil,
                    environment: ProcessInfo.processInfo.environment
                ),
                deviceSource: AppEnvironment.resolveDeviceSource()
            )
            do {
                let data = try DeadboltJSON.encoder.encode(report)
                print(String(data: data, encoding: .utf8) ?? "")
                exit(0)
            } catch {
                fputs("error: \(error)\n", stderr)
                exit(1)
            }
        }

        _viewModel = StateObject(
            wrappedValue: DeadboltViewModel(controller: AppEnvironment.makeController())
        )
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu(viewModel: viewModel)
        } label: {
            Image(systemName: viewModel.snapshot.symbolName)
        }
    }
}

@MainActor
final class DeadboltViewModel: ObservableObject {
    @Published var snapshot: MenuBarModel
    private let controller: DeadboltController
    private var refreshTask: Task<Void, Never>?

    init(controller: DeadboltController) {
        self.controller = controller
        self.snapshot = controller.menuBarModel()
        self.refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                self.refresh()
            }
        }
    }

    func refresh() {
        snapshot = controller.menuBarModel()
    }

    func lock() {
        controller.lock()
        refresh()
    }

    func unlock() {
        controller.unlock()
        refresh()
    }
}

struct MenuBarMenu: View {
    @ObservedObject var viewModel: DeadboltViewModel

    var body: some View {
        let model = viewModel.snapshot
        VStack(alignment: .leading, spacing: 6) {
            Text("State: \(model.statusText)")
            Text("Key: \(model.attachedKeyDescription)")
            Divider()
            Button("Lock") { viewModel.lock() }
                .disabled(model.state == .locked)
            Button("Unlock") { viewModel.unlock() }
                .disabled(!model.unlockEnabled)
            Divider()
            if model.enrolledKeys.isEmpty {
                Text("No keys enrolled")
            } else {
                ForEach(model.enrolledKeys, id: \.fingerprint) { key in
                    Text("\(key.label) (\(key.tier.rawValue))")
                }
            }
            Divider()
            Button("Quit Deadbolt") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
    }
}
