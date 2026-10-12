import Foundation
import Combine
import HealthKit
import CoreMotion
import WatchKit

final class WorkoutController: NSObject, ObservableObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    @Published var active = false
    @Published var busy = false
    @Published var phase = TrainingPhase.ready
    @Published var countdown = 0
    @Published var pulse: Double?
    @Published var pulseAge: Double?
    @Published var sensor = "Sensoren aus"
    @Published var healthStatus = "Berechtigungen noch nicht angefragt"
    @Published var error: String?
    @Published var learningEnabled = false
    @Published var automatic = false
    let detector = LocalDetector()
    let transfer = WatchTransfer()
    private let health = HKHealthStore()
    private let motion = CMMotionManager()
    private var workout: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var query: HKAnchoredObjectQuery?
    private var log: SessionLog?
    private var timer: Timer?
    private var machine = TrainingState()
    private var gate = DetectionGate()
    private var motions = [MotionPoint]()
    private var pulses = [PulsePoint]()
    private var lastMotion: Double?
    private var ending = false

    override init() {
        super.init()
        recoverInterruptedFiles()
    }
    func testHaptic() { WKInterfaceDevice.current().play(.click) }
    func reloadModel() {
        guard !active && !busy else { return }
        automatic = false; detector.reload(); objectWillChange.send()
    }
    func start() {
        guard !active && !busy else { return }
        error = nil; busy = true
        guard HKHealthStore.isHealthDataAvailable() else { error = "HealthKit ist nicht verfügbar"; busy = false; return }
        let heart = HKObjectType.quantityType(forIdentifier: .heartRate)!
        health.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [heart]) { success, failure in
            DispatchQueue.main.async {
                guard success, failure == nil else {
                    self.busy = false; self.error = failure?.localizedDescription ?? "Berechtigungsanfrage fehlgeschlagen"; return
                }
                // Request success never proves permission to READ heart rate.
                self.healthStatus = "Anfrage abgeschlossen; Puls-Leserecht bleibt privat"
                guard self.health.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
                    self.busy = false; self.error = "Bitte das Speichern von Trainings in Health erlauben"; return
                }
                self.beginAuthorized()
            }
        }
    }
    private func beginAuthorized() {
        do {
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .traditionalStrengthTraining
            configuration.locationType = .indoor
            let session = try HKWorkoutSession(healthStore: health, configuration: configuration)
            let live = session.associatedWorkoutBuilder()
            live.dataSource = HKLiveWorkoutDataSource(healthStore: health, workoutConfiguration: configuration)
            session.delegate = self; live.delegate = self
            let recording = try SessionLog(mode: learningEnabled ? "learning" : "installation")
            recording.append("settings", ["watch_model": WKInterfaceDevice.current().model,
                                           "wrist": String(describing: WKInterfaceDevice.current().wristLocation),
                                           "automatic": automatic, "model_status": detector.status,
                                           "detection_threshold": 0.8, "minimum_set_seconds": 8,
                                           "confirmation_seconds": 2, "minimum_coverage": 0.7])
            log = recording; workout = session; builder = live
            machine = TrainingState(); gate.reset(); motions = []; pulses = []
            pulse = nil; pulseAge = nil; lastMotion = nil; ending = false
            session.startActivity(with: recording.startDate)
            live.beginCollection(withStart: recording.startDate) { success, failure in
                DispatchQueue.main.async {
                    guard success, failure == nil else {
                        self.error = failure?.localizedDescription ?? "Trainingsaufzeichnung konnte nicht starten"
                        self.stop(); return
                    }
                    guard !self.ending else { return }
                    self.busy = false; self.active = true; self.phase = .ready
                    self.beginPulseQuery(heart: HKObjectType.quantityType(forIdentifier: .heartRate)!, start: recording.startDate)
                    self.beginMotion()
                    self.timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
                }
            }
        } catch { busy = false; self.error = error.localizedDescription }
    }
    private func beginPulseQuery(heart: HKQuantityType, start: Date) {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil, options: .strictStartDate)
        let q = HKAnchoredObjectQuery(type: heart, predicate: predicate, anchor: nil, limit: HKObjectQueryNoLimit) { [weak self] _, samples, _, _, failure in
            self?.receive(samples, error: failure)
        }
        q.updateHandler = { [weak self] _, samples, _, _, failure in self?.receive(samples, error: failure) }
        query = q; health.execute(q)
    }
    private func receive(_ samples: [HKSample]?, error: Error?) {
        DispatchQueue.main.async {
            guard self.active, let log = self.log else { return }
            if let error { self.healthStatus = "Pulsabfrage: \(error.localizedDescription)"; log.append("sensor_error", ["sensor": "heart", "message": error.localizedDescription]) }
            for sample in (samples as? [HKQuantitySample] ?? []).sorted(by: { $0.endDate < $1.endDate }) {
                let measured = sample.endDate.timeIntervalSince(log.startDate)
                let delivered = log.elapsed
                let bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                let clockOffset = Date().timeIntervalSince(log.startDate) - delivered
                let valid = abs(clockOffset) <= 2 && measured >= 0 && measured <= delivered + 1 && bpm.isFinite && bpm > 0
                log.append("heart", ["sample_t": measured, "bpm": bpm, "sample_utc": ISO8601DateFormatter().string(from: sample.endDate),
                                     "wall_clock_offset": clockOffset, "valid_time": valid], at: delivered)
                if valid { self.pulses.append(PulsePoint(t: measured, bpm: bpm)) }
            }
            self.pulses.sort { $0.t < $1.t }
        }
    }
    private func beginMotion() {
        guard motion.isDeviceMotionAvailable else {
            sensor = "Device Motion nicht verfügbar"
            log?.append("sensor_error", ["sensor": "motion", "message": sensor]); return
        }
        motion.deviceMotionUpdateInterval = 1 / 25
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, failure in
            guard let self, self.active, let log = self.log else { return }
            if let failure { self.sensor = "Bewegung: \(failure.localizedDescription)"; log.append("sensor_error", ["sensor": "motion", "message": self.sensor]); return }
            guard let data else { return }
            // Core Motion timestamps share the system uptime origin; no arrival-time relabeling.
            let t = data.timestamp - log.startUptime
            guard t >= 0 else { return }
            let a = data.userAcceleration, r = data.rotationRate
            log.append("motion", ["ax": a.x, "ay": a.y, "az": a.z, "rx": r.x, "ry": r.y, "rz": r.z,
                                  "received_t": log.elapsed], at: t)
            self.motions.append(MotionPoint(t: t, acceleration: sqrt(a.x*a.x+a.y*a.y+a.z*a.z), rotation: sqrt(r.x*r.x+r.y*r.y+r.z*r.z)))
            self.lastMotion = t
        }
    }
    func startSet() {
        guard active, learningEnabled, let log, machine.phase != .setRunning else { return }
        if machine.phase == .rest { log.append("rest_cancelled", ["set_number": machine.setNumber]) }
        guard machine.startSet(at: log.elapsed) else { return }
        gate.reset()
        log.append("set_start", ["set_number": machine.setNumber, "source": "manual"])
        syncUI(); log.flush()
    }
    func finishSet(source: String = "manual") {
        guard active, learningEnabled, let log, machine.finishSet(at: log.elapsed) else { return }
        gate.reset()
        log.append("set_end", ["set_number": machine.setNumber, "source": source])
        log.append("rest_start", ["deadline_t": machine.restDeadline!, "set_number": machine.setNumber])
        syncUI(); log.flush()
    }
    func recordActivity(_ name: String) {
        guard active else { return }
        log?.append("activity", ["name": name]); log?.flush()
    }
    func recordScene(_ value: String) { log?.append("scene", ["value": value]); log?.flush(); tick() }
    private func syncUI() {
        phase = machine.phase
        countdown = machine.remaining(at: log?.elapsed ?? 0)
    }
    private func tick() {
        guard active, let log else { return }
        let now = log.elapsed
        if machine.tick(at: now) {
            log.append("rest_finished", ["set_number": machine.setNumber])
            WKInterfaceDevice.current().play(.click)
            log.append("haptic_requested", ["type": "rest_end"])
        }
        syncUI()
        if let p = pulses.filter({ $0.t <= now }).last { pulse = p.bpm; pulseAge = max(0, now - p.t) }
        else { pulse = nil; pulseAge = nil }
        sensor = lastMotion.map { now - $0 <= 2 ? "Bewegung aktiv (25 Hz angefragt)" : "Bewegungsdaten fehlen seit \(Int(now - $0)) s" } ?? "Keine Bewegungsdaten"
        log.append("status", ["phase": phase.rawValue, "heart_age": pulseAge.map { $0 as Any } ?? NSNull(),
                              "heart_fresh": (pulseAge ?? .infinity) <= 10,
                              "motion_age": lastMotion.map { (now - $0) as Any } ?? NSNull(),
                              "automatic": automatic, "learning": learningEnabled])
        if automatic, learningEnabled, detector.available, phase == .setRunning {
            let features = WindowFeatures.compute(motion: motions, pulses: pulses, end: now)
            do {
                if let p = try detector.probability(features) {
                    log.append("prediction", ["probability": p, "features": features, "feature_version": WindowFeatures.version])
                    if gate.accepts(probability: p, coverage: features[10], time: now, setStart: machine.setStarted) {
                        finishSet(source: "model")
                    }
                }
            } catch { automatic = false; self.error = "Modellfehler: \(error.localizedDescription)"; log.append("model_error", ["message": error.localizedDescription]) }
        }
        motions.removeAll { $0.t < now - 9 }; pulses.removeAll { $0.t < now - 35 }
        log.flush()
        if let failure = log.error { self.error = "Speichern fehlgeschlagen: \(failure)"; stop() }
    }
    func stop() {
        guard !ending, workout != nil else { return }
        ending = true; busy = true
        motion.stopDeviceMotionUpdates(); timer?.invalidate(); timer = nil
        if let query { health.stop(query) }; query = nil
        log?.append("session_stop_requested", ["phase": phase.rawValue]); log?.flush()
        active = false; automatic = false; workout?.end()
    }
    private func completeRecording(failure: String? = nil) {
        log?.append("session_end", ["reason": failure ?? "user", "phase": phase.rawValue])
        log?.close(); log = nil; workout = nil; builder = nil; busy = false; ending = false
        phase = .ready; countdown = 0; sensor = "Sensoren aus"; transfer.retry()
    }
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        DispatchQueue.main.async {
            guard workoutSession === self.workout else { return }
            self.log?.append("workout_state", ["value": toState.rawValue])
            guard toState == .ended else { return }
            self.motion.stopDeviceMotionUpdates(); self.timer?.invalidate(); self.timer = nil
            if let query = self.query { self.health.stop(query) }; self.query = nil
            self.active = false; self.busy = true
            guard let builder = self.builder else { self.completeRecording(); return }
            builder.endCollection(withEnd: date) { success, failure in
                guard success, failure == nil else {
                    DispatchQueue.main.async { self.error = failure?.localizedDescription ?? "Health-Abschluss fehlgeschlagen"; self.completeRecording(failure: self.error) }; return
                }
                builder.finishWorkout { _, failure in
                    DispatchQueue.main.async {
                        if let failure { self.error = failure.localizedDescription }
                        else { self.healthStatus = "Training in Health gespeichert"; self.log?.append("workout_saved") }
                        self.completeRecording(failure: failure?.localizedDescription)
                    }
                }
            }
        }
    }
    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            guard workoutSession === self.workout else { return }
            self.error = "Trainingssitzung: \(error.localizedDescription)"
            self.motion.stopDeviceMotionUpdates(); self.timer?.invalidate(); self.timer = nil
            if let query = self.query { self.health.stop(query) }; self.query = nil
            self.active = false; self.completeRecording(failure: error.localizedDescription)
        }
    }
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {}

    private func recoverInterruptedFiles() {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Sessions")
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        for url in files where url.pathExtension == "jsonl" {
            do {
                let data = try Data(contentsOf: url)
                // Drop only an incomplete final line after a crash; keep all complete rows.
                let complete = data.last == 10 ? data : Data(data.prefix((data.lastIndex(of: 10).map { $0 + 1 }) ?? 0))
                let rows = String(decoding: complete, as: UTF8.self).split(separator: "\n")
                guard let last = rows.last, let bytes = String(last).data(using: .utf8),
                      let row = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                      row["kind"] as? String != "session_end" else { continue }
                let closing: [String: Any] = ["kind": "session_end", "session_id": row["session_id"] ?? "", "seq": (row["seq"] as? Int ?? 0) + 1,
                                              "t": row["t"] ?? 0, "reason": "interrupted", "phase": "unknown"]
                var repaired = complete
                repaired.append(try JSONSerialization.data(withJSONObject: closing, options: [.sortedKeys])); repaired.append(10)
                try repaired.write(to: url, options: .atomic)
            } catch { self.error = "Wiederherstellung: \(error.localizedDescription)" }
        }
    }
}
