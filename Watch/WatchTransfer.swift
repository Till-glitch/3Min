import Foundation
import WatchConnectivity
import Combine
import CoreML

final class WatchTransfer: NSObject, ObservableObject, WCSessionDelegate {
    @Published var status = "iPhone-Verbindung wird vorbereitet"
    private let modelQueue = DispatchQueue(label: "de.personal.threemin.model", qos: .utility)
    override init() {
        super.init()
        if WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() }
    }
    func retry() {
        let session = WCSession.default
        guard session.activationState == .activated else { status = "Verbindung noch nicht aktiv"; return }
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sessions")
        do {
            let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            var count = 0
            for url in files where url.pathExtension == "jsonl" {
                let id = url.deletingPathExtension().lastPathComponent
                if UserDefaults.standard.bool(forKey: "received.\(id)") { continue }
                if session.outstandingFileTransfers.contains(where: { ($0.file.metadata?["session_id"] as? String) == id }) { continue }
                // Only closed or explicitly recovered sessions may be transferred.
                let tail = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").last.map(String.init) ?? ""
                guard let data = tail.data(using: .utf8),
                      let row = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      row["kind"] as? String == "session_end" else { continue }
                session.transferFile(url, metadata: ["session_id": id, "schema": 1]); count += 1
            }
            status = count > 0 ? "\(count) Datei(en) zur Übertragung vorgemerkt" : "Keine neuen Dateien; lokale Kopien bleiben erhalten"
        } catch { status = "Übertragung: \(error.localizedDescription)" }
    }
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { self.status = error?.localizedDescription ?? "iPhone-Verbindung aktiv"; self.retry() }
    }
    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        DispatchQueue.main.async {
            self.status = error.map { "Übertragung fehlgeschlagen: \($0.localizedDescription). Erneut senden möglich." }
                ?? "Datei übertragen; warte auf Empfangsbestätigung"
        }
    }
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let id = userInfo["received_session"] as? String, UUID(uuidString: id) != nil else { return }
        DispatchQueue.main.async {
            UserDefaults.standard.set(true, forKey: "received.\(id)")
            self.status = "iPhone hat Sitzung gespeichert"
        }
    }
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard file.metadata?["kind"] as? String == "compiled_model_part",
              let id = file.metadata?["generation"] as? String, UUID(uuidString: id) != nil,
              let relative = file.metadata?["relative_path"] as? String,
              let manifest = file.metadata?["paths"] as? [String], !manifest.isEmpty, manifest.count <= 100,
              Set(manifest).count == manifest.count, manifest.contains(relative) else { return }
        do {
            // Copy before returning from the callback; WC removes its temporary file afterward.
            let data = try Data(contentsOf: file.fileURL)
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            modelQueue.async {
                do {
                    let incoming = support.appendingPathComponent("ModelInbox").appendingPathComponent("\(id).mlmodelc")
                    func checkedPath(_ name: String) throws -> URL {
                        let path = incoming.appendingPathComponent(name).standardizedFileURL
                        guard !name.hasPrefix("/"), !name.split(separator: "/").contains(".."),
                              path.path.hasPrefix(incoming.standardizedFileURL.path + "/") else {
                            throw CocoaError(.fileReadCorruptFile)
                        }
                        return path
                    }
                    let paths = try manifest.map { try checkedPath($0) }
                    let received = try checkedPath(relative)
                    try FileManager.default.createDirectory(at: received.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: received, options: .atomic)
                    guard paths.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
                        DispatchQueue.main.async { self.status = "Kompiliertes Modell wird empfangen" }; return
                    }
                    // watchOS loads compiled models; runtime compilation is unavailable on watchOS.
                    let config = MLModelConfiguration(); config.computeUnits = .cpuOnly
                    _ = try MLModel(contentsOf: incoming, configuration: config)
                    let target = support.appendingPathComponent("SetEnd-next.mlmodelc")
                    if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
                    try FileManager.default.moveItem(at: incoming, to: target)
                    DispatchQueue.main.async { self.status = "Kompiliertes Modell empfangen. Training beenden und Modell laden." }
                } catch { DispatchQueue.main.async { self.status = "Modellinstallation: \(error.localizedDescription)" } }
            }
        } catch { DispatchQueue.main.async { self.status = "Modellempfang: \(error.localizedDescription)" } }
    }
}
