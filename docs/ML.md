# ML – erst nach Installation und echter Lernphase

Es wird kein Modell ausgeliefert. `LocalDetector` bleibt ohne gültig importiertes Modell im Lernmodus. Eine Bewegungsschwelle existiert nur als ausdrücklich bezeichnete **Baseline** der Offline-Auswertung.

## Windows-Training ohne externe Pakete

Python 3.10+ genügt. Echte JSONL-Dateien aus mehreren vollständigen Trainings lokal in `data/learning/` ablegen. Rohdaten, Sitzungskennungen, Hashes und Trainingsberichte nicht ins Repository stellen.

```powershell
python -m unittest discover -s Tests/Python -v
python ml/pipeline.py data/learning --output models/run
```

Ohne mindestens sechs Sitzungen und 60 manuelle Satzenden erzeugt die Pipeline **kein Modell**. Training braucht mindestens 30 Enden, Validation und Test jeweils fünf, jede Partition beide Klassen. Mindestzahlen sind keine statistische Garantie. Bei einem abgewiesenen Split weitere vollständige Sitzungen sammeln; nicht zufällig Fenster umsortieren, um ein besseres Ergebnis zu erhalten.

Ausgaben: `trained.json` (gelernte Logistikregressionsgewichte, Normierung, Featureversion, Split, SHA-256 je Eingabedatei), `metrics.json` (ML/Baseline-Ereignismetriken, Split, keine automatische Freigabe). Beide bleiben lokal. Training ist eine echte, klassengewichtete Logistikregression mit L2-Regularisierung und Gradientenverfahren. Standardisierung wird nur auf Trainingsdaten gelernt und für Export in Gewichte/Bias eingefaltet. Kein untrainiertes Netz, keine erfundenen Trainingsdaten.

## Zeitfenster und Labels

Kausales 8-s-Fenster, Schritt 1 s, erwartete 200 Motion-Samples bei 25 Hz. Reihenfolge der zwölf Merkmale ist in Swift und Python identisch (`window-v1`):

1. Mittelwert des Betrags der User-Acceleration.
2. Populationsstandardabweichung dieses Betrags.
3. Mittelwert letzte 4 s minus erste 4 s (Acceleration).
4. Mittelwert des Drehratenbetrags.
5. Dessen Populationsstandardabweichung.
6. Änderung letzte/erste Hälfte (Drehrate).
7. Letzter frischer Puls / 200, sonst 0 mit Missing-Flag.
8. Pulsverlauf über bis zu 30 s: `(letzter - erster BPM) / Zeitdifferenz / 10`, nur mit frischem letzten und mindestens 1 s Abstand; sonst 0.
9. `hr_missing`: 1 bei fehlendem oder über 10 s altem Puls, sonst 0.
10. Messalter, auf 30 s begrenzt / 30; ohne Messung 1.
11. Abdeckung `min(1, vorhandene Samples/200)`.
12. Größter Abstand einschließlich Fensterrändern, begrenzt auf 8 s / 8.

Offline dürfen Puls- und Bewegungsproben nur ab ihrer **Empfangszeit** benutzt werden. Das verhindert, dass verspätet gelieferte Samples beim Training wie früher verfügbar aussehen. Featurefunktionen sind gespiegelt; Tests enthalten denselben analytischen konstanten Bewegungsfall für Swift und Python. Konvertierung kontrolliert zusätzlich die numerische Modellparität auf macOS.

Positive Klasse: Fenster-Endzeit liegt zwischen manuell markiertem Satzende und 12 s danach. Alle übrigen Fenster negativ, einschließlich Wiederholungspausen/Gehen außerhalb dieses Bereichs. Manuelle Labels haben Reaktionszeitfehler; konsequent markieren. Die erste Version unterscheidet „Satzende“ und „kein Satzende“, keine verlässliche Übungsklassifikation.

## Kein Leakage zwischen Training und Test

Deterministischer Split (Seed 42) anhand vollständiger Sitzungs-UUIDs: ungefähr 60% Training, 20% Validation, 20% Test; ganze Sitzungen bleiben zusammen. Keine überlappenden Fenster derselben Sitzung in verschiedenen Partitionen. Duplicate-UUIDs werden abgewiesen. Bei später mehreren Nutzern zusätzlich Nutzergruppen trennen.

Hyperparameter (8-s-Fenster, L2 0.001, Schrittweite 0.08, 400 Iterationen, Wahrscheinlichkeit 0.8) sind für den ersten Versuch vorgegeben. Nach Änderungen anhand der Validation **neue, unangetastete Testsitzungen** verwenden. Den bisherigen Test wiederholt zu optimieren würde ihn faktisch in Validation verwandeln.

## Auswertung der tatsächlichen Ereignisse

Die Pipeline simuliert dieselbe konservative Erkennungspolitik wie die Uhr: manueller Satzanfang armiert, mindestens 8 s Satzdauer, Abdeckung ≥70%, drei zusammenhängende positive 1-s-Fenster (`2 s` zwischen erstem und letztem), danach einmal disarmieren. Wieder scharf wird die Erkennung erst beim nächsten manuellen Satzstart. Gehen/Gerätewechsel ohne Start kann keinen Timer auslösen. In der Watch-App startet nur der Zustandsübergang `setRunning → rest` einen Timer; wiederholte Endsignale sind wirkungslos.

Vergleichsbaseline: Acceleration-Mittel <0.015 g und Drehraten-Mittel <0.15 rad/s, gleiche Mindestdauer/Qualitätsprüfung/Bestätigung. Das ist eine feste Bewegungsschwelle und **kein ML**.

Je Validation und Test für beide Verfahren:

- Fehlalarme und Fehlalarme pro Trainingsstunde.
- Übersehene Satzenden, absolute Zahl und Anteil.
- Erkannte Enden, mittlere und 95%-Erkennungsverzögerung.

Eine Erkennung wird genau einem echten Ende zugeordnet, nur innerhalb `[Satzende, Satzende +12 s]`. Frühalarm ist Fehlalarm; verhindert er das anschließende echte Ende, zählt dieses zusätzlich als übersehen. Verzögerung wird nur für zugeordnete Erkennungen gemessen. `null` bedeutet „keine Beobachtung“, nicht null Sekunden. Bericht gemeinsam mit Klassen-/Datengüte betrachten; kleine Testzahlen ergeben breite Unsicherheit.

Erste Exportkriterien, vor Trainingsauswertung festgelegt: mindestens fünf Enden je Validation/Test, ≤0.5 Fehlalarme/h, ≤10% verpasste Enden, p95-Verzögerung ≤8 s. Zusätzlich persönlich prüfen, ob ML gegenüber Baseline einen sinnvollen Vorteil bringt und ob Übungen/Gehen repräsentiert sind. Grenzwerte sind Produktentscheidungen, keine veröffentlichte Leistungszusage. Scheitern sie, weitere echte Daten aufnehmen oder das Verfahren verbessern; **Lernmodus beibehalten**.

## Core-ML-Export ohne Gesundheitsdaten im Build

Apple dokumentiert [Core ML Tools für macOS/Linux](https://apple.github.io/coremltools/docs-guides/source/installing-coremltools.html), keine unterstützte native Windows-Installation. Training läuft unter Windows; Konvertierung in einer separaten lokalen Linux-Umgebung oder auf einem zugänglichen Mac. Eine lokale WSL2-Linux-Umgebung ist eine mögliche Windows-Option, deren Paketinstallation hier noch nicht geprüft wurde. Sie braucht keinen Upload. Auf einem Mac kann zusätzlich der Core-ML-Runtime-Paritätstest laufen. Die verlinkte Installationsseite enthält ältere Versionsbeispiele; deshalb hier keine erfundene neue Version pinnen. Installierte Version dokumentieren.

In der lokalen Mac-/Linux-Shell (z.B. Python 3.11 oder 3.12 mit verfügbarer Core-ML-Tools-Wheel):

```sh
python3 -m venv .venv-coreml
source .venv-coreml/bin/activate
python -m pip install coremltools numpy
python -c 'import coremltools; print(coremltools.__version__)'
python ml/export_coreml.py models/run/trained.json models/run/SetEnd.mlmodel --reviewed
```

`--reviewed` bestätigt deine tatsächliche Prüfung von Datenherkunft und Metriken. Der Export kontrolliert, dass beide Berichte denselben Split verwenden und die Mindestkriterien bestehen. Er baut ein Core-ML-Neural-Network-Format mit einem trainierten linearen Layer und Sigmoid (dieselbe Logistikregression), Input `features` (12 Zahlen), Output `probability` (1 Zahl). Ein CPU-Modell für lokale watchOS-Ausführung. Die Wahl dieses Formats vermeidet Abhängigkeiten von einem älteren scikit-learn-Konverter. Linux kann die Datei erzeugen, aber Apples native Model-Prediction ist dort nicht der Geräte-Nachweis.

Danach **keine Modelldatei in GitHub Actions hochladen**:

1. `SetEnd.mlmodel` bewusst lokal aufs iPhone übertragen, in Dateien zugänglich machen.
2. 3Min auf iPhone → „Core-ML-Modell lokal importieren“. Die App sendet über WatchConnectivity nur zur gekoppelten Uhr.
3. Watch kompiliert die Datei mit `MLModel.compileModel`. Bei Fehler bleibt sie im Lernmodus; genaue Fehlermeldung sichern. Diese watchOS-Konvertierung ist mangels Hardware noch ungetestet.
4. Training beenden, „Modell laden“ auswählen. Kandidat wird erst außerhalb aktiver Trainings zur Verwendung übernommen; Featureversion und freigegebene Evaluierungsmetadaten müssen passen.
5. Nach repräsentativem Hardwaretest „Automatik freigeben“. Freigabe gilt nur bis Trainingsende/Neustart, kann also nicht unbemerkt dauerhaft bleiben. Einen Satz weiterhin manuell starten. „Satz fertig“ bleibt verfügbar, automatische und manuelle Enden starten denselben Timer.

Auch ein gutes Offline-Ergebnis kann echten Gerätewechsel oder seltene Übungen falsch beurteilen. Nach dem Import zuerst kontrolliert prüfen, sofort manuell eingreifen und die Prediction-/Marker-Dateien auswerten. Automatisch erzeugte Enden nicht als Ground Truth in die nächste Trainingsrunde aufnehmen; dafür neue rein manuelle Lernaufnahmen verwenden. Ohne Modell oder bei Inferenzfehler bleibt/kehrt die App in den manuellen Lernbetrieb zurück.
