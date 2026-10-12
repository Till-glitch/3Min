# Offizielle Quellen und technische Entscheidungen

Gelesen am 12.10.2026. Webseiten und Runner-Images können sich ändern; der Build protokolliert seine echte Toolchain. Keine Foren-/Reddit-Erfahrungsberichte werden als Installationsnachweis verwendet.

| Quelle | Anwendung im Projekt |
|---|---|
| [Apple: SDK and system requirements](https://developer.apple.com/xcode/system-requirements) | Xcode 26.6 enthält watchOS-/iOS-26.5-SDKs; macOS-Anforderung statt erfundener SDK-Nummern |
| [GitHub: macos-26 runner image](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md) | dokumentierter Xcode-26.6-Pfad; Workflow überprüft ihn zur Laufzeit |
| [Apple: Developer account overview](https://developer.apple.com/help/account/basics/about-your-developer-account) | Personal Team, kostenlose Nutzung, Registrierungs-/Profilgrenzen |
| [Apple: Supported capabilities watchOS](https://developer.apple.com/help/account/reference/supported-capabilities-watchos) | HealthKit ist auch für kostenlose Apple-Developer-Konten markiert; tatsächliches Provisioning bleibt zu prüfen |
| [Apple: Configuring HealthKit access](https://developer.apple.com/documentation/xcode/configuring-healthkit-access) | HealthKit-Entitlement und Health-Usage-Beschreibungen im ausführenden Watch-Target |
| [Apple: Protecting user privacy](https://developer.apple.com/documentation/healthkit/protecting-user-privacy) | Read-Ablehnung ist nicht abfragbar; Request-Erfolg kein Leserechtnachweis |
| [Apple: Running workout sessions](https://developer.apple.com/documentation/healthkit/running-workout-sessions) | echte HKWorkoutSession, Builder, explizites Starten/Beenden, Hintergrund während Satz/Pause; Audio-Modus laut Apple auch für Workout-Haptik |
| [Apple: Background execution modes](https://developer.apple.com/documentation/xcode/configuring-background-execution-modes) | `WKBackgroundModes=workout-processing`, zusätzlicher `UIBackgroundModes=audio` für Haptik laut Workout-Dokumentation; keine Wiedergabe eines stummen Dauerstreams |
| [Apple: TN3157](https://developer.apple.com/documentation/technotes/tn3157-updating-your-watchos-project-for-swiftui-and-widgetkit) | modernes Single-Target-Watch-Projekt, SwiftUI, Companion-ID und Bundle-ID-Präfix |
| [Apple: Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device), [Device pairing](https://developer.apple.com/documentation/xcode/pairing-your-devices-with-your-mac) | Aktivierung auf beiden Geräten und lokale Xcode-Paarung als dokumentierter Entwicklungsweg |
| [Sideloadly Startseite](https://sideloadly.io/), [FAQ](https://sideloadly.io/faq.html), [Changelog](https://sideloadly.io/changelog) | Windows/iOS-Sideloading und Erneuerung; keine gefundene dokumentierte Garantie für erfolgreiche Watch-Installation |
| [XcodeGen ProjectSpec](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md) | überprüfbare YAML-Projektdefinition statt handgeschriebener PBX-IDs |
| [Apple Core ML Tools: Installation](https://apple.github.io/coremltools/docs-guides/source/installing-coremltools.html) | unterstützte Konvertierungsplattformen macOS/Linux; Windows-Training getrennt, keine Gesundheitsdaten in CI |

## Berechtigungen

Das iPhone ist nur Begleiter/Dateiempfänger und fragt kein HealthKit an. Die Watch fragt das Lesen von Herzfrequenz und Schreiben von Trainings an. Nur das Watch-Target benötigt `com.apple.developer.healthkit`. Kein App Group, iCloud, HealthKit Background Delivery oder klinisches Entitlement; Workout-Hintergrundausführung ist eine andere Funktion als HealthKit-Observer-Background-Delivery. Die generierten Plists liegen nach XcodeGen unter `Config/`.

Puls wird als echte HealthKit-Probe gespeichert, mit Mess- und Empfangszeit. Der Workout-Builder sichert das Workout; eine Anchored Query liest zeitgestempelte Pulswerte. Zugriff und Lieferfrequenz müssen am Gerät überprüft werden. Bewegungsdaten kommen aus Core Motion `deviceMotion`, User-Acceleration und Drehrate; Verfügbarkeit/Fehler werden angezeigt.

## Oberfläche

Deutsche SwiftUI-Systemtexte, Systemschrift mit Dynamic Type, native ScrollView/List/Button, SF Symbols auf dem iPhone. Watch-Primäraktionen haben mindestens 44 pt Höhe, Status ist auch Text. Kein externes Font-/Icon-Download. Wenige Aktionen pro Zustand, Training-Ende mit Bestätigung, Pulsalter immer sichtbar. UI/UX-Skill: SwiftUI-Empfehlungen für semantische Buttons und Accessibility-Labels übernommen; generische Landingpage-/Webfonts-Empfehlungen waren für die Watch unpassend und wurden nicht übernommen. Layout-, VoiceOver- und große-Schrift-Prüfung auf Hardware noch offen.

## Warum die Installation nicht zugesichert ist

Die Quellen bestätigen verfügbare SDKs, Capabilities und iPhone-Sideloading. Es fehlt ein dokumentierter durchgängiger Nachweis, dass Sideloadly mit deinem freien Konto die Watch korrekt provisioniert, das enthaltene Bundle passend signiert und die Uhr es installiert. Deshalb sind Bundle-Erstellung, Signierung und tatsächlicher Geräte-Start getrennte Prüfschritte. Ein Mac-Cloud-Build ist kein Watch-Installer.
