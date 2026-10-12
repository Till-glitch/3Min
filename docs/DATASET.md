# Datensatz 3Min / Schema 1

Eine UTF-8-Datei je Sitzung, `<session_id>.jsonl`, eine JSON-Zeile je Ereignis. JSONL ist unabhängig von Excel/Python und vermeidet Dezimalkomma-/CSV-Probleme. Dateien enthalten Gesundheitsdaten, Bewegungsdaten und Zeitangaben. Nur lokal aufbewahren und bewusst exportieren.

## Zeitbasis und Felder

Jede Zeile enthält `kind`, `session_id` (zufällige UUID), `seq` (ab 0 lückenlos), `t` (Sekunden seit Sitzungsstart). Sitzungsbeginn speichert `utc_start`. Reihenfolge der Zeilen ist Schreib-/Empfangsreihenfolge; Sensor-Zeitstempel können bei verspäteter Lieferung davon abweichen. Deshalb nach Zeit sortieren, nicht die Schreibreihenfolge als physikalische Messreihenfolge annehmen.

- Zeitbasis: `ProcessInfo.systemUptime`, an Sitzungsstart verankert. Core-Motion-Zeitstempel werden durch Subtraktion des Start-Uptime auf dieselbe Basis gebracht.
- HealthKit liefert Datumswerte. `sample_t` = `sample.endDate - session.startDate`, `t` ist hier die **Empfangszeit**. `sample_utc` bleibt für Diagnose erhalten. `wall_clock_offset` vergleicht aktuelle Wanduhr mit monotoner Sitzungsdauer. Bei Abweichung über 2 s oder ungültigem/futuristischem Sample-Zeitpunkt ist `valid_time=false`; das Sample bleibt im Export, geht aber nicht ins Modell ein. Nach einer systematischen Uhränderung sind Pulsmerkmale bis zu einer neuen Sitzung möglicherweise ungültig.
- Zeitpunkte und Markierungen werden ohne UI-Framerate gespeichert. Pause-Endzeitpunkt = monotone Zeit des Satzendes + 180. Verzögerte UI-/Timer-Callbacks verlängern den berechneten Countdown nicht, können aber das **tatsächliche Haptikereignis** verzögern; dieses Verhalten messen.
- Fehlende Werte erscheinen als `null` oder fehlen bei Ereignissen, denen das Feld nicht zugeordnet ist. Niemals Puls interpolieren oder eine Lücke mit einer angeblichen Messung füllen.

## Ereignisse

| `kind` | Zusätzliche Felder / Bedeutung |
|---|---|
| `session_start` | `schema=1`, `utc_start`, `motion_hz=25`, `rest_seconds=180`, `hr_stale_seconds=10`, `clock`, `mode=installation/learning`, `feature_version`, `os`, `app_version`, optionale `exercise` (anfangs leer) |
| `settings` | `watch_model`, `wrist`, `automatic`, `model_status`, Schwellwert/Bestätigungszeit/Mindestdauer/Mindestabdeckung |
| `motion` | `ax/ay/az`: Core Motion **userAcceleration** ohne Gravitation, in g; `rx/ry/rz`: Drehrate in rad/s. `t` ist Messzeit, `received_t` Empfangszeit. Angefragt: 25 Hz, tatsächliche Rate messen. Nur Device Motion, wenn verfügbar. |
| `heart` | `bpm`, `sample_t`, `sample_utc`, `wall_clock_offset`, `valid_time`; `t` ist Empfangszeit. Pulsabfrage über HealthKit während aktiver Workout-Sitzung. |
| `status` | `phase`, `heart_age` oder null, `heart_fresh`, `motion_age` oder null, `automatic`, `learning`; ungefähr einmal pro Sekunde, nicht als Sensormessung behandeln |
| `set_start` | `set_number`, `source=manual` |
| `set_end` | `set_number`, `source=manual/model`; **nur manuell markierte Enden** als Ground Truth |
| `rest_start` | `deadline_t`, `set_number` |
| `rest_cancelled` | vorige `set_number`; danach beginnt neuer Satz |
| `rest_finished` | `set_number`, tatsächliche Callback-Zeit `t` |
| `haptic_requested` | `type=rest_end`; Softwareaufruf, kein Nachweis einer gefühlten Vibration |
| `activity` | `name=walk_or_equipment_change`; Nutzer markiert Gehen/Gerätewechsel für spätere Datenanalyse |
| `scene` | `value=active/inactive/background`; App-Lifecycle, **kein präziser Handgelenk-Sensor** |
| `workout_state` | nativer HealthKit-State als `value` |
| `workout_saved` | Health-Builder hat erfolgreich abgeschlossen |
| `prediction` | `probability`, `features` (12 Werte), `feature_version` |
| `sensor_error`, `model_error` | Sensor/Fehlermeldung |
| `session_stop_requested` | `phase` beim expliziten Beenden |
| `session_end` | `reason=user/interrupted/<Fehlermeldung>`, `phase`; beendet die Datei |

`heart_fresh` gilt bis einschließlich 10 s nach tatsächlicher Messung. Auf der Uhr erscheint ein alter Wert mit „Puls veraltet“, nicht als neue Messung. Im Modell sind stale/fehlende Pulsmerkmale nullwertkodiert **mit explizitem Missing-Feature**, nicht als erfundene Null-bpm-Messung. Alte/zeitlich ungültige Heart-Zeilen bleiben für QA erhalten.

## Speicherung und Übertragung

Auf der Uhr: Documents/Sessions. JSON-Zeilen werden gepuffert, mindestens je Sekunde/Markierung synchronisiert; ein Absturz kann das letzte ungeschriebene Intervall verlieren. Schreibfehler werden sichtbar und beenden die Sitzung. Ein unterbrochenes Dateiende wird beim nächsten Start repariert und `reason=interrupted` gesetzt. Timer werden nach Absturz/Neustart nicht still fortgesetzt.

Auf dem iPhone: Documents/Sessions, atomarer Empfang, Dateifreigabe über iTunes und die Dateien-App, zusätzlich ShareLink. WatchConnectivity-Dateiübertragung braucht keine unmittelbare Reachability. Die Uhr behält die lokale Kopie; erst nach erfolgreichem iPhone-Schreiben bestätigt das iPhone die UUID. Fehlgeschlagene Übertragungen lassen sich erneut vormerken. App-Neustart versucht geschlossene, unbestätigte Dateien erneut. Dateien werden beim Transfer nicht in den Cloud-Build hochgeladen.

Warte bis zum Ende der Sitzung; aktive Dateien werden nicht versendet. Modelldateien verwenden einen getrennten Transfer-Typ, keine Sitzung. Keine automatische Cloud-Synchronisation implementiert. Bei bewusstem Teilen in einen Cloud-Speicher entscheidet die gewählte iOS-Teilen-Aktion über den Upload; für lokale Windows-Übertragung iTunes-Dateifreigabe nutzen.

## Lernaufnahmen

Sätze exakt markieren, Uhr am üblichen Handgelenk tragen. Auch Pausen, kurze Unterbrechungen zwischen Wiederholungen, Gehen, Gerätewechsel und ruhige Phasen erfassen. „Gehen / Gerätewechsel markieren“ ergänzt Kontext; die Labels der ersten Pipeline entstehen aus manuellen Satzmarkierungen. Mehrere Trainingstage, Übungen und Intensitäten aufnehmen. Sechs Sitzungen/60 Enden sind ein **Mindestfilter**, keine Aussage über verlässliche Modellqualität.

Die Pipeline verwirft unvollständige/abgebrochene/fehlerhafte Sitzungen, offene oder widersprüchliche Satzmarkierungen, fehlende Klassen und Sitzungen mit Modell-Endmarkierungen. Trainingsdaten müssen vollständige echte Sitzungen sein; keine künstlichen Ergänzungen verwenden. Kopien derselben Sitzung zählen nicht als neue Daten.

Zur Hardware-QA lokal ausführen:

```powershell
python scripts/summarize_session.py 'C:\Pfad\Sitzungs-ID.jsonl'
```

Der Bericht nennt gemessene mittlere Bewegungsrate, maximale Lücke, Pulsaktualität und Haptik-Callback-Verspätung. Mittlere Rate allein kann Lücken verdecken; maximale Lücke und Handgelenk-Testprotokoll gemeinsam bewerten.
