# Azeroth Diary Exporter

Optionaler externer Windows-Exporter für das WoW-Addon **Azeroth Diary**.

## Wichtig

Der Exporter ist **nicht Bestandteil des WoW-Addons** und soll auch nicht in dessen CurseForge-ZIP aufgenommen werden. Der manuelle HTML-Export im Addon bleibt vollständig erhalten.

## Funktionen v1.0.1

- Portable Windows-Anwendung (`AzerothDiaryExporter.exe`), keine Installation nötig.
- Liest `WTF\Account\<Account>\SavedVariables\AzerothDiary.lua` ausschließlich lesend.
- Automatische Suche nach üblichen World-of-Warcraft-Installationen und Accounts.
- Manuelle Auswahl der `AzerothDiary.lua`, falls WoW an einem anderen Ort installiert ist.
- Erzeugt eine vollständige `AzerothDiary.html` mit:
  - Suche
  - Kategorie-Filter
  - Charakter-Filter
  - Jahr-/Monat-/Tag-Auswahl
  - interaktivem Kalender
  - 20 Erinnerungen pro Seite
  - optionalen Wowhead-Links und Tooltips
- Deutsch und Englisch.
- Optionaler Auto-Export, sobald WoW die SavedVariables nach `/reload`, Logout oder Beenden neu schreibt. Der Auto-Export läuft, solange die Exporter-Seite geöffnet ist.
- Frei wählbarer Speicherort für die HTML-Datei.
- Schaltflächen zum Öffnen der HTML und des Zielordners.

## Verwendung

1. `AzerothDiaryExporter.exe` starten.
2. Der Exporter öffnet seine lokale Bedienoberfläche im Standardbrowser.
3. Normalerweise wird `AzerothDiary.lua` automatisch gefunden. Falls nicht, über **Datei wählen** auswählen.
4. Ziel für `AzerothDiary.html` festlegen.
5. **Jetzt exportieren** drücken oder den automatischen Export aktivieren. Für den Auto-Export die Exporter-Seite geöffnet lassen. Beim Schließen der Seite beendet sich der Exporter automatisch.

## Wann werden neue WoW-Daten sichtbar?

WoW schreibt SavedVariables nicht nach jedem einzelnen Ereignis sofort auf die Festplatte. Neue Einträge werden normalerweise nach `/reload`, beim Logout oder beim Beenden von WoW gespeichert. Erst danach kann ein externes Programm die neuen Daten lesen.

## Datenschutz / Sicherheit

Der Exporter liest nur die lokale `AzerothDiary.lua`. Er verändert die SavedVariables nicht und sendet keine Tagebuchdaten an einen Server. Nur wenn Wowhead-Tooltips für die erzeugte HTML aktiviert werden, lädt der Browser beim Öffnen der HTML das öffentliche Wowhead-Tooltip-Script aus dem Internet.

## Getrennte Versionierung

Exporter und WoW-Addon werden unabhängig versioniert. Diese Version ist **Azeroth Diary Exporter v1.0.1**.
