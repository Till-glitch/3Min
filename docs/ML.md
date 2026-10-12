# ML â€“ erst nach Installation und echter Lernphase

Es wird kein Modell ausgeliefert. `LocalDetector` bleibt ohne gÃ¼ltig importiertes Modell im Lernmodus. Eine Bewegungsschwelle existiert nur als ausdrÃ¼cklich bezeichnete **Baseline** der Offline-Auswertung.

## Windows-Training ohne externe Pakete

Python 3.10+ genÃ¼gt. Echte JSONL-Dateien aus mehreren vollstÃ¤ndigen Trainings lokal in `data/learning/` ablegen. Rohdaten, Sitzungskennungen, Hashes und Trainingsberichte nicht ins Repository stellen.

```powershell
python -m unittest discover -s Tests/Python -v
python ml/pipeline.py data/learning --output models/run
```

Ohne mindestens sechs Sitzungen und 60 manuelle Satzenden erzeugt die Pipeline **kein Modell**. Training braucht mindestens 30 Enden, Validation und Test jeweils fÃ¼nf, jede Partition beide Klassen. Mindestzahlen sind keine statistische Garantie. Bei einem abgewiesenen Split weitere vollstÃ¤ndige Sitzungen sammeln; nicht zufÃ¤llig Fenster umsortieren, um ein besseres Ergebnis zu erhalten.

Ausgaben: `trained.json` (gelernte Logistikregressionsgewichte, Normierung, Featureversion, Split, SHA-256 je Eingabedatei), `metrics.json` (ML/Baseline-Ereignismetriken, Split, keine automatische Freigabe). Beide bleiben lokal. Training ist eine echte, klassengewichtete Logistikregression mit L2-Regularisierung und Gradientenverfahren. Standardisierung wird nur auf Trainingsdaten gelernt und fÃ¼r Export in Gewichte/Bias eingefaltet. Kein untrainiertes Netz, keine erfundenen Trainingsdaten.

## Zeitfenster und Labels

Kausales 8-s-Fenster, Schritt 1 s, erwartete 200 Motion-Samples bei 25 Hz. Reihenfolge der zwÃ¶lf Merkmale ist in Swift und Python identisch (`window-v1`):

1. Mittelwert des Betrags der User-Acceleration.
2. Populationsstandardabweichung dieses Betrags.
3. Mittelwert letzte 4 s minus erste 4 s (Acceleration).
4. Mittelwert des Drehratenbetrags.
5. Dessen Populationsstandardabweichung.
6. Ã„nderung letzte/erste HÃ¤lfte (Drehrate).
7. Letzter frischer Puls / 200, sonst 0 mit Missing-Flag.
8. Pulsverlauf Ã¼ber bis zu 30 s: `(letzter - erster BPM) / Zeitdifferenz / 10`, nur mit frischem letzten und mindestens 1 s Abstand; sonst 0.
9. `hr_missing`: 1 bei fehlendem oder Ã¼ber 10 s altem Puls, sonst 0.
10. Messalter, auf 30 s begrenzt / 30; ohne Messung 1.
11. Abdeckung `min(1, vorhandene Samples/200)`.
12. GrÃ¶ÃŸter Abstand einschlieÃŸlich FensterrÃ¤ndern, begrenzt auf 8 s / 8.

Offline dÃ¼rfen Puls- und Bewegungsproben nur ab ihrer **Empfangszeit** benutzt werden. Das verhindert, dass verspÃ¤tet gelieferte Samples beim Training wie frÃ¼her verfÃ¼gbar aussehen. Featurefunktionen sind gespiegelt; Tests enthalten denselben analytischen konstanten Bewegungsfall fÃ¼r Swift und Python. Konvertierung kontrolliert zusÃ¤tzlich die numerische ModellparitÃ¤t auf macOS.

Positive Klasse: Fenster-Endzeit liegt zwischen manuell markiertem Satzende und 12 s danach. Alle Ã¼brigen Fenster negativ, einschlieÃŸlich Wiederholungspausen/Gehen auÃŸerhalb dieses Bereichs. Manuelle Labels haben Reaktionszeitfehler; konsequent markieren. Die erste Version unterscheidet â€žSatzendeâ€œ und â€žkein Satzendeâ€œ, keine verlÃ¤ssliche Ãœbungsklassifikation.

## Kein Leakage zwischen Training und Test

Deterministischer Split (Seed 42) anhand vollstÃ¤ndiger Sitzungs-UUIDs: ungefÃ¤hr 60% Training, 20% Validation, 20% Test; ganze Sitzungen bleiben zusammen. Keine Ã¼berlappenden Fenster derselben Sitzung in verschiedenen Partitionen. Duplicate-UUIDs werden abgewiesen. Bei spÃ¤ter mehreren Nutzern zusÃ¤tzlich Nutzergruppen trennen.

Hyperparameter (8-s-Fenster, L2 0.001, Schrittweite 0.08, 400 Iterationen, Wahrscheinlichkeit 0.8) sind fÃ¼r den ersten Versuch vorgegeben. Nach Ã„nderungen anhand der Validation **neue, unangetastete Testsitzungen** verwenden. Den bisherigen Test wiederholt zu optimieren wÃ¼rde ihn faktisch in Validation verwandeln.

## Auswertung der tatsÃ¤chlichen Ereignisse

Die Pipeline simuliert dieselbe konservative Erkennungspolitik wie die Uhr: manueller Satzanfang armiert, mindestens 8 s Satzdauer, Abdeckung â‰¥70%, drei zusammenhÃ¤ngende positive 1-s-Fenster (`2 s` zwischen erstem und letztem), danach einmal disarmieren. Wieder scharf wird die Erkennung erst beim nÃ¤chsten manuellen Satzstart. Gehen/GerÃ¤tewechsel ohne Start kann keinen Timer auslÃ¶sen. In der Watch-App startet nur der ZustandsÃ¼bergang `setRunning â†’ rest` einen Timer; wiederholte Endsignale sind wirkungslos.

Vergleichsbaseline: Acceleration-Mittel <0.015 g und Drehraten-Mittel <0.15 rad/s, gleiche Mindestdauer/QualitÃ¤tsprÃ¼fung/BestÃ¤tigung. Das ist eine feste Bewegungsschwelle und **kein ML**.

Je Validation und Test fÃ¼r beide Verfahren:

- Fehlalarme und Fehlalarme pro Trainingsstunde.
- Ãœbersehene Satzenden, absolute Zahl und Anteil.
- Erkannte Enden, mittlere und 95%-ErkennungsverzÃ¶gerung.

Eine Erkennung wird genau einem echten Ende zugeordnet, nur innerhalb `[Satzende, Satzende +12 s]`. FrÃ¼halarm ist Fehlalarm; verhindert er das anschlieÃŸende echte Ende, zÃ¤hlt dieses zusÃ¤tzlich als Ã¼bersehen. VerzÃ¶gerung wird nur fÃ¼r zugeordnete Erkennungen gemessen. `null` bedeutet â€žkeine Beobachtungâ€œ, nicht null Sekunden. Bericht gemeinsam mit Klassen-/DatengÃ¼te betrachten; kleine Testzahlen ergeben breite Unsicherheit.

Erste Exportkriterien, vor Trainingsauswertung festgelegt: mindestens fÃ¼nf Enden je Validation/Test, â‰¤0.5 Fehlalarme/h, â‰¤10% verpasste Enden, p95-VerzÃ¶gerung â‰¤8 s. ZusÃ¤tzlich persÃ¶nlich prÃ¼fen, ob ML gegenÃ¼ber Baseline einen sinnvollen Vorteil bringt und ob Ãœbungen/Gehen reprÃ¤sentiert sind. Grenzwerte sind Produktentscheidungen, keine verÃ¶ffentlichte Leistungszusage. Scheitern sie, weitere echte Daten aufnehmen oder das Verfahren verbessern; **Lernmodus beibehalten**.

## Core-ML-Export ohne Gesundheitsdaten im Build

Apple dokumentiert [Core ML Tools fÃ¼r macOS/Linux](https://apple.github.io/coremltools/docs-guides/source/installing-coremltools.html), keine unterstÃ¼tzte native Windows-Installation. Training lÃ¤uft unter Windows; Konvertierung in einer separaten lokalen Linux-Umgebung oder auf einem zugÃ¤nglichen Mac. Eine lokale WSL2-Linux-Umgebung ist eine mÃ¶gliche Windows-Option, deren Paketinstallation hier noch nicht geprÃ¼ft wurde. Sie braucht keinen Upload. Auf einem Mac kann zusÃ¤tzlich der Core-ML-Runtime-ParitÃ¤tstest laufen. Die verlinkte Installationsseite enthÃ¤lt Ã¤ltere Versionsbeispiele; deshalb hier keine erfundene neue Version pinnen. Installierte Version dokumentieren.

In der lokalen Mac-/Linux-Shell (z.B. Python 3.11 oder 3.12 mit verfÃ¼gbarer Core-ML-Tools-Wheel):

```sh
python3 -m venv .venv-coreml
source .venv-coreml/bin/activate
python -m pip install coremltools numpy
python -c 'import coremltools; print(coremltools.__version__)'
python ml/export_coreml.py models/run/trained.json models/run/SetEnd.mlmodel --reviewed
```

`--reviewed` bestÃ¤tigt deine tatsÃ¤chliche PrÃ¼fung von Datenherkunft und Metriken. Der Export kontrolliert, dass beide Berichte denselben Split verwenden und die Mindestkriterien bestehen. Er baut ein Core-ML-Neural-Network-Format mit einem trainierten linearen Layer und Sigmoid (dieselbe Logistikregression), Input `features` (12 Zahlen), Output `probability` (1 Zahl). Ein CPU-Modell fÃ¼r lokale watchOS-AusfÃ¼hrung. Die Wahl dieses Formats vermeidet AbhÃ¤ngigkeiten von einem Ã¤lteren scikit-learn-Konverter. Linux kann die Datei erzeugen, aber Apples native Model-Prediction ist dort nicht der GerÃ¤te-Nachweis.

Danach **keine Modelldatei in GitHub Actions hochladen**:

1. `SetEnd.mlmodel` bewusst lokal aufs iPhone Ã¼bertragen, in Dateien zugÃ¤nglich machen.
2. 3Min auf iPhone â†’ â€žCore-ML-Modell lokal importierenâ€œ. Die App sendet Ã¼ber WatchConnectivity nur zur gekoppelten Uhr.
3. Das iPhone kompiliert die Datei mit `MLModel.compileModel(at:)` und überträgt die Bestandteile des kompilierten Modells zur Watch. Die Watch lädt es mit `MLModel(contentsOf:)`; sie kann Modelle nicht zur Laufzeit kompilieren. Bei Fehler bleibt sie im Lernmodus; genaue Fehlermeldung sichern. Ob das auf dem iPhone kompilierte Modell von dieser Watch geladen werden kann, ist mangels Hardware noch ungetestet; bei einem Kompatibilitätsfehler bleibt der Lernmodus aktiv.
4. Training beenden, â€žModell ladenâ€œ auswÃ¤hlen. Kandidat wird erst auÃŸerhalb aktiver Trainings zur Verwendung Ã¼bernommen; Featureversion und freigegebene Evaluierungsmetadaten mÃ¼ssen passen.
5. Nach reprÃ¤sentativem Hardwaretest â€žAutomatik freigebenâ€œ. Freigabe gilt nur bis Trainingsende/Neustart, kann also nicht unbemerkt dauerhaft bleiben. Einen Satz weiterhin manuell starten. â€žSatz fertigâ€œ bleibt verfÃ¼gbar, automatische und manuelle Enden starten denselben Timer.

Auch ein gutes Offline-Ergebnis kann echten GerÃ¤tewechsel oder seltene Ãœbungen falsch beurteilen. Nach dem Import zuerst kontrolliert prÃ¼fen, sofort manuell eingreifen und die Prediction-/Marker-Dateien auswerten. Automatisch erzeugte Enden nicht als Ground Truth in die nÃ¤chste Trainingsrunde aufnehmen; dafÃ¼r neue rein manuelle Lernaufnahmen verwenden. Ohne Modell oder bei Inferenzfehler bleibt/kehrt die App in den manuellen Lernbetrieb zurÃ¼ck.
