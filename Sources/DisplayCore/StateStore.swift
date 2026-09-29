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
