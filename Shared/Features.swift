import Foundation

struct MotionPoint {
    let t: Double
    let acceleration: Double // magnitude, user acceleration in g
    let rotation: Double // magnitude, rad/s
}
struct PulsePoint {
    let t: Double // actual measurement time, not delivery time
    let bpm: Double
}

enum WindowFeatures {
    static let names = ["acc_mean", "acc_std", "acc_change", "rot_mean", "rot_std", "rot_change",
                        "hr_scaled", "hr_slope_scaled", "hr_missing", "hr_age_scaled", "coverage", "max_gap_scaled"]
    static let version = "window-v1"
    static func compute(motion: [MotionPoint], pulses: [PulsePoint], end: Double) -> [Double] {
        let points = motion.filter { $0.t > end - 8 && $0.t <= end }.sorted { $0.t < $1.t }
        func mean(_ a: [Double]) -> Double { a.isEmpty ? 0 : a.reduce(0, +) / Double(a.count) }
        func std(_ a: [Double]) -> Double {
            let m = mean(a)
            return sqrt(mean(a.map { ($0 - m) * ($0 - m) }))
        }
        let a = points.map(\.acceleration), r = points.map(\.rotation)
        let early = points.filter { $0.t <= end - 4 }, late = points.filter { $0.t > end - 4 }
        let recent = pulses.filter { $0.t <= end && $0.t >= end - 30 }.sorted { $0.t < $1.t }
        let last = recent.last
        let age = last.map { max(0, end - $0.t) } ?? 30
        let fresh = last != nil && age <= 10
        let hr = fresh ? last!.bpm / 200 : 0
        let slope: Double
        if fresh, let first = recent.first, last!.t - first.t >= 1 {
            slope = (last!.bpm - first.bpm) / (last!.t - first.t) / 10
        } else { slope = 0 }
        var gap = points.first.map { max(0, $0.t - (end - 8)) } ?? 8
        for i in 1..<max(1, points.count) { gap = max(gap, points[i].t - points[i-1].t) }
        gap = max(gap, end - (points.last?.t ?? (end - 8)))
        return [mean(a), std(a), mean(late.map(\.acceleration)) - mean(early.map(\.acceleration)),
                mean(r), std(r), mean(late.map(\.rotation)) - mean(early.map(\.rotation)),
                hr, slope, fresh ? 0 : 1, min(age, 30) / 30,
                min(1, Double(points.count) / 200), min(gap, 8) / 8]
    }
}
