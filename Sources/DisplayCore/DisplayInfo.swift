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
