# Changelog

## Azeroth Diary Exporter 1.0.3

- Behoben: Der Exporter konnte nach dem normalen Schließen des Browserfensters als unsichtbarer Windows-Prozess weiterlaufen.
- Die Browser-Seite meldet ihr Schließen jetzt zusätzlich aktiv an den lokalen Exporter.
- Fehler bzw. Abbrüche der dauerhaften Browser-Verbindung werden nun erkannt und beenden den Exporter zuverlässig.
- Ein normales Neuladen der Exporter-Seite wird erkannt und beendet das Programm nicht versehentlich.
- Mehrere gleichzeitig geöffnete Exporter-Tabs werden berücksichtigt.

## Azeroth Diary Exporter 1.0.2

- Neues eigenes Azeroth-Diary-Exporter-Icon direkt in die Windows-EXE eingebaut.
- Dasselbe Icon wird auch als Favicon in der lokalen Browser-Oberfläche verwendet.
- Der Quellcode enthält `icon.ico`, `icon.png` und einen kleinen Build-Helfer, damit das Icon auch bei späteren Builds automatisch eingebettet wird.

## Azeroth Diary Exporter 1.0.1

- Behoben: Interne WoW-Itemlinks von Transmog-Einträgen (`item:...|h[...]|h`) werden nicht mehr als Rohtext in der HTML angezeigt.
- Der saubere Itemname im Titel bleibt weiterhin als optionaler Wowhead-Link anklickbar.

## Azeroth Diary Exporter 1.0.0

- Erste eigenständige Windows-Version.
- Liest Azeroth Diary SavedVariables ausschließlich lesend.
- Automatische Suche nach üblichen WoW-Retail-Installationen und Account-SavedVariables.
- Manuelle Auswahl von `AzerothDiary.lua` als Fallback.
- Exportiert die gesamte Chronik als moderne HTML-Datei.
- HTML mit Suche, Kategorien, Charakteren, Jahr/Monat/Tag und interaktivem Kalender.
- Seitennavigation mit 20 Erinnerungen pro Seite.
- Deutsch/Englisch für die erzeugte Chronik.
- Optionale Wowhead-Links und Tooltips.
- Optionaler Auto-Export bei Änderungen der SavedVariables, solange die Exporter-Seite geöffnet ist.
- Beim Schließen der Exporter-Seite beendet sich der unsichtbare Hintergrundprozess automatisch.
- Frei wählbares HTML-Ziel sowie Buttons zum Öffnen der Datei und des Zielordners.
- Konfiguration wird im Windows-Benutzerprofil gespeichert.
