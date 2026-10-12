# 3Min – Krafttraining auf der Apple Watch

Native SwiftUI-App mit iPhone-Begleiter. Ein „Satzende“ bezeichnet einen einzelnen Satz. Die Pause dauert 180 Sekunden. Keine Gesundheitsdaten werden an einen Build- oder Analyse-Dienst gesendet.

**Status: Cloud-Build mit Xcode 26.6 erfolgreich, vier Swift-Tests und zehn Python-Tests bestanden. Ein unsigniertes IPA mit eingebetteter Watch-App liegt vor. Signierung, echte Watch und Modellimport sind noch nicht geprüft; kein trainiertes Modell vorhanden.**

Erster erfolgreicher Build: [GitHub-Actions-Lauf](https://github.com/Till-glitch/3Min/actions/runs/38243162717), Commit `e4852e4`. Dort das Artefakt **ThreeMin-installation-probe** herunterladen. Der jeweilige neueste erfolgreiche Lauf enthält spätere Korrekturen. Die tatsächliche Toolchain war macOS 26.6.2, Xcode 26.6 (17F113), Swift 6.3.3 und XcodeGen 2.46.0 mit iOS-/watchOS-26.5-SDKs.

## Etappen

1. **Installation und Sensorzugriff:** Standard beim ersten Start. Training starten/beenden, Puls mit Alter, Bewegungsstatus, kurze Testvibration. Erst nach dem Hardwaretest „Sensortest bestanden“ auswählen.
2. **Lernversion:** vorbereiteter Quellcode wird danach auf der Uhr freigeschaltet. Große Tasten „Satz starten“ / „Satz fertig“, manuelle Markierungen, Pausentimer, Datenspeicherung und iPhone-Export. Auch diese Etappe muss auf echter Hardware abgenommen werden.
3. **ML:** Windows-Pipeline auf echten Lernaufzeichnungen, Vergleich mit Baseline, Core-ML-Export auf einem Mac bzw. Linux, lokale Modellübertragung iPhone → Watch. Kein Dummy-Modell enthalten. Automatik braucht ein trainiertes, bewertetes Modell und eine bewusste Gerätefreigabe. **Satzanfang bleibt in dieser ersten ML-Version manuell; Satzende kann automatisch erkannt werden.** So armiert Gehen oder Gerätewechsel allein keinen Pausentimer.

Die späteren Etappen sind vorbereitet, nicht als bereits getestete Erkennung freigegeben. Der nächste tatsächliche Meilenstein ist der erfolgreiche Installations- und Sensortest.

## Einstieg unter Windows

Lies [Installation und Signierung](docs/INSTALLATION_WINDOWS.md) zuerst. Der Weg Sideloadly → iPhone → Watch ist ein **unbestätigter Installationsversuch**, kein zugesicherter Weg. Apple's kostenlose HealthKit-Capability bedeutet nicht, dass ein beliebiger Signierer ein passendes Watch-Profil erzeugt.

Das Git-Remote ist `https://github.com/Till-glitch/3Min.git`. Der Workflow startet beim Push von App-/Build-Dateien automatisch. Einen weiteren Build kannst du unter Actions → „Unsigned iPhone and Watch installation probe“ → Run workflow starten. Vorher das GitHub-Actions-Kontingent/Kostenlimit ansehen. Der aktuelle Buildstatus steht im jeweiligen Actions-Lauf; ein Push allein bestätigt keinen erfolgreichen Build.

Der Workflow erzeugt nach einem erfolgreichen Build das Artefakt `ThreeMin-installation-probe` mit `ThreeMin-unsigned.ipa`, Toolchain-Protokoll, Build-Log und Paketprüfung. Das unsignierte IPA enthält echte Geräte-Binaries und ein Watch-App-Bundle. Signierung erfolgt anschließend lokal in Sideloadly. Ein unsigniertes IPA lässt sich nicht unmittelbar installieren.

## Projektinhalt

| Pfad | Zweck |
|---|---|
| `project.yml` | XcodeGen-Projektdefinition, zwei native App-Targets und eingebettete Watch-App |
| `Watch/` | HealthKit-Training, Core Motion, SwiftUI, JSONL-Aufzeichnung, Core ML, WatchConnectivity |
| `Phone/` | Empfang, lokale Dateien und Teilen/Export |
| `Shared/` | Plattformunabhängige Zustandslogik und Merkmale |
| `Package.swift`, `Tests/Swift/` | Swift-Tests ohne Sensor-/UI-Abhängigkeit |
| `.github/workflows/build.yml` | macOS-/Xcode-Build ohne Apple-Zugangsdaten |
| `scripts/` | IPA-Erstellung und Profil-Diagnose |
| `ml/` | Windows-Training, Evaluierung, separater Core-ML-Export |
| `docs/` | Installation, Datenformat, ML und Hardware-Abnahme |

## Lokal prüfen

Unter Windows reicht Python 3.10 oder neuer, ohne Zusatzpakete, für Training und Tests:

```powershell
python -m unittest discover -s Tests/Python -v
python -m compileall -q ml scripts Tests/Python
```

Auf einem Mac mit Xcode (siehe Anleitung):

```sh
brew install xcodegen
xcodegen generate
swift test
open ThreeMin.xcodeproj
```

XcodeGen erzeugt `Config/*` einschließlich Plists/Entitlements und die `.xcodeproj`. Änderungen an der Konfiguration in `project.yml` vornehmen. XcodeGen-Version und die tatsächlich installierten SDKs stehen im Build-Artefakt; die Homebrew-Version ist nicht fest gepinnt. Bei Generatoränderungen die Bundle-Struktur neu prüfen.

## Grenzen des aktuellen Stands

- Windows kann hier keine Apple-SDKs kompilieren. Tests und Geräte-Kompilierung wurden deshalb erfolgreich auf dem macOS-Cloud-Runner ausgeführt; eine echte Watch ist hier nicht verbunden.
- Haptik bedeutet einen `.click`-Aufruf pro abgelaufener Pause. Ob du ihn spürst und ob er bei gesenktem Handgelenk zeitnah erfolgt, ist nur auf echter Hardware prüfbar.
- Eine aktive HealthKit-Sitzung läuft über Satz **und** Pause. Training bewusst beenden; es wird in Health gespeichert. Keine Wiederaufnahme eines Timers nach App-Absturz oder Watch-Neustart: betroffene Dateien werden als unterbrochen abgeschlossen und beim ML-Training ausgeschlossen.
- Training auf Windows ist vollständig lokal. Apples Core-ML-Tools dokumentieren macOS/Linux, keinen Windows-Support; Konvertierung deshalb getrennt (z.B. lokale Linux-Umgebung). Das iPhone kompiliert das importierte Modell und überträgt seine Dateien zur Watch. Die Watch lädt nur kompilierte Modelle; die Gerätekompatibilität muss noch geprüft werden. In den Cloud-Build kommen nur App-Quellen, keine Rohdaten, gelernten Gewichte oder Trainingsprotokolle.
- Sensordaten werden nach Empfang nicht automatisch gelöscht. Löschen der Apps entfernt ihre lokalen Dateien; Health-Trainingsdaten separat in Health verwalten. JSONL vor Neuinstallation exportieren.

Details: [Datensatz](docs/DATASET.md), [ML](docs/ML.md), [Abnahmeprotokoll](docs/HARDWARE_TEST.md), [Quellenprüfung](docs/SOURCES.md).
