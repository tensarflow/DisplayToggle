# DisplayToggle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A menu bar app + `displayctl` CLI (one binary) that disconnects monitors so they vanish from System Settings › Displays, and reconnects them.

**Architecture:** SwiftPM package. `DisplayCore` library holds a pure, unit-tested logic layer (`DisplayLogic`), a JSON state file (`StateStore`), and a `DisplayManager` that performs the side effects (CoreGraphics enumeration, IOKit physical-panel detection, private SkyLight `SLSConfigureDisplayEnabled` resolved via `dlsym`). The `DisplayToggle` executable picks CLI or menu bar mode from `argv`.

**Tech Stack:** Swift 6.4 toolchain (language mode 5 via tools-version 5.10), AppKit, CoreGraphics, IOKit, ServiceManagement, Swift Testing.

## Global Constraints

- Target: Apple Silicon, macOS 27; `platforms: [.macOS(.v14)]` floor.
- Disconnects use `CGCompleteDisplayConfiguration(config, .forSession)`; nothing re-disconnects at login.
- Never disconnect the last active display (`SafetyVerdict.refuse`).
- When only virtual displays would remain, warn (CLI: stderr; menu: confirm alert) but allow.
- State file: `~/Library/Application Support/DisplayToggle/disconnected.json`, updated only after a successful toggle.
- CLI name `displayctl`, app name `DisplayToggle`, bundle id `local.DisplayToggle`.

---

### Task 1: Package scaffold and pure logic

**Files:**
- Create: `Package.swift`, `.gitignore`
- Create: `Sources/DisplayCore/DisplayInfo.swift`
- Create: `Sources/DisplayCore/DisplayLogic.swift`
- Test: `Tests/DisplayCoreTests/DisplayLogicTests.swift`

**Interfaces:**
- Produces: `DisplayInfo` (Codable, Equatable; fields `id: CGDirectDisplayID, name: String, vendor/model/serial: UInt32, width/height: Int, isMain/isPhysical/isOn: Bool`; init with defaults `vendor/model/serial = 0, width/height = 0, isMain = false, isPhysical = true, isOn = true`), `SafetyVerdict { ok, onlyVirtualRemains, refuse }`, `DisplayError` (Error, Equatable, CustomStringConvertible), `DisplayLogic.safety(turningOff:among:) -> SafetyVerdict`, `DisplayLogic.find(_:in:) throws -> DisplayInfo`, `DisplayLogic.pruneReconnected(_:onlineIDs:) -> [DisplayInfo]`, `DisplayLogic.merge(online:stillOff:) -> [DisplayInfo]`.

- [ ] **Step 1: Write `Package.swift` and `.gitignore`**

```swift
// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DisplayToggle",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DisplayCore"),
        .executableTarget(name: "DisplayToggle", dependencies: ["DisplayCore"]),
        .testTarget(name: "DisplayCoreTests", dependencies: ["DisplayCore"]),
    ]
)
```

```
.build/
build/
```

- [ ] **Step 2: Write the failing tests** — `Tests/DisplayCoreTests/DisplayLogicTests.swift`

```swift
import CoreGraphics
import Testing
@testable import DisplayCore

private func display(_ id: CGDirectDisplayID, _ name: String, physical: Bool = true, on: Bool = true) -> DisplayInfo {
    DisplayInfo(id: id, name: name, isPhysical: physical, isOn: on)
}

@Suite struct SafetyTests {
    @Test func refusesToTurnOffTheLastDisplay() {
        #expect(DisplayLogic.safety(turningOff: 1, among: [display(1, "VG27A")]) == .refuse)
    }

    @Test func displaysAlreadyOffDoNotCountAsRemaining() {
        let all = [display(1, "VG27A"), display(3, "R27qe", on: false)]
        #expect(DisplayLogic.safety(turningOff: 1, among: all) == .refuse)
    }

    @Test func warnsWhenOnlyAVirtualDisplayWouldRemain() {
        let all = [display(7, "Remote", physical: false), display(1, "VG27A")]
        #expect(DisplayLogic.safety(turningOff: 1, among: all) == .onlyVirtualRemains)
    }

    @Test func okWhenAnotherPhysicalDisplayRemains() {
        let all = [display(7, "Remote", physical: false), display(1, "VG27A"), display(3, "R27qe")]
        #expect(DisplayLogic.safety(turningOff: 1, among: all) == .ok)
    }
}

@Suite struct FindTests {
    let all = [display(7, "Remote", physical: false), display(1, "VG27A"), display(3, "R27qe")]

    @Test func findsByID() throws {
        #expect(try DisplayLogic.find("3", in: all).name == "R27qe")
    }

    @Test func findsByCaseInsensitiveNameFragment() throws {
        #expect(try DisplayLogic.find("vg27", in: all).id == 1)
    }

    @Test func reportsAmbiguousNames() {
        #expect(throws: DisplayError.ambiguous("27", ["VG27A", "R27qe"])) {
            try DisplayLogic.find("27", in: all)
        }
    }

    @Test func prefersExactNameOverFragment() throws {
        let dells = [display(1, "DELL"), display(2, "DELL U2720Q")]
        #expect(try DisplayLogic.find("dell", in: dells).id == 1)
    }

    @Test func reportsUnknownDisplay() {
        #expect(throws: DisplayError.notFound("LG")) {
            try DisplayLogic.find("LG", in: all)
        }
    }
}

@Suite struct RememberedStateTests {
    @Test func dropsRememberedDisplaysThatAreOnlineAgain() {
        let remembered = [display(1, "VG27A", on: false), display(3, "R27qe", on: false)]
        #expect(DisplayLogic.pruneReconnected(remembered, onlineIDs: [3, 7]).map(\.id) == [1])
    }

    @Test func listsStillOffDisplaysAfterOnlineOnes() {
        let online = [display(7, "Remote", physical: false)]
        let stillOff = [DisplayInfo(id: 1, name: "VG27A", isMain: true, isOn: true)]
        let merged = DisplayLogic.merge(online: online, stillOff: stillOff)
        #expect(merged.map(\.id) == [7, 1])
        #expect(merged[1].isOn == false)
        #expect(merged[1].isMain == false)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test`
Expected: compile failure — `cannot find 'DisplayInfo' in scope` (the `DisplayCore` target has no sources yet).

- [ ] **Step 4: Write `Sources/DisplayCore/DisplayInfo.swift`**

```swift
import CoreGraphics

/// One monitor as the tool sees it: either connected now, or turned off by this tool.
public struct DisplayInfo: Codable, Equatable {
    public let id: CGDirectDisplayID
    public var name: String
    public var vendor: UInt32
    public var model: UInt32
    public var serial: UInt32
    public var width: Int
    public var height: Int
    public var isMain: Bool
    public var isPhysical: Bool
    public var isOn: Bool

    public init(id: CGDirectDisplayID, name: String, vendor: UInt32 = 0, model: UInt32 = 0, serial: UInt32 = 0,
                width: Int = 0, height: Int = 0, isMain: Bool = false, isPhysical: Bool = true, isOn: Bool = true) {
        self.id = id
        self.name = name
        self.vendor = vendor
        self.model = model
        self.serial = serial
        self.width = width
        self.height = height
        self.isMain = isMain
        self.isPhysical = isPhysical
        self.isOn = isOn
    }
}

public enum SafetyVerdict: Equatable {
    case ok
    /// Allowed, but only virtual displays (e.g. a remote-desktop screen) would be left.
    case onlyVirtualRemains
    /// Turning this display off would leave no active display at all.
    case refuse
}

public enum DisplayError: Error, Equatable, CustomStringConvertible {
    case apiUnavailable
    case cgError(step: String, code: Int32)
    case notFound(String)
    case ambiguous(String, [String])
    case wouldLeaveNoDisplay(String)
    case alreadyOff(String)
    case alreadyOn(String)
    case didNotTakeEffect(String)

    public var description: String {
        switch self {
        case .apiUnavailable:
            return "this macOS version doesn't provide SLSConfigureDisplayEnabled"
        case let .cgError(step, code):
            return "CoreGraphics \(step) failed (CGError \(code))"
        case let .notFound(query):
            return "no display matches '\(query)' (see `displayctl list`)"
        case let .ambiguous(query, names):
            return "'\(query)' matches several displays: \(names.joined(separator: ", ")); use the ID instead"
        case let .wouldLeaveNoDisplay(name):
            return "refusing to turn off \(name): it's the last active display"
        case let .alreadyOff(name):
            return "\(name) is already off"
        case let .alreadyOn(name):
            return "\(name) is already on"
        case let .didNotTakeEffect(name):
            return "macOS accepted the request, but \(name) did not change state"
        }
    }
}
```

- [ ] **Step 5: Write `Sources/DisplayCore/DisplayLogic.swift`**

```swift
import CoreGraphics
import Foundation

/// Decision logic with no window-server calls, so it can be unit tested.
public enum DisplayLogic {
    public static func safety(turningOff target: CGDirectDisplayID, among displays: [DisplayInfo]) -> SafetyVerdict {
        let remaining = displays.filter { $0.isOn && $0.id != target }
        if remaining.isEmpty { return .refuse }
        if remaining.allSatisfy({ !$0.isPhysical }) { return .onlyVirtualRemains }
        return .ok
    }

    /// Resolves a CLI argument: an exact display ID, else a unique case-insensitive name fragment.
    public static func find(_ query: String, in displays: [DisplayInfo]) throws -> DisplayInfo {
        if let id = CGDirectDisplayID(query), let match = displays.first(where: { $0.id == id }) {
            return match
        }
        let matches = displays.filter { $0.name.localizedCaseInsensitiveContains(query) }
        if matches.count == 1 { return matches[0] }
        if matches.isEmpty { throw DisplayError.notFound(query) }
        let exact = matches.filter { $0.name.caseInsensitiveCompare(query) == .orderedSame }
        if exact.count == 1 { return exact[0] }
        throw DisplayError.ambiguous(query, matches.map(\.name))
    }

    /// Remembered displays that are online again (replug, reboot, reconnected elsewhere) are forgotten.
    public static func pruneReconnected(_ remembered: [DisplayInfo], onlineIDs: Set<CGDirectDisplayID>) -> [DisplayInfo] {
        remembered.filter { !onlineIDs.contains($0.id) }
    }

    public static func merge(online: [DisplayInfo], stillOff: [DisplayInfo]) -> [DisplayInfo] {
        online + stillOff.map { display in
            var display = display
            display.isOn = false
            display.isMain = false
            return display
        }
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test`
Expected: all 11 tests in `SafetyTests`, `FindTests`, `RememberedStateTests` pass.

- [ ] **Step 7: Commit**

```bash
git add Package.swift .gitignore Sources/DisplayCore Tests
git commit -m "Add DisplayCore model and pure display logic"
```

---

### Task 2: State file

**Files:**
- Create: `Sources/DisplayCore/StateStore.swift`
- Test: `Tests/DisplayCoreTests/StateStoreTests.swift`

**Interfaces:**
- Consumes: `DisplayInfo` (Task 1).
- Produces: `StateStore(url: URL)`, `StateStore.default`, `load() -> [DisplayInfo]` (missing or corrupt file → `[]`), `save(_: [DisplayInfo]) throws`, `url: URL`.

- [ ] **Step 1: Write the failing tests** — `Tests/DisplayCoreTests/StateStoreTests.swift`

```swift
import Foundation
import Testing
@testable import DisplayCore

@Suite struct StateStoreTests {
    let store = StateStore(url: FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("disconnected.json"))

    @Test func missingFileMeansNothingRemembered() {
        #expect(store.load().isEmpty)
    }

    @Test func roundTripsDisplays() throws {
        let saved = [DisplayInfo(id: 1, name: "VG27A", vendor: 1715, model: 10018, serial: 16843009,
                                 width: 2560, height: 1440, isOn: false)]
        try store.save(saved)
        #expect(store.load() == saved)
    }

    @Test func corruptFileMeansNothingRemembered() throws {
        try store.save([])
        try Data("not json".utf8).write(to: store.url)
        #expect(store.load().isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test`
Expected: compile failure — `cannot find 'StateStore' in scope`.

- [ ] **Step 3: Write `Sources/DisplayCore/StateStore.swift`**

```swift
import Foundation

/// Remembers which displays this tool turned off, so they can be turned back on.
/// The CLI and the menu bar app share this file.
public struct StateStore {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static let `default` = StateStore(url: FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/DisplayToggle/disconnected.json"))

    public func load() -> [DisplayInfo] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([DisplayInfo].self, from: data)) ?? []
    }

    public func save(_ displays: [DisplayInfo]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(displays).write(to: url, options: .atomic)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: all 14 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/DisplayCore/StateStore.swift Tests/DisplayCoreTests/StateStoreTests.swift
git commit -m "Add JSON state file for disconnected displays"
```

---

### Task 3: DisplayManager and `displayctl` CLI

**Files:**
- Create: `Sources/DisplayCore/DisplayManager.swift`
- Create: `Sources/DisplayToggle/CLI.swift`
- Create: `Sources/DisplayToggle/main.swift` (CLI branch only; app branch added in Task 4)

**Interfaces:**
- Consumes: `DisplayInfo`, `DisplayError`, `DisplayLogic.*` (Task 1), `StateStore` (Task 2).
- Produces: `@MainActor DisplayManager(store: StateStore = .default)` with `allDisplays() -> [DisplayInfo]`, `turnOff(_: DisplayInfo) throws`, `turnOn(_: DisplayInfo) throws`, `turnAllOn() -> [(display: DisplayInfo, error: Error?)]`; `@MainActor enum CLI { static func run(_ arguments: [String]) -> Int32 }`.

There is no unit test for `DisplayManager` (it drives real hardware); it's verified by `displayctl list` against the attached monitors, and by the live round-trip in Task 5.

- [ ] **Step 1: Write `Sources/DisplayCore/DisplayManager.swift`**

```swift
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
```

- [ ] **Step 2: Write `Sources/DisplayToggle/CLI.swift`**

```swift
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
                    warn("only virtual displays will remain. If the remote session ends, the Mac has no screen "
                         + "until you connect remotely again or run `displayctl on --all` over SSH.")
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
```

- [ ] **Step 3: Write `Sources/DisplayToggle/main.swift` (CLI only for now)**

```swift
import Foundation

// One binary, two faces: invoked as `displayctl` (or with arguments) it's the CLI;
// launching DisplayToggle.app with no arguments starts the menu bar app.
let arguments = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-psn_") }
let invokedName = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent

exit(CLI.run(Array(arguments)))
```

- [ ] **Step 4: Build and run the tests**

Run: `swift build && swift test`
Expected: build succeeds with no errors; all 14 tests pass.

- [ ] **Step 5: Verify `list` against the real hardware (read-only)**

Run: `swift run DisplayToggle list`
Expected (IDs from this Mac):
```
ID  NAME    STATE  KIND      RESOLUTION  MAIN
7   Remote  on     virtual   1920x1200   yes
1   VG27A   on     physical  2560x1440
3   R27qe   on     physical  2560x1440
```

Also check the error paths, none of which touch hardware:
- `swift run DisplayToggle off 27` → `displayctl: '27' matches several displays: VG27A, R27qe; use the ID instead`, exit 1
- `swift run DisplayToggle on 1` → `displayctl: VG27A is already on`, exit 1
- `swift run DisplayToggle bogus` → usage, exit 64

- [ ] **Step 6: Commit**

```bash
git add Sources
git commit -m "Add DisplayManager (SkyLight toggle) and displayctl CLI"
```

---

### Task 4: Menu bar app, bundle, install

**Files:**
- Create: `Sources/DisplayToggle/MenuBar.swift`
- Modify: `Sources/DisplayToggle/main.swift` (add app branch)
- Create: `build.sh`, `install.sh`, `README.md`

**Interfaces:**
- Consumes: `DisplayManager`, `DisplayLogic.safety`, `DisplayInfo` (Tasks 1–3), `CLI.run` (Task 3).
- Produces: `MenuBarController` (`@MainActor`, `NSObject`, `NSMenuDelegate`), `build/DisplayToggle.app`, `~/Applications/DisplayToggle.app`, `~/.local/bin/displayctl`.

- [ ] **Step 1: Write `Sources/DisplayToggle/MenuBar.swift`**

```swift
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
```

- [ ] **Step 2: Replace `Sources/DisplayToggle/main.swift` with the two-mode entry point**

```swift
import AppKit

// One binary, two faces: invoked as `displayctl` (or with arguments) it's the CLI;
// launching DisplayToggle.app with no arguments starts the menu bar app.
let arguments = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-psn_") }
let invokedName = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent

if invokedName == "displayctl" || !arguments.isEmpty {
    exit(CLI.run(Array(arguments)))
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let menuBar = MenuBarController()
app.run()
```

- [ ] **Step 3: Write `build.sh`**

```bash
#!/bin/bash
# Builds build/DisplayToggle.app (menu bar app; the same binary is the displayctl CLI).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --product DisplayToggle
BIN="$(swift build -c release --show-bin-path)/DisplayToggle"
APP=build/DisplayToggle.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/DisplayToggle"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>DisplayToggle</string>
    <key>CFBundleIdentifier</key><string>local.DisplayToggle</string>
    <key>CFBundleName</key><string>DisplayToggle</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"
```

- [ ] **Step 4: Write `install.sh`**

```bash
#!/bin/bash
# Installs DisplayToggle.app into ~/Applications, links displayctl into ~/.local/bin, and starts it.
set -euo pipefail
cd "$(dirname "$0")"
./build.sh

APPS="$HOME/Applications"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
mkdir -p "$APPS" "$BIN_DIR"

pkill -x DisplayToggle 2>/dev/null || true
rm -rf "$APPS/DisplayToggle.app"
cp -R build/DisplayToggle.app "$APPS/"
ln -sf "$APPS/DisplayToggle.app/Contents/MacOS/DisplayToggle" "$BIN_DIR/displayctl"
open "$APPS/DisplayToggle.app"

echo "Installed $APPS/DisplayToggle.app and $BIN_DIR/displayctl"
case ":$PATH:" in *":$BIN_DIR:"*) ;; *) echo "Note: $BIN_DIR is not on your PATH" ;; esac
```

- [ ] **Step 5: Write `README.md`**

````markdown
# DisplayToggle

Turn monitors off in software so they disappear from System Settings › Displays,
and turn them back on later. The same trick as BetterDisplay's "Disconnect".

## Install

```bash
./install.sh
```

Puts `DisplayToggle.app` in `~/Applications`, links `displayctl` into `~/.local/bin`,
and starts the menu bar icon.

## Use

Menu bar: click the display icon; a checkmark means the monitor is on. Click to toggle.

Terminal (also works over SSH):

```bash
displayctl list
displayctl off VG27A      # or the ID from `list`
displayctl on VG27A
displayctl on --all
```

## Good to know

- A monitor turned off here comes back by itself after a reboot, logout, or cable replug.
- It refuses to turn off the last active display, and warns when only a virtual
  (remote-desktop) display would remain.
- Uses the private SkyLight call `SLSConfigureDisplayEnabled`; a future macOS may remove it,
  in which case the tool reports an error instead of doing anything.
- Remembered state: `~/Library/Application Support/DisplayToggle/disconnected.json`.
````

- [ ] **Step 6: Build the bundle and check both faces**

Run: `chmod +x build.sh install.sh && ./build.sh && build/DisplayToggle.app/Contents/MacOS/DisplayToggle list && swift test`
Expected: `Built build/DisplayToggle.app`, the same table as Task 3 Step 5, all 14 tests pass.

Run: `codesign -dv build/DisplayToggle.app 2>&1 | grep -E 'Identifier|Signature'`
Expected: `Identifier=local.DisplayToggle`, `Signature=adhoc`.

- [ ] **Step 7: Install and check the menu bar app starts**

Run: `./install.sh && sleep 2 && pgrep -x DisplayToggle && displayctl list`
Expected: a PID is printed and the table matches Task 3 Step 5.

- [ ] **Step 8: Commit**

```bash
git add Sources build.sh install.sh README.md
git commit -m "Add menu bar app, bundle build and install scripts"
```

---

### Task 5: Live round-trip (only with the user's go-ahead)

This blanks one physical monitor for a few seconds and moves its windows, so ask first.

- [ ] **Step 1: Turn one physical monitor off and back on**

Run: `displayctl off R27qe; displayctl list; system_profiler SPDisplaysDataType | grep -c 'Online: Yes'; displayctl on R27qe; displayctl list`
Expected:
- `R27qe is off.`
- The table shows `3  R27qe  off  physical ...`.
- `system_profiler` reports 2 online displays (it no longer knows about R27qe).
- `R27qe is on.`
- The table is back to all three `on`.
- `~/Library/Application Support/DisplayToggle/disconnected.json` contains `[]`.

- [ ] **Step 2: If the display did not leave the online list** (`didNotTakeEffect`), switch
  `.forSession` to `.permanently` in `DisplayManager.setEnabled`, rebuild, reinstall, and repeat Step 1.
