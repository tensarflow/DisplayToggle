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
