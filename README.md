<p align="center"><img src="Resources/Logo/logo-256.png" width="160" alt="Helferlein-Logo: zwei papierweiße Hände auf orangem Grund"></p>

<h1 align="center">Helferlein</h1>
<p align="center"><b>Dein lokaler Sprach-Assistent für den Mac.</b><br>Er fragt beim Login, ob du Hilfe brauchst. Er schreibt Briefe, PDFs und Präsentationen und sucht im Internet. Alles läuft auf deinem Mac, nichts geht in eine Cloud.</p>

---

## So fühlt es sich an

1. **Einloggen.** Rechts oben unter der Menüleiste geht ein Fenster auf, und Helferlein fragt per Stimme: *„Brauchst du heute Hilfe?“*
2. **Antworten.** Du kannst einfach reden. Willst du lieber tippen, drück **Enter**: Er wird still, und du schreibst.
3. **Er erledigt es.** Ein Brief öffnet sich in **Word**, ein PDF in **PDF Acrobat**, Folien in **PowerPoint**. Eine Suche öffnet sich im **Brave Browser**.
4. **Stille?** Nach 7 Sekunden fragt er nach: *„<Vorname>, hörst du mich?“* Kommt wieder nichts, wird er still und wartet oben in der Menüleiste.

## Einrichtung beim ersten Start

Jeder richtet sich Helferlein selbst ein, das dauert eine Minute:

| Schritt     | Auswahl |
|-------------|---------|
| **Vorname** | So spricht er dich an. |
| **Wofür**   | Briefe & Formulare, Arbeit, Schule & Studium, Verein, Privates & Hobby, Einkaufen & Rezepte, oder in eigenen Worten. |
| **Programme** | Word, PDF Acrobat, PowerPoint, Internet. Was du abwählst, fasst er nicht an. |
| **Stil**    | 😊 **Casual**: locker wie ein guter Freund<br>🧘 **Ruhig & genau**: langsam, Schritt für Schritt<br>😄 **Witzig**: hilft mit Augenzwinkern<br>😈 **Ehrenlos**: frech, roastet dich liebevoll (Dokumente bleiben trotzdem seriös) |

Jeden Stil kann man vorher mit 🔊 probehören. Ändern lässt sich alles später über das **Zahnrad** im Fenster.

> **Programmnamen:** Word ist [WordCraft](https://getartcraft.com/apps/wordcraft), PDF Acrobat ist [PdfCraft](https://github.com/storytold/pdfcraft/wiki), PowerPoint ist [DeckCraft](https://getartcraft.com/apps/deckcraft). Das sind kostenlose Open-Source-Apps von ArtCraft. Sie öffnen ganz normale .docx-, .pdf- und .pptx-Dateien. Fehlt eine davon, öffnet Helferlein die Datei in der Standard-App.

## Installation

**Voraussetzung:** Mac mit Apple Silicon (M1 oder neuer) und mindestens 16 GB RAM empfohlen, macOS 13 oder neuer.

1. **Einmalig mit Admin-Account:**
   - `xcode-select --install` ausführen (Command Line Tools).
   - Word, PDF Acrobat und PowerPoint installieren, also WordCraft, PdfCraft und DeckCraft, am einfachsten über den [ArtCraft Launcher](https://github.com/storytold/craft-launcher).
   - Optional [Brave](https://brave.com) installieren.
2. **Im Account der Person, die Helferlein benutzen soll:**
   ```bash
   git clone https://github.com/KimJongUnNK/helferin.git ~/helferlein
   ~/helferlein/scripts/install.sh
   ```
   Das Skript:
   - installiert Ollama und lädt das Sprachmodell (ca. 4,7 GB),
   - richtet das Dokument-Werkzeug ein,
   - findet die Programme automatisch,
   - prüft die Stimme,
   - baut die App mit Logo,
   - startet sie und richtet den Autostart ein.
3. Beim ersten Start **Mikrofon** und **Spracherkennung** erlauben, dann einrichten.
4. Prüfen: `~/helferlein/scripts/selftest.sh`

**Nur für diesen Account:** Helferlein landet in `~/Applications`, und der Autostart gilt nur für den Account, in dem `install.sh` lief. Andere Accounts auf demselben Mac bekommen nichts davon mit.

**Schönste Stimme:** Systemeinstellungen → Bedienungshilfen → Gesprochene Inhalte → Systemstimme → Stimmen verwalten → Deutsch → **Anna (Premium)** laden. Helferlein nimmt automatisch die beste weibliche deutsche Stimme.

**Komplett offline:** Systemeinstellungen → Tastatur → **Diktat** einschalten, Sprache Deutsch. Dann läuft auch die Spracherkennung auf dem Gerät.

## Was er kann

| Du sagst …                                   | Helferlein …                                                         |
|----------------------------------------------|----------------------------------------------------------------------|
| „Schreib einen Brief an die Gemeinde …“       | erstellt eine .docx in `Dokumente/Helferlein` und öffnet sie in Word |
| „Mach mir die Einladung als PDF“              | erstellt ein .pdf und öffnet es in PDF Acrobat                       |
| „Mach eine Präsentation über unseren Urlaub“  | erstellt eine .pptx (Titel + 4–8 Folien) und öffnet sie in PowerPoint |
| „Öffne meinen Brief an die Gemeinde“          | sucht in Dokumente, Schreibtisch, Downloads und iCloud und öffnet ihn |
| „Wie wird das Wetter morgen?“                 | öffnet eine Brave-Suche                                              |
| „Mach orf.at auf“                             | öffnet die Seite in Brave                                            |
| „Nein danke“                                  | verabschiedet sich, das Fenster geht zu                              |

**Grenzen:** Er öffnet Webseiten nur, lesen kann er sie nicht. Er schickt keine E-Mails und kauft nichts. Bei Geld und Passwörtern warnt er vor Betrug.

## Einstellungen für Bastler

- `~/Library/Application Support/Helferlein/profile.json`: Name, Zweck, Programme, Stil. Wird bei der Einrichtung geschrieben.
- `~/Library/Application Support/Helferlein/config.json`: Technik, siehe unten. Wirkt nach einem Neustart der App.

```json
{
  "model": "qwen2.5:7b",
  "wordApp": "WordCraft",
  "pdfApp": "PDFCraft",
  "deckApp": "DeckCraft",
  "browserApp": "Brave Browser",
  "speechRate": 0,
  "voiceName": "",
  "noSpeechSeconds": 7,
  "maxReprompts": 1
}
```

- **`speechRate`:** `0` heißt, das Tempo kommt vom Stil. Sonst 0,4 (ruhig) bis 0,55 (flott).
- **`voiceName`:** fester Stimmenname, z. B. `"Anna (Premium)"`.
- **`noSpeechSeconds`:** Sekunden Stille bis zur Nachfrage.
- **`maxReprompts`:** wie oft er nachfragt, 0 = nie.

## Aufbau

```
Sources/Helferlein/
  main.swift / AppDelegate.swift   Menüleiste, Fenster, Enter = leise
  Profile.swift                    Profil, Programme (Word/PDF/PowerPoint/Internet), 4 Stile
  OnboardingView.swift             Einrichtung beim ersten Start + Zahnrad
  ChatView.swift / Orb.swift       Chat-Oberfläche, animierte Status-Kugel
  Assistant.swift                  Gesprächsablauf, Nachfragen bei Stille, Aktionen
  Speech.swift                     weibliche Stimme, Zuhören, Mikrofon-Pegel
  Ollama.swift / Prompt.swift      lokales Modell mit erzwungener JSON-Antwort
  Actions.swift                    Dateien bauen und öffnen, Brave
helper/craftdocs.py                .docx/.pdf/.pptx erzeugen (mit Tests)
Resources/Logo/                    Logo als SVG + PNG (wird zum App-Icon)
scripts/                           install, build-app, selftest, uninstall
```

## Deinstallieren

```bash
~/helferlein/scripts/uninstall.sh
```

Die Dokumente in `~/Documents/Helferlein` bleiben erhalten.
