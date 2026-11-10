# RobocrafterLP-Saechsisch

Sächsisch/Erzgebirgisch Sprachpaket für Brotato 1.2.0.1 (inkl. Abyssal Terrors, Paws & Claws und Primal Dread DLC).

## Was es macht (v1.0.2)

- Fügt die Sprache "Sächsisch" (Locale `de_AT`) ins Sprachmenü ein.
- Übersetzt das komplette UI: alle Menüs, Optionen, Coop-Hinweise,
  Profil-Verwaltung, Codex, Challenges, Crash-/Korruptionsmeldungen und
  Steam-Texte.
- Übersetzt alle Item- und Waffennamen von Vanilla, Abyssal Terrors, Paws &
  Claws und Primal Dread, dazu alle Gegnernamen und Gegner-Beschreibungen
  (Mutationen inklusive), Stat-Namen, Stat-Erklärungen (Hover-Texte),
  Waffenklassen, Tier-Labels und alle Effekt-Beschreibungen.
- Sächsischer/erzgebirgischer Wortschatz recherchiert aus Mundart-Quellen
  (erzgebirgisch.de, sachsenwelt.de, Mundart-Lexikon des Erzgebirgshauses,
  Foren- und Kommentar-Beiträgen); Dialekt-Kaskade für Kernbegriffe:
  Bunktlandung (Volltreffer), Fuchtel (Nahkampf), Flitzebogen (Fernkampf),
  Ausbixn (Flinkfüßigkeit), Däämlack (Glück), Mugge (Musik),
  Polnböller (Böller), Kuung (Kuchen), Sachsensplitter, Nicki, Stirnbandl.
- Alle nicht übersetzten Texte fallen automatisch auf das offizielle Deutsch
  zurück (Godot-Near-Match von `de_AT` auf `de`). Deutsch selbst bleibt
  unberührt.

## Wie es funktioniert

- `translations/saechsisch.json`: 1480 statische Übersetzungen nach
  Localization-Key plus 63 Zuordnungen englischer Anzeigenamen zu sächsischen
  Namen (für Primal-Dread-Inhalte, deren Keys offline nicht verifizierbar
  waren; die im 1.0.0-Testlog aufgetauchten Keys ITEM_USED_LIFEFORM_SCANNER,
  ITEM_AMMOSAURUS, ITEM_TUMOR, ITEM_MECA_EVOLVED_LEAP, ITEM_MUT_EVOLVED_LEAP
  und WEAPON_MOLOTOV sind seit 1.0.1 gemappt).
- `mod_main.gd` baut daraus zur Laufzeit ein Godot-Translation-Objekt
  (Locale `de_AT`), registriert es am TranslationServer, hängt `de_AT` an
  `ProgressData.languages` und liest anschließend alle Item-/Waffen-Keys aus
  `ItemService` aus, um Primal-Dread-Namen über die Zuordnungstabelle
  zuzuordnen. Nicht zugeordnete Keys stehen als Gap-Liste im Log
  (`~/.local/share/Brotato/logs/modloader.log`).

## Installation (Steam-Build)

Zip in den [Modders]-Workshop-Ordner legen (Workshop-Item 3369699033,
`steamapps/workshop/content/1942280/3369699033/`), Spiel starten, im
Sprachmenü "Sächsisch" wählen.

## Hinweis zu Primal Dread

Die offizielle deutsche Übersetzung der Primal-Dread-Texte war offline nicht
verfügbar. Die sächsischen PD-Namen basieren auf den exakten englischen Namen
und Effektdaten (brotato.unpacked.wiki, aus Spieldaten generiert). PD-Keys,
die offline unbekannt sind, fallen auf Deutsch zurück; die Mod loggt die
Key-Namen, sodass sie später ergänzt werden können.
