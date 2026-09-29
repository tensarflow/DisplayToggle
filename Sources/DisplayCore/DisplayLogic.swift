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
