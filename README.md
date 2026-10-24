<p align="center"><a href="https://linux-handheld-starter-kit.cocoabloom514.chatgpt.site/"><img src="assets/linux-handheld-starter-kit-logo.png" width="640" alt="Linux Handheld Starter Kit"></a></p>

<p align="center"><a href="https://www.youtube.com/@SteamDeckChecker/"><img src="assets/steam-deck-checker.png" width="180" alt="Steam Deck Checker"></a></p>

# Linux Handheld Starter Kit · 0.1.0

Geführte Ersteinrichtung für Linux-Handhelds mit
**[SteamOS](https://store.steampowered.com/steamos/), [CachyOS](https://cachyos.org/)
und [Bazzite](https://bazzite.gg/)**.

[English](README.en.md) · [Webseite](https://linux-handheld-starter-kit.cocoabloom514.chatgpt.site/de/) · [Releases](https://github.com/Steamdeckchecker/LinuxGamingStarterKit/releases) · [YouTube](https://www.youtube.com/@SteamDeckChecker/) · [Changelog](CHANGELOG.md)

Die Oberfläche nutzt **Zenity** oder **KDialog**, die Installationen laufen
einzeln und synchron. Die `install.sh` enthält den vollständigen Programmcode.
Ein Klonen des Projekts oder das Installieren von Python-Paketen ist nicht nötig.

**Entwicklungsstand:** v0.1.0 ist die erste öffentliche Testversion. Die Kernabläufe sind automatisiert
mit simulierten Systembefehlen geprüft. Tests wurden auf SteamOS, CachyOS und Bazzite durchgeführt. Die Funktion einzelner
Decky-Plugins und externer Apps hängt zusätzlich von deren eigener Unterstützung
für die jeweilige Steam-Version, Distribution und Hardware ab.

## Downloads

| Datei | Zweck |
| --- | --- |
| [Linux-Handheld-Starter-Kit.desktop](https://github.com/Steamdeckchecker/LinuxGamingStarterKit/releases/download/v0.1.0/Linux-Handheld-Starter-Kit.desktop) | Empfohlen: eigenständiger Starter per Doppelklick. |
| [install.sh](https://github.com/Steamdeckchecker/LinuxGamingStarterKit/releases/download/v0.1.0/install.sh) | Alternative für den Start im Terminal. |
| [Quellcode-ZIP](https://github.com/Steamdeckchecker/LinuxGamingStarterKit/releases/download/v0.1.0/Linux-Handheld-Starter-Kit-v0.1.0.zip) | Beide Starter, bearbeitbarer Quellcode, Webseite, Dokumentation und Tests. |
| [SHA256SUMS](https://github.com/Steamdeckchecker/LinuxGamingStarterKit/releases/download/v0.1.0/SHA256SUMS) | SHA-256-Prüfsummen für beide Starter und das ZIP. |

Nur **eine** der beiden Startdateien herunterladen.

## Starten

**Per Doppelklick:** Im Desktop-Modus nur `Linux-Handheld-Starter-Kit.desktop`
herunterladen und öffnen. Die Datei enthält den vollständigen aktuellen
Installer und öffnet ein Terminal mit Fortschrittsanzeige. Es ist keine
zusätzliche `install.sh` nötig.

Je nach Desktop muss die heruntergeladene Datei beim ersten Start als
ausführbar beziehungsweise vertrauenswürdig freigegeben werden. In KDE:
Rechtsklick → Eigenschaften → Berechtigungen → als Programm ausführbar
markieren; anschließend gegebenenfalls „Ausführen“ bestätigen. Webbrowser
können die Ausführungsberechtigung beim Herunterladen entfernen.

Die eingebettete Datei wird vor dem Start auf ihre SHA-256-Prüfsumme geprüft,
in einem privaten temporären Ordner ausgeführt und nach Ende des Assistenten
entfernt. Es wird keine weitere Starter-Kit-Datei aus dem Internet nachgeladen.
Die gewählten Pakete werden wie bisher während der Einrichtung heruntergeladen.

**Alternativ: mit einem Terminalbefehl herunterladen und starten**

In den **Desktop-Modus** wechseln und diesen Befehl als normalen Benutzer
ausführen. Über das Kopiersymbol am Codeblock lässt er sich vollständig kopieren:

```bash
curl -fL --retry 3 -o install.sh "https://github.com/Steamdeckchecker/LinuxGamingStarterKit/releases/download/v0.1.0/install.sh" && bash install.sh
```

Der Befehl speichert Version **0.1.0** als `install.sh` im aktuellen Ordner
und startet sie erst nach erfolgreichem Download. **Kein sudo voranstellen**;
die benötigte Administratorberechtigung wird innerhalb des Assistenten angefragt.
Wenn `install.sh` bereits heruntergeladen wurde, genügt `bash install.sh`.
Alternativ kann `install.sh` ausführbar gemacht und mit dem Dateimanager
gestartet werden, sofern dieser das Ausführen von Shellskripten unterstützt.

Voraussetzungen: x86_64, Bash, Python **3.9 oder neuer**, grafische Desktop-Sitzung,
**Zenity oder KDialog**, Internetzugang. Für Decky: `sudo`, `curl`, `jq`, `getent`
und `systemctl`. Für Apps: `flatpak`. Für die Passworterstellung wird ein
unterstütztes Terminal benötigt: Konsole, GNOME Terminal oder xterm.
Diese Werkzeuge sind je nach Distributionsinstallation bereits vorhanden.
Fehlende Systempakete werden gemeldet; der Installer entsperrt SteamOS nicht und
führt keine automatischen kompletten Distributions-Upgrades aus.

## Sprachen

Am Anfang stehen **Deutsch, English, Español, Français, Русский,
中文（简体） und 日本語** zur Wahl. Dialoge, Schaltflächen und die fest eingebauten
App-Beschreibungen sind übersetzt. Plugin-Beschreibungen aus dem Explorer und
Ausgaben externer Installationsprogramme bleiben in der Originalsprache.
Für Chinesisch und Japanisch muss der Desktop passende Schriftarten besitzen.
Die Systemsprache wird nicht verändert.

## Reihenfolge

| Schritt | Verhalten |
| --- | --- |
| Sprachauswahl | Sprache für diesen Durchlauf auswählen. |
| 1. Handheld | Steam Deck LCD, Steam Deck OLED, Steam Machine, MSI Claw, Legion Go oder anderer Handheld. |
| 2. Passwort | Bei fehlendem Passwort Erstellung über das native `passwd` anbieten. Bei unbekanntem/gesperrtem Status ist Setzen/Ändern ebenfalls möglich. |
| 3. Autorisierung | Das Benutzerpasswort erneut für `sudo` abfragen. Wird die Autorisierung abgelehnt, bleiben Video- und Benutzer-Flatpak-Installationen möglich. |
| 4. Startvideos | Passendes Gerät vorauswählen; alle sechs Pakete und „Keine Startvideos“ anbieten. |
| 5. Decky Loader | Aktuelle stabile Version mit dem offiziellen CLI-Installer installieren. Bei vorhandenem Decky kann direkt zur Plugin-Auswahl gewechselt werden. „Nein“ führt zu Schritt 7. |
| 6. Plugins | Alle 23 eingebetteten Empfehlungen, Auswahl aus dem Explorer oder keine Plugins. |
| 7. Apps | Gewünschte Anwendungen anhaken und einzeln installieren. Danach optional die erfolgreichen/bereits vorhandenen ausgewählten Apps zur Steam-Bibliothek hinzufügen. |
| 8. Emulation | RetroDECK, EmuDeck oder keine Emulationslösung. Danach optional die installierte Lösung als steamfremdes Spiel hinzufügen. |
| 9. Abschluss | Ergebnisse anzeigen und einen Neustart mit Ja/Nein anbieten. |
| 10. Ende | Beenden; ein Neustart erfolgt nur bei „Ja“. |

Im Terminal erscheinen die aktuellen Arbeitsschritte und Ergebnisse. Downloads
und ZIP-Entpackvorgänge zeigen ihren tatsächlichen Fortschritt; bei bekannter
Größe mit Prozent, Datenmenge und Übertragungsrate. Bei Vorgängen ohne bekannte
Gesamtgröße erscheint eine Aktivitätsanzeige mit Laufzeit. Ausgaben von Flatpak
und anderen Installationsprogrammen werden während der Ausführung angezeigt.
Beim Start aus dem Dateimanager öffnet sich nach Möglichkeit ein Terminal.

Jeder Download, jedes Entpacken und jede Installation wird abgeschlossen und
geprüft, bevor der nächste Vorgang beginnt. Bei einem Fehler erscheint eine
Meldung. Das fehlgeschlagene Paket gilt nicht als installiert; nach dem
Schließen der Meldung können die übrigen Pakete weiterverarbeitet werden.
Decky wird während der Plugin-Dateiänderungen gestoppt und danach wieder
gestartet. Bei fehlgeschlagenem Decky-Setup wird die Plugin-Installation
übersprungen; Apps und Emulation bleiben verfügbar.

## Startvideos und Steam-Pfade

| Auswahl | Quelle |
| --- | --- |
| Steam Deck LCD | <https://github.com/Steamdeckchecker/SVSDLCD> |
| Steam Deck OLED | <https://github.com/Steamdeckchecker/SVSDOLED> |
| Steam Machine | <https://github.com/Steamdeckchecker/SVSM> |
| MSI Claw | <https://github.com/Steamdeckchecker/SVMSICLAW> |
| Legion Go / Legion Go 2 | <https://github.com/Steamdeckchecker/SVLLGO> |
| Anderer Handheld | <https://github.com/Steamdeckchecker/SVOTHER> |

Bevorzugt werden ZIP-/tar.gz-Pakete oder WebM-Dateien des aktuellen Releases
geladen. Falls dort keine Videos vorliegen, wird das Repository-Archiv geprüft.
Verschachtelte Archive werden bis zu zwei Ebenen unterstützt. Es werden nur
WebM-Videos in den Zielordner kopiert, keine README- oder Installationsdateien.
Vorhandene Dateien mit gleichem Namen werden ersetzt. Andere Videos im
Zielordner bleiben erhalten. Bei mehrfach enthaltenem Dateinamen wird die
zuletzt verarbeitete Datei verwendet.

Auf einem Steam Deck ist das Ziel normalerweise:

```text
/home/deck/.steam/root/config/uioverrides/movies/
```

Auf anderen Geräten wird das tatsächliche Home-Verzeichnis und die vorhandene
Steam-Installation ermittelt. Auch `/home/fabian`, Bazzites Benutzerverzeichnis
und die üblichen Flatpak-Steam-Pfade werden berücksichtigt. Fehlende
Zielverzeichnisse werden angelegt. Ist noch keine Steam-Installation erkennbar,
werden Videos unter `~/.steam/root/config/uioverrides/movies/` abgelegt; für Decky
und Steam-Verknüpfungen muss Steam zuvor einmal gestartet und eingerichtet sein.

Nach erfolgreicher Installation erinnert ein Dialog daran, die Videos im
**Game Mode → Einstellungen → Anpassungen → Startvideo** zu aktivieren.
Die Benennung kann je nach Steam-Sprache und Steam-Version leicht abweichen.

Der Installer lädt aus dem jeweils ausgewählten Repository. Für Steam Machine
ist `Steamdeckchecker/SVSM` hinterlegt und nach der Geräteauswahl vorausgewählt.
Der Release-Dateiname muss dafür nicht dem Gerätenamen entsprechen.

## Decky-Plugins

Alle **23 Repository-Links aus `recommend.txt` sind in beiden Startdateien integriert**.
Für die empfohlene Auswahl ist keine zusätzliche Datei erforderlich. Die Datei
im Quellcode-Paket dient der Pflege: `python3 build.py` übernimmt ihren Inhalt
beim Erstellen des Installers. Für eigene Empfehlungen werden auch dieses
Format, Kommentare, Leerzeilen, UTF-8-BOM und CRLF unterstützt:

```text
# Ein Repository pro Zeile
https://github.com/Steamdeckchecker/SDC-Benchmark-
SteamGridDB/decky-steamgriddb | Artwork und Bibliotheksbilder
```

Duplikate werden ohne Beachtung der Groß-/Kleinschreibung zusammengefasst.
Eine eigene Datei kann optional über `--recommend /pfad/recommend.txt` angegeben
werden und ersetzt dann die eingebettete Auswahl für diesen Durchlauf.

Für die freie Auswahl wird der aktuelle Datensatz des
[Decky Plugins Explorer](https://safetzahirovic.github.io/decky-plugins-explorer/)
geladen, **nach GitHub-Sternen absteigend** sortiert und als Liste mit Checkboxen,
Projektname, Repository und Kurzbeschreibung dargestellt. Vorher kann nach Name,
Repository oder Beschreibung gefiltert werden. Ein leeres Suchfeld zeigt alle
Einträge.

Paketquellen in dieser Reihenfolge:

1. Installierbare ZIP-/tar.gz-Anhänge des aktuellen stabilen GitHub-Releases.
   Gibt es ausschließlich Vorabversionen, kann die neueste verwendet werden.
2. Offizieller stabiler Decky-Store mit exakt passendem Plugin-Namen **und**
   Autor. Der SHA-256-Hash wird geprüft. Das ermöglicht z. B. SteamGridDB,
   Animation Changer, Audio Loader und Wine Cellar ohne eigene Release-ZIPs.
3. Repository-Archiv, falls es bereits ein gebautes Plugin enthält.

Ein Paket benötigt `plugin.json` und `dist/index.js`. Installer-Pakete mit einem
eingebetteten Plugin-Archiv werden unterstützt; fremde Installerskripte werden
nicht ausgeführt. In `package.json` deklarierte `remote_binary`-Downloads werden
mit dem jeweiligen SHA-256-Hash geladen und ausführbar gemacht.
Reiner Quellcode ohne gebautes Frontend wird mit einer Fehlermeldung übersprungen.

Vorhandene Plugin-Versionen werden unter
`~/homebrew/.starter-kit-backups/` gesichert. Bestehende Plugin-Daten und andere
Decky-Einstellungen bleiben erhalten. Symlinks und Pfade außerhalb eines
Archivs werden beim Entpacken abgewiesen. Die Besitzrechte richten sich nach
dem `root`-Flag des Plugins, wie bei Decky.

GitHub erlaubt nur eine begrenzte Zahl an API-Anfragen ohne Anmeldung.
Optional können `GH_TOKEN` oder `GITHUB_TOKEN` bereits in der Umgebung stehen.
Der Token wird nur an die GitHub-API gesendet, nicht an weiterleitende
Download-Domains. Er wird weder in Dateien noch in Protokollen gespeichert.
Private Repositories benötigen entsprechende GitHub-Zugriffsrechte.

## Anwendungen

Alle Apps werden als **Benutzer-Flatpaks** installiert. Bereits systemweit oder
für den Benutzer installierte Apps werden erkannt und wiederverwendet.
Flathub wird bei Bedarf für den Benutzer hinzugefügt. Für GeForce NOW werden
das offizielle NVIDIA-Repository und anschließend `com.nvidia.geforcenow`
installiert; allein das Hinzufügen des Repositorys würde die App nicht installieren.

| Anwendung | Flatpak-ID |
| --- | --- |
| Heroic | `com.heroicgameslauncher.hgl` |
| ProtonUp-Qt | `net.davidotek.pupgui2` |
| Proton Plus | `com.vysp3r.ProtonPlus` |
| VacuumTube | `rocks.shy.VacuumTube` |
| Lutris | `net.lutris.Lutris` |
| Moonlight | `com.moonlight_stream.Moonlight` |
| Chiaki4deck / chiaki-ng | `io.github.streetpea.Chiaki4deck` |
| GeForce NOW | `com.nvidia.geforcenow` |
| XStreaming | `io.github.Geocld.XStreamingDesktop` |
| Flatseal | `com.github.tchx84.Flatseal` |
| Filelight | `org.kde.filelight` |
| Discord | `com.discordapp.Discord` |
| Google Chrome | `com.google.Chrome` |
| LibreOffice | `org.libreoffice.LibreOffice` |
| SuperTuxKart | `net.supertuxkart.SuperTuxKart` |
| Dr. Robotnik's Ring Racers | `org.kartkrew.RingRacers` |

Für die Steam-Integration wird Steam nach einem Hinweis regulär beendet und
auf sein vollständiges Ende gewartet. Läuft Steam noch, werden keine
Bibliotheksdateien verändert. Bei mehreren lokalen Steam-Konten wird das Zielkonto
abgefragt. Bestehende `shortcuts.vdf`-Dateien werden gesichert, existierende Spiele
und unbekannte Felder erhalten und bereits vorhandene Flatpak-Verknüpfungen
erkannt. Die Datei wird atomar ersetzt. Anschließend wartet der Installer
**drei Sekunden und startet Steam automatisch wieder** als angemeldeter
Benutzer. Er wartet auf den erkannten Start; das geöffnete Steam-Fenster muss
für die Fortsetzung des Assistenten nicht geschlossen werden.

Das gilt für Verknüpfungen der zusätzlichen Apps ebenso wie für RetroDECK und
EmuDeck. Nach deren Installation wird jeweils separat mit **Ja/Nein** gefragt.
RetroDECK startet über sein Flatpak, EmuDeck über die installierte AppImage mit
`APPIMAGE_EXTRACT_AND_RUN=1`. Bereits vorhandene passende Einträge werden nicht
erneut hinzugefügt. Wird das Speichern nach dem Beenden von Steam abgebrochen,
versucht der Installer auch im Fehlerfall, das zuvor laufende Steam wieder zu
starten.

## RetroDECK und EmuDeck

RetroDECK wird mit `flatpak install --user flathub net.retrodeck.retrodeck`
installiert. Seine erste Konfiguration erfolgt später innerhalb von RetroDECK.
Anschließend kann eine Steam-Verknüpfung für RetroDECK angelegt werden.

Für EmuDeck wird die **offizielle EmuDeck-AppImage** aus dem Release von
`EmuDeck/emudeck-electron` nach `~/Applications/EmuDeck.AppImage` geladen und
als Benutzer gestartet. Dies ist die Anwendung, die auch das verlinkte
[EmuDeck.sh](https://www.emudeck.com/EmuDeck.sh) startet. Das Starter Kit
umgeht dessen vorgeschaltete vollständige System-Upgrades und Paket-Layering,
was besonders für Bazzites unveränderliches System wichtig ist.

Die AppImage wird mit `APPIMAGE_EXTRACT_AND_RUN=1` gestartet, damit für den
Start keine zusätzliche FUSE-Installation erforderlich ist. **Die eigentliche
EmuDeck-Einrichtung im offiziellen Assistenten abschließen und das Fenster
danach schließen.** Das Starter Kit wartet auf das Prozessende. Ein einfaches
Schließen ohne Einrichtung gilt nicht als Nachweis einer fertig eingerichteten
EmuDeck-Installation; die Abschlussmeldung macht das deutlich. Nach dem
Schließen kann die EmuDeck-AppImage optional zur Steam-Bibliothek hinzugefügt
werden, um den offiziellen Assistenten später wieder zu öffnen.
ROMs und BIOS-Dateien werden nicht mitgeliefert.

## Testmodus, Diagnose und Weiterentwicklung

```bash
# Nur Voraussetzungen und erkannte Pfade anzeigen
bash install.sh --check

# Geführter Probelauf: keine Installationen, Passwortänderungen oder Neustarts
# Ein frei gewählter Plugin-Katalog kann dabei lesend geladen werden.
bash install.sh --dry-run

# Sprache vorauswählen; die Sprachauswahl bleibt sichtbar
bash install.sh --lang en

# Tests aus dem Projektordner; keine echten Installationsaktionen
python3 -m unittest discover -s tests -v

# install.sh und die eigenständige .desktop-Datei neu erzeugen
python3 build.py
```

Protokolle und Ergebnislisten liegen unter
`~/.local/state/linux-handheld-starter-kit/`. Passwörter werden ausschließlich
über die Standardeingabe an `sudo` übergeben und nicht für spätere Aktionen
gespeichert. `sudo` verwaltet seine normale kurzlebige Autorisierung; sie wird
während des Durchlaufs aufgefrischt und beim Beenden invalidiert.
Die Passworterstellung selbst übernimmt das Systemwerkzeug `passwd`.

**Decky-Korrektur vom 21.10.2026:** Die erneute Passwortprüfung setzt die alte
sudo-Freigabe mit einem eigenen `sudo -k` zurück und erzeugt danach mit
`sudo -S -v` die neue Freigabe. Die vorherige Kombination `sudo -k -v` konnte
das Passwort akzeptieren, ohne eine Freigabe für die nachfolgende Installation
zu hinterlegen. Dadurch erschien „sudo: Ein Passwort ist notwendig“.
Die korrigierte Fassung speichert das Passwort weiterhin nicht und hebt die
temporäre Freigabe beim Beenden auf.

Das ZIP enthält die `.desktop`-Datei, `install.sh`, `recommend.txt`, `starterkit.py`,
`build.py`, `desktop_launcher.py`, `desktop_bootstrap.py`, diese Dokumentation,
die Lizenz und die Offline-Tests. Die fertige `install.sh` enthält den vollständigen Programmcode und alle
Plugin-Empfehlungen.

## Webseite und Weiterentwicklung

Die [Webseite](https://linux-handheld-starter-kit.cocoabloom514.chatgpt.site/de/)
ist in allen sieben Sprachen verfügbar. Sie enthält das Original-Logo, offizielle
Projektlinks, Downloads und die **neun neuesten Videos** des
[Steam Deck Checker Kanals](https://www.youtube.com/@SteamDeckChecker/).
Das Tutorial-Video kann später ergänzt werden.
Der teilbare Kurzlink lautet <https://is.gd/linux_handheld_starter_kit>.

Die Webseitenquellen liegen unter [`website/`](website/README.md).
Build, Tests und der Release-Ablauf sind in [CONTRIBUTING.md](CONTRIBUTING.md)
beschrieben. Der Quellcode-Build verwendet Python 3.12; Webseitenprüfungen
benötigen Node.js 20 oder neuer. Es sind keine zusätzlichen Python- oder
npm-Pakete erforderlich.

## Projekte und Lizenz

Von [Steam Deck Checker auf YouTube](https://www.youtube.com/@SteamDeckChecker/).
Quellcode unter der [MIT-Lizenz](LICENSE). Fremdsoftware und deren Inhalte
unterliegen den jeweiligen eigenen Lizenzen.

Offizielle Projekte: [Decky Loader](https://decky.xyz/) ·
[RetroDECK](https://retrodeck.net/) · [EmuDeck](https://www.emudeck.com/).

**Unabhängiges Projekt. Nicht mit Valve, den genannten Herstellern, Decky Loader,
RetroDECK oder EmuDeck verbunden.**

Die vollständige englische Anleitung steht in [README.en.md](README.en.md).
