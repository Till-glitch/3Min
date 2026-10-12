import XCTest
@testable import ThreeMinCore

final class TrainingTests: XCTestCase {
    func testDelayedTickAndDuplicateFinish() {
        var state = TrainingState()
        XCTAssertFalse(state.finishSet(at: 0))
        XCTAssertTrue(state.startSet(at: 10))
        XCTAssertFalse(state.startSet(at: 11))
        XCTAssertTrue(state.finishSet(at: 30))
        XCTAssertFalse(state.finishSet(at: 40))
        XCTAssertEqual(state.restDeadline, 210)
        XCTAssertEqual(state.remaining(at: 209.1), 1)
        XCTAssertFalse(state.tick(at: 209.9))
        XCTAssertTrue(state.tick(at: 240))
        XCTAssertEqual(state.phase, .restFinished)
        XCTAssertFalse(state.tick(at: 241))
    }
    func testStartCancelsRestAndRearms() {
        var state = TrainingState()
        _ = state.startSet(at: 0); _ = state.finishSet(at: 20)
        XCTAssertTrue(state.startSet(at: 25))
        XCTAssertNil(state.restDeadline)
        XCTAssertFalse(state.tick(at: 500))
        XCTAssertEqual(state.setNumber, 2)
        _ = state.finishSet(at: 510)
        XCTAssertEqual(state.restDeadline, 690)
    }
    func testDetectionNeedsValidContinuousWindows() {
        var gate = DetectionGate()
        XCTAssertFalse(gate.accepts(probability: 0.9, coverage: 1, time: 7, setStart: 0))
        XCTAssertFalse(gate.accepts(probability: 0.9, coverage: 1, time: 8, setStart: 0))
        XCTAssertFalse(gate.accepts(probability: 0.1, coverage: 1, time: 9, setStart: 0))
        XCTAssertFalse(gate.accepts(probability: 0.9, coverage: 1, time: 10, setStart: 0))
        XCTAssertFalse(gate.accepts(probability: 0.9, coverage: 1, time: 12, setStart: 0))
        XCTAssertFalse(gate.accepts(probability: 0.9, coverage: 1, time: 13, setStart: 0))
        XCTAssertTrue(gate.accepts(probability: 0.9, coverage: 1, time: 14, setStart: 0))
        gate.reset()
        XCTAssertFalse(gate.accepts(probability: 0.9, coverage: 0.2, time: 15, setStart: 0))
    }
    func testFeatureContractAndMissingHeart() {
        let points = (1...200).map { MotionPoint(t: Double($0)/25, acceleration: 0.1, rotation: 0.2) }
        let f = WindowFeatures.compute(motion: points, pulses: [], end: 8)
        XCTAssertEqual(f.count, 12)
        XCTAssertEqual(f[0], 0.1, accuracy: 1e-10)
        XCTAssertEqual(f[1], 0, accuracy: 1e-10)
        XCTAssertEqual(f[6], 0)
        XCTAssertEqual(f[8], 1)
        XCTAssertEqual(f[10], 1)
        XCTAssertEqual(f[11], 0.005, accuracy: 1e-10)
        let stale = WindowFeatures.compute(motion: [], pulses: [PulsePoint(t: 0, bpm: 100)], end: 11)
        XCTAssertEqual(stale[6], 0)
        XCTAssertEqual(stale[8], 1)
        XCTAssertEqual(stale[11], 1)
    }
}
