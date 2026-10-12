import SwiftUI
import WatchConnectivity
import UniformTypeIdentifiers

final class PhoneReceiver: NSObject, ObservableObject, WCSessionDelegate {
    @Published var files = [URL]()
    @Published var status = "Watch-Verbindung wird vorbereitet"
    let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Sessions")
    override init() {
        super.init()
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch { status = error.localizedDescription }
        refresh()
        if WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() }
    }
    func refresh() {
        files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "jsonl" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    func sendModel(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            guard url.pathExtension == "mlmodel" else { throw CocoaError(.fileReadUnsupportedScheme) }
            let session = WCSession.default
            guard session.activationState == .activated && session.isWatchAppInstalled else {
                status = "Watch-Verbindung noch nicht bereit"; return
            }
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            let kept = support.appendingPathComponent("model-\(UUID().uuidString).mlmodel")
            try Data(contentsOf: url).write(to: kept, options: .atomic)
            session.transferFile(kept, metadata: ["kind": "trained_model"])
            status = "Modell zur lokalen Watch-Übertragung vorgemerkt"
        } catch { status = "Modellimport: \(error.localizedDescription)" }
    }
    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        if fileTransfer.file.metadata?["kind"] as? String == "trained_model" {
            try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
            DispatchQueue.main.async {
                self.status = error.map { "Modellübertragung: \($0.localizedDescription). Erneut importieren." }
                    ?? "Modell übertragen. Kompilierung und Freigabe auf der Uhr prüfen."
            }
        }
    }
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.status = error?.localizedDescription ?? (session.isWatchAppInstalled ? "Watch-App gemeldet; Start auf der Uhr separat prüfen" : "Watch-App noch nicht als installiert gemeldet")
        }
    }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // WC's temporary URL is valid only during this delegate callback.
        do {
            guard let id = file.metadata?["session_id"] as? String, UUID(uuidString: id) != nil else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let data = try Data(contentsOf: file.fileURL)
            let rows = String(decoding: data, as: UTF8.self).split(separator: "\n")
            guard let first = rows.first, let last = rows.last,
                  let start = try JSONSerialization.jsonObject(with: Data(first.utf8)) as? [String: Any],
                  let end = try JSONSerialization.jsonObject(with: Data(last.utf8)) as? [String: Any],
                  start["session_id"] as? String == id, start["kind"] as? String == "session_start",
                  end["session_id"] as? String == id, end["kind"] as? String == "session_end" else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try data.write(to: folder.appendingPathComponent("\(id).jsonl"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            session.transferUserInfo(["received_session": id])
            DispatchQueue.main.async { self.refresh(); self.status = "Sitzung lokal gespeichert" }
        } catch { DispatchQueue.main.async { self.status = "Empfang fehlgeschlagen: \(error.localizedDescription). Auf der Uhr erneut senden." } }
    }
}

@main
struct ThreeMinPhoneApp: App {
    @StateObject private var receiver = PhoneReceiver()
    @State private var importingModel = false
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                List {
                    Section("Installation prüfen") {
                        Text(receiver.status)
                        Text("Öffne 3Min auf der Apple Watch. Starte dort eine Trainingssitzung und prüfe Puls, Bewegung und Vibration.")
                        Text("Ein erfolgreicher iPhone-Start bestätigt noch keine Watch-Installation.")
                    }
                    Section("Deine lokalen Sitzungen") {
                        if receiver.files.isEmpty { Text("Noch keine Sitzung empfangen. Beende das Training auf der Uhr und lasse beide Geräte verbunden.") }
                        ForEach(receiver.files, id: \.self) { url in
                            ShareLink(item: url) { Label(url.deletingPathExtension().lastPathComponent, systemImage: "square.and.arrow.up") }
                                .accessibilityLabel("Trainingssitzung exportieren")
                        }
                    }
                    Section("Export nach Windows") {
                        Text("Die JSONL-Dateien liegen auch in Dateien → Auf meinem iPhone → 3Min → Sessions. Über iTunes-Dateifreigabe kannst du den Ordner auf deinen PC kopieren.")
                        Text("Keine Gesundheitsdaten an Build-Workflows oder Analyse-Dienste senden.")
                    }
                    Section("Später: trainiertes Modell") {
                        Button("Core-ML-Modell lokal importieren") { importingModel = true }
                        Text("Nur dein bewertetes SetEnd.mlmodel wählen. Übertragung erfolgt zur Uhr, außerhalb des Cloud-Builds.")
                    }
                }.navigationTitle("3Min").refreshable { receiver.refresh() }
                    .fileImporter(isPresented: $importingModel, allowedContentTypes: [UTType(filenameExtension: "mlmodel") ?? .data]) { result in
                        switch result {
                        case .success(let url): receiver.sendModel(url)
                        case .failure(let error): receiver.status = "Modellimport: \(error.localizedDescription)"
                        }
                    }
            }
        }
    }
}
