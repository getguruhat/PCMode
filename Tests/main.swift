import Foundation
func XCTAssertTrue(_ value: Bool) { precondition(value) }
func XCTAssertFalse(_ value: Bool) { precondition(!value) }

final class PressGateTests {
    func testMultiplePathsAndLongHoldFireOnce() {
        var gate = PressGate()
        XCTAssertTrue(gate.receive(path: "HID", down: true, repeating: false, now: 1))
        XCTAssertFalse(gate.receive(path: "media", down: true, repeating: false, now: 1.01))
        XCTAssertFalse(gate.receive(path: "F7", down: true, repeating: false, now: 1.02))
        XCTAssertFalse(gate.receive(path: "HID", down: true, repeating: false, now: 2))
        XCTAssertFalse(gate.receive(path: "media", down: true, repeating: true, now: 3))
        for path in ["HID", "media", "F7"] { XCTAssertFalse(gate.receive(path: path, down: false, repeating: false, now: 4)) }
        XCTAssertTrue(gate.receive(path: "media", down: true, repeating: false, now: 4.5))
    }
    func testLateDuplicateAfterReleaseAndOrphanRepeat() {
        var gate = PressGate()
        XCTAssertTrue(gate.receive(path: "HID", down: true, repeating: false, now: 1))
        XCTAssertFalse(gate.receive(path: "HID", down: false, repeating: false, now: 1.01))
        XCTAssertFalse(gate.receive(path: "media", down: true, repeating: false, now: 1.1))
        XCTAssertFalse(gate.receive(path: "media", down: false, repeating: false, now: 1.2))
        XCTAssertFalse(gate.receive(path: "F7", down: true, repeating: true, now: 2))
    }
}

let tests = PressGateTests()
tests.testMultiplePathsAndLongHoldFireOnce()
tests.testLateDuplicateAfterReleaseAndOrphanRepeat()
print("PASS: multiple paths, long hold, release/re-arm, late duplicate, orphan repeat")

var cut = CutState()
XCTAssertFalse(cut.consume(changeCount: 1))
_ = cut.begin(changeCount: 1)
cut.finish(changeCount: 2, hasFiles: true)
XCTAssertTrue(cut.consume(changeCount: 2))
XCTAssertFalse(cut.consume(changeCount: 2))
_ = cut.begin(changeCount: 2)
cut.finish(changeCount: 3, hasFiles: true)
XCTAssertFalse(cut.consume(changeCount: 4))
_ = cut.begin(changeCount: 4)
cut.finish(changeCount: 5, hasFiles: false)
XCTAssertFalse(cut.consume(changeCount: 5))
let oldGeneration = cut.begin(changeCount: 5)
cut.cancel()
XCTAssertTrue(cut.generation != oldGeneration)
cut.finish(changeCount: 6, hasFiles: true)
XCTAssertFalse(cut.consume(changeCount: 6))
_ = cut.begin(changeCount: 6)
XCTAssertFalse(cut.consume(changeCount: 6))
print("PASS: cut once, clipboard replacement, non-file copy, cancellation, pending copy")

// Each physical code belongs to exactly one selectable action.
let functionKeys = DeleteKey.allCases.compactMap(\.keyCode)
precondition(functionKeys.count == 12 && Set(functionKeys).count == 12)
let mediaKeys = DeleteKey.allCases.flatMap { Array($0.mediaCodes) }
precondition(Set(mediaKeys).count == mediaKeys.count)
let usages = DeleteKey.allCases.flatMap { Array($0.consumerUsages) }
precondition(Set(usages).count == usages.count)
precondition(DeleteKey.rewind.mediaCodes == [18, 20])
precondition(DeleteKey.playPause.mediaCodes == [16])
precondition(DeleteKey.forward.mediaCodes == [17, 19])
precondition(DeleteKey.volumeUp.mediaCodes == [0])
precondition(DeleteKey.volumeDown.mediaCodes == [1])
precondition(DeleteKey.mute.mediaCodes == [7])
for key in DeleteKey.allCases { precondition(DeleteKey(rawValue: key.rawValue) == key) }
print("PASS: all 12 function keys, distinct media/HID mappings, settings key round trips")

precondition(SwitcherNavigation.index(steps: 1, count: 4) == 1)
precondition(SwitcherNavigation.index(steps: -1, count: 4) == 3)
precondition(SwitcherNavigation.index(steps: 5, count: 4) == 1)
precondition(SwitcherNavigation.index(steps: -5, count: 4) == 3)
precondition(SwitcherNavigation.index(steps: 99, count: 0) == 0)
precondition(SwitcherNavigation.index(steps: 99, count: 1) == 0)
print("PASS: switcher forward/reverse wrapping, empty list, single target")

precondition(UsageFormat.cpu(0) == "0%")
precondition(UsageFormat.cpu(0.3) == "<1%")
precondition(UsageFormat.cpu(42.6) == "43%")
precondition(UsageFormat.cpu(250) == "250%")
precondition(UsageFormat.memory(340 * 1_048_576) == "340 MB")
precondition(UsageFormat.memory(1_288_490_189) == "1.2 GB")
precondition(UsageFormat.memory(999 * 1_048_576 + 800_000) == "1.0 GB")
precondition(UsageFormat.cpuLevel(39) == .normal)
precondition(UsageFormat.cpuLevel(40) == .high)
precondition(UsageFormat.cpuLevel(90) == .critical)
precondition(UsageFormat.memoryLevel(8 << 30, pressure: .normal) == .normal)
precondition(UsageFormat.memoryLevel(512 << 20, pressure: .critical) == .normal)
precondition(UsageFormat.memoryLevel(2 << 30, pressure: .warning) == .high)
precondition(UsageFormat.memoryLevel(2 << 30, pressure: .critical) == .critical)
print("PASS: usage formatting, CPU thresholds, RAM flagged only under memory pressure")
