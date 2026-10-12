import SwiftUI

@main
struct ThreeMinWatchApp: App {
    @StateObject private var controller = WorkoutController()
    var body: some Scene { WindowGroup { WatchView(controller: controller) } }
}

struct WatchView: View {
    @ObservedObject var controller: WorkoutController
    @Environment(\.scenePhase) private var scene
    @AppStorage("installationVerified") private var verified = false
    @State private var confirmLearning = false
    @State private var confirmAutomatic = false
    @State private var confirmStop = false
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text(controller.phase.title)
                    .font(.title3.bold()).accessibilityAddTraits(.isHeader)
                Text(!controller.learningEnabled ? "Installation · Sensortest" : (controller.automatic ? "Automatik: Satzende" : "Lernmodus · manuell"))
                    .font(.caption).foregroundStyle(.secondary)
                if controller.phase == .rest {
                    Text(String(format: "%02d:%02d", controller.countdown / 60, controller.countdown % 60))
                        .font(.system(.largeTitle, design: .rounded).monospacedDigit())
                        .accessibilityLabel("Pause, noch \(controller.countdown) Sekunden")
                }
                if controller.active && controller.learningEnabled {
                    if controller.phase == .setRunning {
                        action("Satz fertig", color: .orange) { controller.finishSet() }
                    } else {
                        action(controller.phase == .rest ? "Pause abbrechen · Satz starten" : "Satz starten", color: .green) { controller.startSet() }
                    }
                }
                if !controller.active {
                    action("Training starten", color: .green) { controller.start() }.disabled(controller.busy)
                }
                Group {
                    Text(controller.pulse.map { "\(Int($0.rounded())) bpm" } ?? "Puls fehlt")
                        .font(.headline.monospacedDigit())
                    Text(controller.pulseAge.map { $0 <= 10 ? "Puls vor \(Int($0)) s" : "Puls veraltet · \(Int($0)) s" } ?? "Noch keine Pulsmessung")
                    Text(controller.sensor)
                    Text(controller.healthStatus)
                }.font(.caption)
                if let error = controller.error { Text(error).font(.caption).foregroundStyle(.orange) }
                Button("Vibration testen") { controller.testHaptic() }.frame(minHeight: 44)
                if controller.active {
                    Button("Gehen / Gerätewechsel markieren") { controller.recordActivity("walk_or_equipment_change") }
                        .frame(minHeight: 44)
                    Button("Training beenden", role: .destructive) { confirmStop = true }.frame(minHeight: 44)
                } else {
                    if !verified {
                        Button("Sensortest bestanden") { confirmLearning = true }.frame(minHeight: 44)
                    } else {
                        Text("Installation als geprüft markiert").font(.caption)
                    }
                    if controller.detector.available && verified {
                        Button("Automatik freigeben") { confirmAutomatic = true }.frame(minHeight: 44)
                    }
                    Button("Modell laden") { controller.reloadModel() }.frame(minHeight: 44).disabled(controller.busy)
                    Text(controller.detector.status).font(.caption)
                }
                TransferView(transfer: controller.transfer)
            }.padding(.horizontal, 4)
        }
        .onAppear { controller.learningEnabled = verified }
        .onChange(of: scene) { _, value in controller.recordScene(String(describing: value)) }
        .confirmationDialog("Installation, Puls, Bewegung und Vibration auf dieser Uhr geprüft?", isPresented: $confirmLearning) {
            Button("Ja · Lernversion aktivieren") { verified = true; controller.learningEnabled = true }
        }
        .confirmationDialog("Modell anhand echter Daten bewertet und auf dieser Uhr geprüft? Satzanfang bleibt manuell.", isPresented: $confirmAutomatic) {
            Button("Ja · Automatik aktivieren") { controller.automatic = true }
        }
        .confirmationDialog("Gesamtes Training beenden?", isPresented: $confirmStop) {
            Button("Training beenden", role: .destructive) { controller.stop() }
        }
    }
    private func action(_ title: String, color: Color, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { Text(title).font(.headline).frame(maxWidth: .infinity, minHeight: 44) }
            .tint(color).foregroundStyle(.black).buttonStyle(.borderedProminent)
    }
}
struct TransferView: View {
    @ObservedObject var transfer: WatchTransfer
    var body: some View {
        VStack(spacing: 8) {
            Text(transfer.status).font(.caption)
            Button("Daten erneut senden") { transfer.retry() }.frame(minHeight: 44)
        }
    }
}
