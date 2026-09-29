import AppKit
import DisplayCore
import ServiceManagement

/// Menu bar icon with one checkable item per display. The menu is rebuilt every time it
/// opens, so changes made with `displayctl` show up here too.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let manager = DisplayManager()

    override init() {
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "display.2", accessibilityDescription: "DisplayToggle")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let displays = manager.allDisplays()

        menu.addItem(.sectionHeader(title: "Displays"))
        for display in displays {
            let item = menuItem(title(for: display), #selector(toggle(_:)))
            item.state = display.isOn ? .on : .off
            item.representedObject = display
            menu.addItem(item)
        }

        if displays.contains(where: { !$0.isOn }) {
            menu.addItem(.separator())
            menu.addItem(menuItem("Turn All Back On", #selector(turnAllOn)))
        }

        menu.addItem(.separator())
        let launchAtLogin = menuItem("Launch at Login", #selector(toggleLaunchAtLogin))
        launchAtLogin.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchAtLogin)
        menu.addItem(menuItem("Quit DisplayToggle", #selector(quit), key: "q"))
    }

    private func title(for display: DisplayInfo) -> String {
        let size = display.width > 0 ? "  \(display.width)×\(display.height)" : ""
        return display.name + size + (display.isPhysical ? "" : "  (virtual)")
    }

    @objc private func toggle(_ sender: NSMenuItem) {
        guard let display = sender.representedObject as? DisplayInfo else { return }
        do {
            if display.isOn {
                let verdict = DisplayLogic.safety(turningOff: display.id, among: manager.allDisplays())
                if verdict == .onlyVirtualRemains, !confirmOnlyVirtualRemains(display) { return }
                try manager.turnOff(display)
            } else {
                try manager.turnOn(display)
            }
        } catch {
            show("\(error)")
        }
    }

    @objc private func turnAllOn() {
        let failures = manager.turnAllOn().compactMap { result in
            result.error.map { "\(result.display.name): \($0)" }
        }
        if !failures.isEmpty { show(failures.joined(separator: "\n")) }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            show("Couldn't change Launch at Login: \(error.localizedDescription)")
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func confirmOnlyVirtualRemains(_ display: DisplayInfo) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Turn off \(display.name)?"
        alert.informativeText = "Only virtual displays will remain. If your remote session ends, the Mac will "
            + "have no screen until you connect remotely again or run `displayctl on --all` over SSH."
        alert.addButton(withTitle: "Turn Off")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func show(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "DisplayToggle"
        alert.informativeText = message
        NSApp.activate()
        alert.runModal()
    }

    private func menuItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }
}
