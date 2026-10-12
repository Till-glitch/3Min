import Foundation

enum TrainingPhase: String, Codable {
    case ready, setRunning, rest, restFinished
    var title: String {
        switch self {
        case .ready: return "Bereit"
        case .setRunning: return "Satz läuft"
        case .rest: return "Pause"
        case .restFinished: return "Pause beendet"
        }
    }
}

// All deadlines are in seconds from session start on the monotonic clock.
struct TrainingState {
    private(set) var phase: TrainingPhase = .ready
    private(set) var setStarted: Double?
    private(set) var restDeadline: Double?
    private(set) var setNumber = 0
    let restSeconds: Double = 180

    mutating func startSet(at time: Double) -> Bool {
        guard phase != .setRunning else { return false }
        setNumber += 1
        phase = .setRunning
        setStarted = time
        restDeadline = nil
        return true
    }
    mutating func finishSet(at time: Double) -> Bool {
        guard phase == .setRunning else { return false }
        phase = .rest
        restDeadline = time + restSeconds
        return true
    }
    // Returns true exactly once for each expired rest, even after delayed callbacks.
    mutating func tick(at time: Double) -> Bool {
        guard phase == .rest, let end = restDeadline, time >= end else { return false }
        phase = .restFinished
        restDeadline = nil
        return true
    }
    func remaining(at time: Double) -> Int {
        guard let end = restDeadline else { return 0 }
        return max(0, Int(ceil(end - time)))
    }
}

struct DetectionGate {
    private var firstPositive: Double?
    private var lastTime: Double?
    mutating func reset() { firstPositive = nil; lastTime = nil }
    mutating func accepts(probability: Double, coverage: Double, time: Double, setStart: Double?) -> Bool {
        defer { lastTime = time }
        guard let start = setStart, time - start >= 8, coverage >= 0.7,
              probability.isFinite, probability >= 0.8 else { firstPositive = nil; return false }
        if let last = lastTime, time - last > 1.5 { firstPositive = nil }
        if firstPositive == nil { firstPositive = time }
        return time - firstPositive! >= 2 // three consecutive one-second windows
    }
}
