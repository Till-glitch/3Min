# Installation unter Windows – zuerst als Geräteversuch

## Was nach offizieller Dokumentation feststeht

Prüfstand 12.10.2026. Deine Angaben watchOS **26.5** und iOS **26.6.2** werden übernommen. SDK-, Xcode- und Betriebssystemversionen sind unterschiedliche Dinge.

- Apple führt HealthKit in [Supported capabilities (watchOS)](https://developer.apple.com/help/account/reference/supported-capabilities-watchos) auch für die kostenlose Spalte „Apple Developer“ auf. Die HTML-Tabelle hat bei HealthKit Häkchen in allen drei Spalten. Eine kostenpflichtige Mitgliedschaft ist daher nicht allein wegen HealthKit pauschal Voraussetzung. Das tatsächlich ausgestellte Profil muss die Berechtigung trotzdem enthalten.
- Ein [Personal Team](https://developer.apple.com/help/account/basics/about-your-developer-account) hat Einschränkungen: 10 App-IDs, 3 Geräte, 3 Apps pro Gerät, jeweils die dokumentierten Gültigkeitsgrenzen; Provisioning-Profile laufen nach 7 Tagen ab. Enthaltene Targets können zusätzliche IDs/Registrierungen benötigen.
- [Sideloadly](https://sideloadly.io/) unterstützt Windows, freie Apple-Konten und iOS 26+. Die [FAQ](https://sideloadly.io/faq.html) beschreibt Erneuerung und Developer Mode. In Startseite, FAQ und aktuellem [Changelog](https://sideloadly.io/changelog) wurde **keine Zusage für watchOS-Installation** gefunden. Daraus folgt weder „sicher unmöglich“ noch „funktioniert“.
- [Apples SDK-Tabelle](https://developer.apple.com/xcode/system-requirements) nennt für Xcode 26.6 iOS-/watchOS-26.5-SDKs und macOS Tahoe ab 26.2. [GitHubs macos-26-Image](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md) listet Xcode 26.6, Build 17F113, unter `/Applications/Xcode_26.6.app`. Genau diesen Pfad nutzt der Workflow und bricht ab, wenn er fehlt. Er benötigt kein erfundenes „iOS-26.6.2-SDK“. Deployment-Minima sind iOS 17 und watchOS 10. Ob deine konkreten Geräte diesen Build akzeptieren, bleibt Teil des Tests.

## Drei getrennte Ergebnisse

1. **Paket:** Das IPA enthält ein kompiliertes Watch-Bundle, Companion-ID und ausführbare Datei. Dies prüft das Paketskript.
2. **Signierung:** Jedes erforderliche Bundle benötigt eine gültige Signatur und ein passendes Profil. Das Watch-Profil muss die Watch selbst zulassen; die iPhone-Registrierung allein genügt nicht. HealthKit muss im Watch-Profil **und in den signierten Executable-Entitlements** enthalten sein. Das IPA-Paketskript prüft keine Signierung.
3. **Installation und Start:** Die Uhr muss die App tatsächlich annehmen, anzeigen, öffnen und Sensorzugriff erlauben. Weder Sideloadlys iPhone-Erfolgsmeldung noch `WCSession.isWatchAppInstalled` beweisen das vollständig.

## 1. IPA in GitHub Actions bauen

1. Projektdateien in dein GitHub-Repository übertragen. Keine Dateien aus `data/`, `models/` oder `*.jsonl` committen. `.gitignore` hilft, ist aber kein Schutz vor ausdrücklich erzwungenen Uploads.
2. GitHub → Repository → Actions aktivieren. Kontingent/Budget prüfen: macOS-Runs können kostenpflichtige Minuten verbrauchen; dieser Workflow startet keine kostenpflichtigen Zusatzdienste. Bei Bedarf `push`/`pull_request`-Trigger entfernen und nur manuell ausführen.
3. Workflow „Unsigned iPhone and Watch installation probe“ → Run workflow.
4. Erfolgsbedingungen: Swift-Tests, Python-Tests, `xcodebuild`, anschließend Paketprüfung erfolgreich. Ein grüner Test-Job ohne erzeugtes IPA ist kein vollständiger Build.
5. Artefakt `ThreeMin-installation-probe` herunterladen und ZIP unter Windows entpacken. `toolchain.txt`, `xcodebuild.log`, `package-report.json` aufbewahren. `signed: false` und `watch_installation_verified: false` sind erwartete Werte.

Es werden keine Apple-Zugangsdaten, Zertifikate, Geräte-UDIDs oder Gesundheitsdaten benötigt. `CODE_SIGNING_ALLOWED=NO` erstellt Geräte-Binaries. `Payload/ThreeMinPhone.app` wird mit `ditto` zu einem IPA gepackt; es handelt sich nicht um einen mit Apple-Profilen exportierten Development-Archive-Build. Sideloadly kann IPAs nachsignieren; ob das komplette Watch-Paket dabei geeignet signiert wird, muss separat geprüft werden.

Wenn Xcode meldet, Watch-Content liege im falschen Verzeichnis (z.B. „Foundation extension ... PlugIns directory“): genaue Meldung, XcodeGen-Version und Build-Log sichern. Nicht bloß das fertige IPA umsortieren. Die Target-Art und Einbettung im generierten Xcode-Projekt müssen dazu passen. Das Skript akzeptiert genau eine moderne Watch-App unter `Watch/` oder `PlugIns/`, entscheidet aber nicht über Apples Installer-Validierung. Keine ungeprüfte Generator-Reparatur ist hier als erfolgreiche Installation ausgewiesen.

## 2. Windows und Geräte vorbereiten

1. Aktuelle Sideloadly-Version ausschließlich von [sideloadly.io](https://sideloadly.io/) verwenden. Zum Prüfzeitpunkt nennt die Seite 0.70.1. Deine tatsächliche Version im Hardwareprotokoll eintragen.
2. Nach Sideloadlys Hinweisen die dort verlinkten **Web-Versionen** von iTunes/iCloud benutzen; die Website nennt Microsoft-Store-Versionen als ungeeignet. Bestehende Installationen erst anhand der dortigen Hinweise prüfen.
3. iPhone mit Datenkabel verbinden, entsperren, „Diesem Computer vertrauen“ bestätigen. Apple Watch gekoppelt, entsperrt und in der Nähe halten. Genügend freien Speicher sicherstellen.
4. Auf dem iPhone Einstellungen → Datenschutz & Sicherheit → Entwicklermodus einschalten, Neustart und Bestätigung durchführen. Auf der Watch ebenfalls Einstellungen → Datenschutz & Sicherheit → Entwicklermodus prüfen. [Apple beschreibt Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device) und [Gerätepaarung](https://developer.apple.com/documentation/xcode/pairing-your-devices-with-your-mac) für Entwicklung.
5. Fehlt der Watch-Schalter: Das ist ein konkretes Hindernis, keine Einstellung, die die App selbst freischalten kann. Apples dokumentierter Entwicklungsweg verwendet Xcode-Gerätepaarung. Ein cloudgehosteter Build-Mac hat keine automatische Verbindung zu deiner lokalen Watch. Keinen garantierten Windows-Ersatz versprechen.

## 3. Sideloadly-Installationsversuch

1. `ThreeMin-unsigned.ipa` in Sideloadly ziehen, **dein iPhone** auswählen, dein kostenloses Apple-Konto lokal eingeben und ggf. Apples Zwei-Faktor-Prüfung beantworten. Keine Zugangsdaten ins Repository schreiben.
2. Regulären Apple-ID-Sideload-Modus verwenden. Keine Tweak-Injection, keine Entfernung von Erweiterungen/Watch-Inhalten, keine automatische Reduktion von Capabilities.
3. Bundle-IDs zunächst erhalten. Falls Sideloadly sie für dein Konto anpasst, müssen iPhone-ID, Watch-ID (iPhone-Präfix) und `WKCompanionAppBundleIdentifier` gemeinsam passend geändert sein. Bloß eine der drei IDs zu ändern kann die Installation/WatchConnectivity verhindern. Für Updates exakt dieselben IDs verwenden.
4. Start drücken, vollständiges Ergebnisprotokoll sichern. Fehler beim Registrieren von IDs/Geräten, Profile-Erstellen oder Entitlements nicht durch Entfernen von HealthKit umgehen; das würde den erforderlichen Sensortest verändern.
5. Falls nötig auf dem iPhone Einstellungen → Allgemein → VPN & Geräteverwaltung → deinem Entwicklerkonto vertrauen (siehe Sideloadly-FAQ). App auf dem iPhone öffnen.
6. iPhone-App **Watch** → Meine Watch → verfügbare Apps prüfen. Falls 3Min erscheint, „Installieren“ wählen; bei automatischer App-Installation trotzdem den tatsächlichen Watch-Start kontrollieren.
7. 3Min in der App-Liste **auf der Uhr** öffnen. Wenn sie fehlt, Installation hängt oder Start scheitert: Uhrmodell, OS-Versionen, Sideloadly-Version, Zeitpunkt, genaue Fehlermeldung und Logs im [Protokoll](HARDWARE_TEST.md) sammeln. „iPhone erfolgreich“ zählt nicht als bestandene Etappe.

Falls Sideloadly ein **nach der Signierung exportiertes** IPA bereitstellt, kann unter Windows dessen Profilinhalt untersucht werden:

```powershell
python scripts/inspect_profiles.py 'C:\Pfad\ThreeMin-signed.ipa'
```

Das liest die XML-Information aus CMS-Profilen, validiert aber weder die kryptografische Signatur noch die Executable-Entitlements. `healthkit_allowed` im Watch-Profil muss wahr sein. Es gibt bewusst keinen universell zugesicherten Sideloadly-Menüpfad für den Export; falls kein nachsigniertes Paket zugänglich ist, den Signierungsnachweis als **offen** markieren. Auf einem Mac kann man extrahierte Bundles zusätzlich mit `codesign -d --entitlements :- <Watch.app>` und Profile mit `security cms -D -i <embedded.mobileprovision>` prüfen. Profilgeräte müssen iPhone bzw. Watch zulassen; vollständige Gerätekennungen nicht öffentlich posten.

## 4. Sensortest auf der Uhr

1. „Vibration testen“ drücken, kurze Vibration fühlen und dokumentieren.
2. „Training starten“. HealthKit-Anfrage auf der Uhr bearbeiten: Puls lesen und Training speichern erlauben. 3Min benötigt kein Schreiben eigener Pulswerte.
3. Puls und Alter beobachten; Handgelenk bewegen. „Bewegung aktiv“ muss mit realen Samples bestätigt werden. Erfolg der Berechtigungsanfrage bestätigt nicht das Puls-Leserecht; HealthKit verbirgt Ablehnung von Leserechten aus Datenschutzgründen.
4. Mindestens 5 Minuten mit gesenktem Handgelenk trainieren, zwischendurch Uhr anheben. App im Hintergrund lassen. Sensorlücken nach Export prüfen; „25 Hz angefragt“ ist keine gemessene Garantie.
5. Training beenden, Health-Speicherung prüfen. Beide Geräte verbunden lassen; Sitzungsdatei soll im iPhone erscheinen. JSONL nach Windows exportieren und Sensorzeiten ansehen.
6. Erst bei bestandenem Protokoll auf der Uhr „Sensortest bestanden“ bestätigen. Damit ist die vorbereitete Lernversion aktiviert. Danach die Timer-/Hintergrundprüfung aus dem Hardwareprotokoll durchführen.

## 5. Vor Ablauf erneuern

1. Vor sieben Tagen die identische IPA mit **demselben Apple-Konto und denselben Bundle-IDs** erneut signieren/installieren. Lokale Daten vorher exportieren. App überschreiben, nicht erst deinstallieren.
2. Nach Sideloadly-FAQ automatische Erneuerung aktivieren, wenn gewünscht. Der Daemon braucht erreichbares iPhone über USB oder zuvor eingerichtete WLAN-Synchronisation; PC eingeschaltet, Daemon laufend, gleiches Netz. WLAN zuerst mit iTunes über USB einrichten.
3. Die dokumentierte iPhone-Erneuerung ist keine bestätigte Watch-Erneuerung. Nach **jedem** Refresh die Watch-App öffnen, Sensortraining starten, wieder beenden. Ablaufdatum der Watch-Profile und Gerätefunktion separat kontrollieren.
4. Scheitert Refresh, IPA erneut manuell installieren und konkrete Fehlermeldung sichern. Ein abgelaufenes Profil wird nicht durch einen Timer innerhalb der App verlängert.

## Hindernisse und Alternativen

| Befund | Nächster sinnvoller Schritt |
|---|---|
| Keine Watch-App in „verfügbare Apps“ | Nachsigniertes Bundle und Companion-IDs prüfen; Sideloadly-Log sichern. Ein enthaltenes Watch-Verzeichnis ist noch kein Installationsnachweis. |
| Watch-Profil fehlt / Watch nicht provisioniert | Signierer muss watchOS-Profil und Watch-Geräteregistrierung unterstützen; iPhone-Profil nicht kopieren. Wenn Sideloadly das nicht leistet, ist dieser Weg blockiert. |
| HealthKit-Entitlement fehlt | Profil und Executable prüfen; auf passendes Personal-Team-Provisioning über Xcode wechseln. Capability nicht wegpatchen. |
| Kein Watch Developer Mode | Einmaliger Zugang zu einem geeigneten Mac mit Xcode und lokaler Gerätepaarung kann nötig sein. Reiner GitHub-Build kann die Uhr nicht koppeln. |
| „A valid provisioning profile ... was not found“ | Genauen Bundle-Pfad in der Meldung, Ablaufdatum, Gerätezuordnung und Entitlements prüfen. |
| App startet, aber kein Puls | Uhrsitz, Pulsfreigabe, aktive Workout-Sitzung und exportierte Heart-/Fehlerzeilen prüfen. Fehlender Puls allein beweist keine Ablehnung. |
| Hintergrundtimer oder Bewegung setzt aus | Aktive Workout-Sitzung und Hintergrundmodi prüfen, Datenlücken/CPU analysieren, keine bestandene Hintergrundprüfung behaupten. |

Die nächste Alternative ist ein **geliehener, passender Mac** mit Xcode, kostenloser Personal-Team-Signierung und lokaler iPhone-/Watch-Verbindung. XcodeGen erzeugen, für beide Targets dein Personal Team auswählen, individuelle zusammenpassende IDs setzen und zunächst iPhone-, dann Watch-Scheme auf echten Geräten starten. HealthKit-/Hintergrund-Einträge erhalten. Ob Xcode deine konkrete Uhr provisioniert, dort prüfen.

Ein gemieteter Remote-Mac kann kompilieren oder konvertieren, benötigt für Geräteinstallation aber eine tatsächlich funktionierende lokale Geräteverbindung; gewöhnlicher Remote-Desktop stellt diese nicht bereit. Kostenpflichtige Mitgliedschaft, TestFlight oder Signierdienste werden weder vorausgesetzt noch gebucht. Bei einem dokumentierten Sideloadly-Hindernis ist eine zusätzliche Entscheidung erforderlich; das Projekt kann den fehlenden Installer-Support nicht per App-Code beheben.
