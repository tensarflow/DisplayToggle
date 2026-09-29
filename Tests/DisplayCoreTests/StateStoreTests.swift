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
