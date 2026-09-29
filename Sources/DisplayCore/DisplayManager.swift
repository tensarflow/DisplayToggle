import AppKit
import CoreGraphics
import IOKit

/// Talks to the window server: lists displays and turns them off/on through SkyLight.
@MainActor
public final class DisplayManager {
    private let store: StateStore

    public init(store: StateStore = .default) {
        self.store = store
    }

    /// Connected displays first, then displays this tool turned off that are still off.
    public func allDisplays() -> [DisplayInfo] {
        let online = onlineDisplays()
        let remembered = store.load()
        let stillOff = DisplayLogic.pruneReconnected(remembered, onlineIDs: Set(online.map(\.id)))
        if stillOff.count != remembered.count { try? store.save(stillOff) }
        return DisplayLogic.merge(online: online, stillOff: stillOff)
    }

    public func turnOff(_ display: DisplayInfo) throws {
        let all = allDisplays()
        guard let current = all.first(where: { $0.id == display.id }), current.isOn else {
            throw DisplayError.alreadyOff(display.name)
        }
        if DisplayLogic.safety(turningOff: current.id, among: all) == .refuse {
            throw DisplayError.wouldLeaveNoDisplay(current.name)
        }
        try Self.setEnabled(current.id, false)

        var saved = current
        saved.isOn = false
        try store.save(store.load().filter { $0.id != current.id } + [saved])

        guard waitFor({ !self.onlineIDs().contains(current.id) }) else {
            throw DisplayError.didNotTakeEffect(current.name)
        }
    }

    public func turnOn(_ display: DisplayInfo) throws {
        if onlineIDs().contains(display.id) { throw DisplayError.alreadyOn(display.name) }
        try Self.setEnabled(display.id, true)
        guard waitFor({ self.onlineIDs().contains(display.id) }) else {
            throw DisplayError.didNotTakeEffect(display.name)
        }
        try store.save(store.load().filter { $0.id != display.id })
    }

    /// Turns on every display this tool turned off, reporting each one's error (if any).
    public func turnAllOn() -> [(display: DisplayInfo, error: Error?)] {
        allDisplays().filter { !$0.isOn }.map { display in
            do {
                try turnOn(display)
                return (display, nil)
            } catch {
                return (display, error)
            }
        }
    }

    // MARK: - Window server

    private func onlineIDs() -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    private func onlineDisplays() -> [DisplayInfo] {
        let panels = Self.physicalPanels()
        let screenNames = Self.screenNames()
        return onlineIDs().map { id in
            let key = PanelKey(vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id),
                               serial: CGDisplaySerialNumber(id))
            let mode = CGDisplayCopyDisplayMode(id)
            let panelName = panels[key].flatMap { $0.isEmpty ? nil : $0 }
            return DisplayInfo(
                id: id,
                name: screenNames[id] ?? panelName ?? "Display \(id)",
                vendor: key.vendor, model: key.model, serial: key.serial,
                width: mode?.width ?? Int(CGDisplayPixelsWide(id)),
                height: mode?.height ?? Int(CGDisplayPixelsHigh(id)),
                isMain: CGDisplayIsMain(id) != 0,
                isPhysical: CGDisplayIsBuiltin(id) != 0 || panels[key] != nil,
                isOn: true)
        }
    }

    /// Display changes land asynchronously; poll until `condition` holds or 3 s pass.
    private func waitFor(_ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if condition() { return true }
            let step = Date().addingTimeInterval(0.1)
            RunLoop.current.run(until: step)
            if Date() < step { Thread.sleep(until: step) }
        }
        return condition()
    }

    private static func screenNames() -> [CGDirectDisplayID: String] {
        var names: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                names[number.uint32Value] = screen.localizedName
            }
        }
        return names
    }

    // MARK: - Physical panels (IORegistry)

    private struct PanelKey: Hashable {
        let vendor: UInt32
        let model: UInt32
        let serial: UInt32
    }

    /// Real monitors show up under IOMobileFramebufferShim with their EDID identity;
    /// virtual screens (remote desktop, BetterDisplay dummies) don't.
    private static func physicalPanels() -> [PanelKey: String] {
        var panels: [PanelKey: String] = [:]
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOMobileFramebufferShim"),
                                           &iterator) == KERN_SUCCESS else { return panels }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            guard let attributes = IORegistryEntryCreateCFProperty(service, "DisplayAttributes" as CFString,
                                                                   kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any],
                  let product = attributes["ProductAttributes"] as? [String: Any],
                  let vendor = (product["LegacyManufacturerID"] as? NSNumber)?.uint32Value,
                  let model = (product["ProductID"] as? NSNumber)?.uint32Value
            else { continue }
            let serial = (product["SerialNumber"] as? NSNumber)?.uint32Value ?? 0
            panels[PanelKey(vendor: vendor, model: model, serial: serial)] = product["ProductName"] as? String ?? ""
        }
        return panels
    }

    // MARK: - SkyLight

    private typealias ConfigureDisplayEnabled = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError

    /// The private call behind BetterDisplay's "Disconnect". Looked up at runtime so a
    /// macOS release without it produces an error instead of a crash.
    private static let configureDisplayEnabled: ConfigureDisplayEnabled? = {
        let candidates = [
            ("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", "SLSConfigureDisplayEnabled"),
            ("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", "CGSConfigureDisplayEnabled"),
        ]
        for (path, symbol) in candidates {
            if let handle = dlopen(path, RTLD_LAZY), let pointer = dlsym(handle, symbol) {
                return unsafeBitCast(pointer, to: ConfigureDisplayEnabled.self)
            }
        }
        return nil
    }()

    private static func setEnabled(_ id: CGDirectDisplayID, _ enabled: Bool) throws {
        guard let configure = configureDisplayEnabled else { throw DisplayError.apiUnavailable }
        var config: CGDisplayConfigRef?
        var result = CGBeginDisplayConfiguration(&config)
        guard result == .success, let config else {
            throw DisplayError.cgError(step: "begin", code: result.rawValue)
        }
        result = configure(config, id, enabled)
        guard result == .success else {
            CGCancelDisplayConfiguration(config)
            throw DisplayError.cgError(step: enabled ? "enable" : "disable", code: result.rawValue)
        }
        result = CGCompleteDisplayConfiguration(config, .forSession)
        guard result == .success else {
            throw DisplayError.cgError(step: "complete", code: result.rawValue)
        }
    }
}
