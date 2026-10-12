# Abnahme auf deiner echten Apple Watch

**Noch nicht ausgeführt.** Alle leeren Felder sind offene Prüfungen. Keine Aussagen über Geräteverhalten aus Simulatoren oder erstelltem Quellcode ableiten.

## Nachweisstand (12.10.2026)

| Prüfung | Tatsächlicher Stand |
|---|---|
| Quellcode, Builddefinition, Workflow, Anleitung | erstellt |
| Python-Tests unter Windows | 10 Tests bestanden |
| Python-Syntaxprüfung | bestanden |
| Swift-Zustands-/Featuretests | geschrieben, mangels Compiler nicht ausgeführt |
| XcodeGen-Generierung | nicht ausgeführt |
| Xcode-Build iOS/watchOS | nicht ausgeführt |
| IPA-Paketprüfung an echten Binaries | nicht ausgeführt |
| Sideloadly-Signierung inkl. Watch-Profil/HealthKit | nicht ausgeführt |
| Watch-Installation und Developer Mode | nicht ausgeführt |
| Puls-/Bewegungsberechtigung, Hintergrund, Haptik | nicht ausgeführt |
| Echte Lernaufzeichnungen und trainiertes Modell | noch nicht vorhanden |
| Core-ML-Konvertierung / lokaler Watch-Modellimport | nicht ausgeführt |

## Geräte- und Buildangaben

- Watch-Modell / Größe / Handgelenk: ____
- watchOS: 26.5 (Nutzerangabe; tatsächlicher Build optional ergänzen): ____
- iPhone-Modell: ____
- iOS: 26.6.2 (Nutzerangabe): ____
- Sideloadly-Version: ____
- Git-Commit und GitHub-Run: ____
- `toolchain.txt` / XcodeGen-Version: ____
- IPA SHA-256 (`package-report.json`): ____
- Profil-Ablaufdatum iPhone / Watch: ____
- Beide Geräte in den erforderlichen Profilen enthalten, Executable-Entitlements passend: ____
- Developer Mode iPhone / Watch: ____

Keine vollständigen UDIDs, Apple-Konten, Gesundheitsdateien oder privaten Profile öffentlich posten.

## Etappe A: Installation und Sensoren

| Schritt | Erwartung | Ergebnis / genauer Fehler |
|---|---|---|
| IPA baut und Paketprüfung findet genau ein Watch-Bundle | Build-/Package-Logs vollständig | ____ |
| Sideloadly signiert iPhone und enthaltene Watch-App | getrennte Profile/Berechtigungen prüfen; kein Nachweis durch iPhone-Status allein | ____ |
| 3Min auf iPhone starten | Begleiter sichtbar | ____ |
| 3Min auf echter Uhr starten | Watch-Oberfläche sichtbar, kein Sofortabsturz | ____ |
| „Vibration testen“ | ein kurzer gefühlter Impuls | ____ |
| Training starten und Berechtigungen erteilen | Workout aktiv, Pulsproben erscheinen, Alter angezeigt | ____ |
| Lesen von Puls testweise ablehnen | kein erfundener Puls; Anfrage-Erfolg wird nicht als Leserecht behauptet | ____ |
| Training-Schreibrecht ablehnen | verständlicher Fehler, keine aktive Scheinsitzung | ____ |
| Uhr bewegen | Motion-Zeilen mit realen Achsenwerten; Status aktiv | ____ |
| Training beenden | Sensoren aus, Workout gespeichert oder Fehler sichtbar | ____ |
| Datei zum iPhone übertragen | JSONL lokal sichtbar und unter Windows exportierbar | ____ |
| iPhone nicht erreichbar, später wieder verbinden | Datei bleibt auf Watch; Retry/Bestätigung möglich | ____ |

Nur nach bestandenem Sensor-/Installationstest „Sensortest bestanden“ bestätigen.

## Etappe B: Lernversion und Timer

| Schritt | Erwartung | Ergebnis |
|---|---|---|
| Satz starten | „Satz läuft“, genau eine Startmarkierung | ____ |
| Satz fertig | sofort „Pause“, Countdown beginnt bei 180 s | ____ |
| Wiederholt auf Satzende tippen | kein zweiter Timer; Deadline unverändert | ____ |
| Pause bis Ende | „Pause beendet“, genau eine kurze Vibration | ____ |
| Pause abbrechen / neuen Satz starten | alter Countdown weg, neuer Satz armiert | ____ |
| Gesamtes Training während Pause beenden | Sensoren stoppen, kein späterer Pausenimpuls | ____ |
| Training ohne Satzmarkierung beenden | ordentliche Sensor-Datei; kein erfundenes Satzende | ____ |
| App beenden / Watch neu starten | unterbrochene Daten gekennzeichnet; kein still fortgesetzter Timer | ____ |
| Große Systemschrift / VoiceOver | alle großen Tasten lesbar/bedienbar, Status nicht allein über Farbe | ____ |

### Handgelenk- und Hintergrundmessung

Aktive Workout-Sitzung bleibt **auch in der Pause** bestehen. Keine Apple-Workout-App parallel starten: eine konkurrierende Trainingssitzung kann die eigene beenden oder stören. Gerätefehler dokumentieren.

1. Externe Stoppuhr bereithalten. Auf der Watch Training und Satz starten, nach mindestens 10 s Satzende markieren.
2. Uhr mindestens 180 s gesenkt halten. Zeitpunkt der **gefühlten** Vibration extern messen; erst danach Uhr anheben. Sichtbare UI allein beweist keine rechtzeitige Haptik.
3. Weitere Durchläufe mit Always-On an/aus, Rückkehr zum Zifferblatt, kurz anderer App, Energiesparmodus an/aus, iPhone außer Reichweite. Jede Bedingung getrennt notieren.
4. Mindestens einen echten 30–60-min-Trainingsdurchlauf mit Satz/Pause/Gehen aufnehmen. Akkustand zu Beginn/Ende messen; tatsächliche Trainingsdauer notieren.
5. JSONL lokal auswerten:

```powershell
python scripts/summarize_session.py 'C:\Pfad\Sitzung.jsonl'
```

6. Report und tatsächliche Haptik vergleichen: `deadline_duration` ≈180 s, `callback_lateness_seconds` separat. Erwartete Callback-Verspätung normalerweise etwa 0–1 s; längere Verzögerung ist ein offener Fehler, keine garantierte Präzision. `max_motion_gap_seconds` und Pulsaktualität prüfen. Ein Scene-Wechsel approximiert App-Zustand, nicht exakt „Handgelenk gesenkt“.

| Bedingung / Sitzung | Dauer | Motion-Rate / max. Lücke | Puls fehlend/veraltet | Callback verspätet | Haptik tatsächlich gefühlt | Akku vorher/nachher |
|---|---|---|---|---|---|---|
| Display aktiv | ____ | ____ | ____ | ____ | ____ | ____ |
| Handgelenk gesenkt | ____ | ____ | ____ | ____ | ____ | ____ |
| Zifferblatt / andere App | ____ | ____ | ____ | ____ | ____ | ____ |
| Energiesparen | ____ | ____ | ____ | ____ | ____ | ____ |

Ohne solche Messungen keine Aussage „läuft zuverlässig im Hintergrund“. Bei Aussetzern mit einem zugänglichen Mac Xcode/Instruments-CPU-Bericht und Geräte-Logs prüfen. Der Cloud-Build kann diese Hardwaremessung nicht ersetzen.

## Erneuerung separat abnehmen

Vor Profilablauf dieselbe IPA mit gleichem Konto/IDs erneuern. Danach Watch-App starten und eine Sensorsitzung beenden. Ein erfolgreiches iPhone-Refresh zählt nicht als bestandene Watch-Erneuerung.

- Erneuerung vor Ablauf, lokale Dateien erhalten: ____
- Watch-Profil ebenfalls erneuert / neues Ablaufdatum: ____
- Watch-Start und Sensortraining nach Erneuerung: ____

## Etappe C: ML

Erst nach mehreren echten manuellen Lernaufnahmen. Validation/Test-Metriken und Baseline vergleichen. Bei Exportkriterien-Verletzung kein Automatikmodus. Lokaler Modellimport/Watch-Kompilierung separat prüfen. Kontrollierte Durchläufe mit unterschiedlichen Übungen, kurzen Wiederholungspausen, Gehen/Gerätewechsel durchführen. Anfang bleibt manuell.

- Echte vollständige Sitzungen / Satzenden: ____
- Validation: Fehlalarme/h, verpasst, p95-Verzögerung: ____
- Unangetasteter Test: dieselben Metriken: ____
- Vergleich Baseline: ____
- Core-ML-Version / Export / numerische Parität: ____
- Watch-Kompilierung und Featureformat: ____
- Fehlalarme / verpasste Enden / Verzögerung auf Uhr: ____
- Manueller Eingriff jederzeit möglich: ____

Freigabeentscheidung mit Datum: ____
