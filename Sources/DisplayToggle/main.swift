import AppKit

// One binary, two faces: invoked as `displayctl` (or with arguments) it's the CLI;
// launching DisplayToggle.app with no arguments starts the menu bar app.
let arguments = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-psn_") }
let invokedName = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent

MainActor.assumeIsolated {
    if invokedName == "displayctl" || !arguments.isEmpty {
        exit(CLI.run(Array(arguments)))
    }

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let menuBar = MenuBarController()
    withExtendedLifetime(menuBar) { app.run() }
}
