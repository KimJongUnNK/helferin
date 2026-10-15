<p align="center"><img src="Resources/Logo/logo-256.png" width="160" alt="Helferlein-Logo: zwei papierweiße Hände auf orangem Grund"></p>

<h1 align="center">Helferlein</h1>
<p align="center"><b>Dein lokaler Sprach-Assistent für den Mac.</b><br>Er fragt beim Login, ob du Hilfe brauchst, schreibt Briefe, Tabellen, PDFs und Präsentationen, öffnet deine Programme und sucht im Internet. Alles läuft auf deinem Mac, nichts geht in eine Cloud.</p>

---

## Download (ohne Terminal)

1. Unter **[Releases](../../releases/latest)** die Datei **Helferlein.dmg** laden.
2. Öffnen und Helferlein auf **Programme** ziehen.
3. Helferlein starten. Beim ersten Mal sagt macOS, dass die App „nicht überprüft“ werden kann. Dann: **Systemeinstellungen › Datenschutz & Sicherheit › „Dennoch öffnen“**.
4. Helferlein bereitet sich einmalig selbst vor: Es lädt das KI-Programm Ollama und das Sprachmodell (ca. 5 GB) und findet deine Programme. Danach geht es ohne Internet.

**Voraussetzungen:** Mac mit Apple-Chip (M1 oder neuer), macOS 13 oder neuer, 16 GB RAM empfohlen.

## So fühlt es sich an

1. **Einloggen.** Rechts oben unter der Menüleiste geht ein Fenster auf, und Helferlein fragt: *„Brauchst du heute Hilfe?“*
2. **Reden oder tippen.** Mit **Enter** wird er still und du schreibst. Mit **„Sprechen“** redest du wieder.
3. **Er erledigt es.** Brief in **Word**, Tabelle in **Excel**, Folien in **PowerPoint**, PDF in **PDF Acrobat**, Suche in **Brave**.
4. **Stille?** Nach 7 Sekunden fragt er: *„\<Vorname\>, hörst du mich?“* Bleibt es still, wartet er oben in der Menüleiste.

## Einrichtung beim ersten Start

| Schritt       | Auswahl |
|---------------|---------|
| **Vorname**   | So spricht er dich an. |
| **Wofür**     | Briefe & Formulare, Arbeit, Schule & Studium, Verein, Privates & Hobby, Einkaufen & Rezepte, oder in eigenen Worten. |
| **Programme** | Die ganze ArtCraft-Familie (siehe unten) und das Internet. Installierte Programme sind vorausgewählt. Was du abwählst, fasst er nicht an. |
| **Stil**      | 😊 **Casual** · 🧘 **Ruhig & genau** · 😄 **Witzig** · 😈 **Ehrenlos** (frech, roastet liebevoll; Dokumente bleiben seriös). Jeden Stil kannst du mit 🔊 probehören. |

## Die Programme: ArtCraft-Familie

Helferlein nennt die kostenlosen Open-Source-Apps von [ArtCraft](https://github.com/storytold) so, wie man sie kennt:

| Helferlein sagt | App | Was er damit macht |
|---|---|---|
| **Word** | WordCraft | Briefe, Listen, Texte **erstellen**, Rechtschreibung **korrigieren**, öffnen |
| **Excel** | GridCraft | Tabellen **erstellen** (Haushaltsbuch, Listen mit Summen), öffnen |
| **PowerPoint** | DeckCraft | Präsentationen **erstellen**, öffnen |
| **PDF Acrobat** | PdfCraft | PDFs **erstellen**, öffnen |
| **Photoshop** | PhotoCraft | starten, Bilder öffnen |
| **Lightroom** | LightCraft | starten, RAW-Fotos öffnen |
| **Illustrator** | VectorCraft | starten, SVG/AI öffnen |
| **InDesign** | DesignCraft | starten, Layouts öffnen |
| **Premiere** | FilmCraft | starten, Videos öffnen |
| **After Effects** | EffectCraft | starten |
| **Pro Tools** | SoundCraft | starten, Audio öffnen |
| **AutoCAD** | CADCraft | starten, DWG/DXF öffnen |
| **Figma** | FigCraft | starten |
| **Internet** | Brave Browser | suchen (Brave Search), Webseiten öffnen |

Am einfachsten installierst du alles über den [ArtCraft Launcher](https://github.com/storytold/craft-launcher). Manche Apps (z. B. DeckCraft bei .pptx) nehmen Dateien nur über ihren eigenen „Öffnen“-Dialog an. Dann öffnet Helferlein die Datei darüber. Dafür braucht er einmalig die Erlaubnis **Bedienungshilfen** (Zahnrad › „Dateien automatisch öffnen“).

## Word auf Deutsch (WordCraft mit deutscher Rechtschreibprüfung)

WordCraft prüft von sich aus Englisch, Polnisch, Portugiesisch, Italienisch, Kroatisch, Türkisch, Russisch und Tschechisch, aber kein Deutsch. Deutscher Text ohne Sprachangabe wird deshalb als **US-Englisch** rot markiert. Das **Deutsch-Paket** behebt das:

- Es fügt Deutsch als echte Prüfsprache ein, mit Komposita („Haustürschlüssel“) und Vorschlägen („Gebutstag“ → „Geburtstag“).
- Es lädt die deutschen Wörterbücher (Österreich, Deutschland, Schweiz; igerman98) nach `~/Library/Spelling`.
- WordCraft startet danach auf Deutsch, und neue Dokumente sind Deutsch.

**Installieren:** In Helferlein **Zahnrad › „Word auf Deutsch“ › Installieren**, oder im Terminal:

```bash
~/helferlein/extras/wordcraft-deutsch/install.sh            # installieren / nach WordCraft-Update erneut
~/helferlein/extras/wordcraft-deutsch/install.sh --restore  # Original zurück
```

Das Skript nimmt die fertig gebaute Version aus den Releases. Ist keine erreichbar, baut es WordCraft selbst aus dem Quellcode (Rust wird dann nur für deinen Benutzer installiert). Den Patch selbst findest du unter [`extras/wordcraft-deutsch/wordcraft-deutsch.patch`](extras/wordcraft-deutsch/wordcraft-deutsch.patch).

Zusätzlich kann Helferlein jedes Word-Dokument mit der deutschen Rechtschreibprüfung von macOS korrigieren. Sag einfach *„Korrigier meinen Brief“*. Er speichert dann eine korrigierte Kopie und zeigt dir jede Änderung.

## Einstellungen (Zahnrad)

- **Profil & Programme:** Name, Zweck, Programme und Stil ändern.
- **Mikrofon:** Mikrofon wählen und mit Pegelanzeige testen.
- **Stimme:** Hinweis, wie du **Anna (Premium)** lädst.
- **Word auf Deutsch:** das Deutsch-Paket installieren oder nach einem WordCraft-Update erneut ausführen.
- **Dateien automatisch öffnen:** die Erlaubnis Bedienungshilfen erteilen.
- **Beim Anmelden starten:** Autostart an oder aus.
- **Alles neu starten:** Wenn etwas hängt, beendet das die KI und Helferlein und startet beides frisch.

## Installation für Entwickler (aus dem Quellcode)

```bash
git clone https://github.com/KimJongUnNK/helferin.git ~/helferlein
~/helferlein/scripts/install.sh     # Ollama, Modell, Python-venv, App bauen, starten
~/helferlein/scripts/selftest.sh    # Dokument-Werkzeug, Swift-Build, Modell-Aktionen, Stimme
```

`install.sh` braucht die Xcode Command Line Tools (`xcode-select --install`). Es installiert nur für den aktuellen Account.

**Technik:** `~/Library/Application Support/Helferlein/config.json` (optional):

```json
{ "model": "qwen2.5:7b", "apps": { "powerpoint": "DeckCraft" }, "speechRate": 0,
  "voiceName": "", "noSpeechSeconds": 7, "maxReprompts": 1 }
```

## Aufbau

```
Sources/Helferlein/
  HelferleinApp.swift / AppDelegate.swift   Start, nur eine Instanz, Menüleiste, Enter = leise
  Setup.swift / SetupView.swift             Vorbereitung: Ollama, Modell (mit Fortschritt), Programme
  Profile.swift / OnboardingView.swift      Profil, ArtCraft-Programme, 4 Stile, Einrichtung
  ChatView.swift / Orb.swift                Chat, Startkarten, animierte Status-Kugel
  SettingsView.swift / LoginItem.swift      Einstellungen, Autostart, Neustart, Word auf Deutsch
  Assistant.swift                           Gesprächsablauf, Nachfragen bei Stille, Aktionen
  Speech.swift / AudioDevices.swift         Stimme, Zuhören, Mikrofon-Wahl und -Pegel
  Ollama.swift / Prompt.swift               lokales Modell mit erzwungener JSON-Antwort
  Actions.swift / Proofreader.swift         Dateien bauen/öffnen/finden, Brave, Rechtschreibkorrektur
helper/craftdocs.py                         .docx / .pdf / .pptx / .xlsx erzeugen (mit Tests)
extras/wordcraft-deutsch/                   Deutsch-Patch + Installer für WordCraft
.github/workflows/build.yml                 baut DMG + WordCraft-Deutsch, Release bei Tag v*
```

## Deinstallieren

Für die DMG-Version: die App in den Papierkorb legen. Bei der Entwickler-Installation: `~/helferlein/scripts/uninstall.sh`. Deine Dokumente in `~/Documents/Helferlein` bleiben erhalten.
