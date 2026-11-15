# CaritasLaptops-Releases

Öffentliches Auslieferungsziel der Caritas-Laptop-Verwaltungsskripte (PowerShell, Windows 11).

- `src/CaritasScripts/`: die bereinigte Skriptsammlung, wie sie auf die Laptops kommt.
- `version.json`: Update-Manifest (Version, Download-Adresse, SHA-256) für den eingebauten Selbst-Aktualisierer.
- Releases: `CaritasScripts.zip` plus `.sha256`.

Diese Sammlung enthält keine Zugangsdaten. Kennwörter werden auf jedem Gerät bei der Einrichtung
eingegeben und dort lokal verschlüsselt abgelegt. Jeder Push läuft durch einen Leak-Check
(Musterprüfung plus gitleaks über die gesamte Historie). Die Entwicklung findet in einem
privaten Repository statt; dieses Repository wird nur durch dessen Release-Skript befüllt.

Public delivery target of the Caritas laptop management scripts. It ships no credentials;
every push is scanned for leaks. Pull requests are not accepted here.

Lizenz: GNU AGPL v3, siehe `LICENSE`.
