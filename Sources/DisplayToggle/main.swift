import Foundation

// One binary, two faces: invoked as `displayctl` (or with arguments) it's the CLI;
// launching DisplayToggle.app with no arguments starts the menu bar app.
let arguments = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-psn_") }
let invokedName = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent

exit(MainActor.assumeIsolated { CLI.run(Array(arguments)) })
