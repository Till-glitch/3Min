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
        guard file.metadata?["kind"] as? String == "trained_model" else { return }
        do {
            let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // Copy before returning from the callback; WC removes its temporary file afterward.
            let received = folder.appendingPathComponent("incoming-\(UUID().uuidString).mlmodel")
            try FileManager.default.copyItem(at: file.fileURL, to: received)
            modelQueue.async {
                defer { try? FileManager.default.removeItem(at: received) }
                do {
                    let compiled = try MLModel.compileModel(at: received)
                    let staging = folder.appendingPathComponent("staging-\(UUID().uuidString).mlmodelc")
                    try FileManager.default.copyItem(at: compiled, to: staging)
                    let target = folder.appendingPathComponent("SetEnd-next.mlmodelc")
                    if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
                    try FileManager.default.moveItem(at: staging, to: target)
                    DispatchQueue.main.async { self.status = "Modell lokal kompiliert. Training beenden und Modell laden." }
                } catch { DispatchQueue.main.async { self.status = "Modellinstallation: \(error.localizedDescription)" } }
            }
        } catch { DispatchQueue.main.async { self.status = "Modellempfang: \(error.localizedDescription)" } }
    }
}
