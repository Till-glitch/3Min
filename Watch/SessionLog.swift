import Foundation

final class SessionLog {
    let id = UUID().uuidString
    let startDate = Date()
    let startUptime = ProcessInfo.processInfo.systemUptime
    let url: URL
    private var handle: FileHandle?
    private var pending = Data()
    private var sequence = 0
    var error: String?
    var elapsed: Double { ProcessInfo.processInfo.systemUptime - startUptime }

    init(mode: String) throws {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appendingPathComponent("\(id).jsonl")
        guard FileManager.default.createFile(atPath: url.path, contents: nil,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        handle = try FileHandle(forWritingTo: url)
        append("session_start", ["schema": 1, "utc_start": ISO8601DateFormatter().string(from: startDate),
                                "motion_hz": 25, "rest_seconds": 180, "hr_stale_seconds": 10,
                                "feature_version": WindowFeatures.version, "mode": mode,
                                "os": ProcessInfo.processInfo.operatingSystemVersionString,
                                "app_version": "0.1.0", "clock": "systemUptime", "exercise": ""])
        flush()
    }
    func append(_ kind: String, _ values: [String: Any] = [:], at time: Double? = nil) {
        guard handle != nil, error == nil else { return }
        var row = values
        row["kind"] = kind; row["session_id"] = id; row["seq"] = sequence
        row["t"] = time ?? elapsed
        do {
            let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
            pending.append(data); pending.append(10); sequence += 1
            if pending.count >= 32768 { flush() }
        } catch { self.error = error.localizedDescription }
    }
    func flush() {
        guard !pending.isEmpty else { return }
        do { try handle?.write(contentsOf: pending); pending.removeAll(keepingCapacity: true); try handle?.synchronize() }
        catch { self.error = error.localizedDescription }
    }
    func close() { flush(); try? handle?.close(); handle = nil }
    deinit { close() }
}
