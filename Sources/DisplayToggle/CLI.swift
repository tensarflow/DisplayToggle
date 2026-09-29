import DisplayCore
import Foundation

@MainActor
enum CLI {
    static let usage = """
        usage: displayctl <command>

          list                 show displays and whether they are on
          off <id|name>        disconnect a display (it disappears from System Settings)
          on  <id|name>        reconnect a display turned off with this tool
          on  --all            reconnect every display turned off with this tool

        <name> can be any unique part of the name, case-insensitive.
        Displays come back on by themselves after a reboot, logout or cable replug.
        """

    static func run(_ arguments: [String]) -> Int32 {
        let manager = DisplayManager()
        let command = arguments.first ?? "help"
        do {
            switch (command, arguments.count) {
            case ("list", 1), ("ls", 1):
                printTable(manager.allDisplays())

            case ("off", 2):
                let all = manager.allDisplays()
                let display = try DisplayLogic.find(arguments[1], in: all)
                if display.isOn, DisplayLogic.safety(turningOff: display.id, among: all) == .onlyVirtualRemains {
                    warn("only virtual displays will remain. If the remote session ends, the Mac has no screen until "
                         + "you connect remotely again or restart it (a restart brings every monitor back).")
                }
                try manager.turnOff(display)
                print("\(display.name) is off.")

            case ("on", 2) where arguments[1] == "--all":
                let results = manager.turnAllOn()
                if results.isEmpty { print("Nothing to turn on.") }
                var failed = false
                for (display, error) in results {
                    if let error {
                        warn("\(display.name): \(error)")
                        failed = true
                    } else {
                        print("\(display.name) is on.")
                    }
                }
                return failed ? 1 : 0

            case ("on", 2):
                let display = try DisplayLogic.find(arguments[1], in: manager.allDisplays())
                try manager.turnOn(display)
                print("\(display.name) is on.")

            case ("help", _), ("-h", _), ("--help", _):
                print(usage)

            default:
                warn("unknown command: \(arguments.joined(separator: " "))\n\n\(usage)")
                return 64
            }
            return 0
        } catch {
            warn("\(error)")
            return 1
        }
    }

    private static func printTable(_ displays: [DisplayInfo]) {
        let header = ["ID", "NAME", "STATE", "KIND", "RESOLUTION", "MAIN"]
        let rows = displays.map { display in
            [String(display.id),
             display.name,
             display.isOn ? "on" : "off",
             display.isPhysical ? "physical" : "virtual",
             display.width > 0 ? "\(display.width)x\(display.height)" : "-",
             display.isMain ? "yes" : ""]
        }
        let table = [header] + rows
        let widths = header.indices.map { column in table.map { $0[column].count }.max() ?? 0 }
        for row in table {
            let cells = zip(row, widths).map { cell, width in cell.padding(toLength: width, withPad: " ", startingAt: 0) }
            print(cells.joined(separator: "  ").trimmingCharacters(in: .whitespaces))
        }
    }

    private static func warn(_ message: String) {
        FileHandle.standardError.write(Data("displayctl: \(message)\n".utf8))
    }
}
