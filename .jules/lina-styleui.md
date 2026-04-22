## 2024-05-18 - [Hartcodierte Farben durch Theme-Variablen ersetzen]
**Erkenntnis:** In vielen Bereichen von Vorce (wie dem Module Canvas, Mesh-Editor und Timeline) wurden UI-Farben hartcodiert, was beim Wechseln des Themes zu massiven Kontrast- und Sichtbarkeitsproblemen führt.
**Aktion:** Ersetze `Color32::from_rgb` etc. stets durch die passenden Theme-Variablen wie `ui.visuals().text_color()`, `ui.visuals().window_fill` oder semantische Farben wie `ui.visuals().error_fg_color`, um ein robustes Rendering über alle Themes hinweg sicherzustellen.
## 2024-05-18 - [Hartcodierte Farben durch Theme-Variablen ersetzen]
**Erkenntnis:** In vielen Bereichen von Vorce (wie dem Module Canvas, Mesh-Editor und Timeline) wurden UI-Farben hartcodiert, was beim Wechseln des Themes zu massiven Kontrast- und Sichtbarkeitsproblemen führt.
**Aktion:** Ersetze `Color32::from_rgb` etc. stets durch die passenden Theme-Variablen wie `ui.visuals().text_color()`, `ui.visuals().window_fill` oder semantische Farben wie `ui.visuals().error_fg_color`, um ein robustes Rendering über alle Themes hinweg sicherzustellen.
