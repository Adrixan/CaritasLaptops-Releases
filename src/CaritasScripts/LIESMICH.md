# Caritas Laptop Verwaltung: Skriptsammlung

Verwaltungs- und Härtungsskripte für gespendete Windows-11-Laptops der Caritas.

## Start
- Ordner `CaritasScripts` auf den Desktop des Administratorkontos kopieren.
- `Caritas-Verwaltung.cmd` (grafisch) oder `Caritas-Verwaltung-TUI.cmd` (Terminal) doppelklicken.

## Zugangsdaten
Diese Skriptsammlung enthält keine Kennwörter. Beim ersten Start auf einem Gerät fragt das
Kontrollzentrum nach dem Administrator-Kennwort und dem Kennwort des Gastkontos `User`
(GUI: Karte "Zugangsdaten dieses Geräts"; TUI: Menü `[Z]`). Die Kennwörter liegen danach
verschlüsselt (DPAPI) unter `%ProgramData%\CaritasCredentials`, lesbar nur für SYSTEM und
Administratoren. Sie werden nie mitkopiert oder aktualisiert. Die Kennwörter selbst stehen im
internen Handbuch.

## Aktualisierung
Das Kontrollzentrum prüft `version.json` im öffentlichen Repository
`Adrixan/CaritasLaptops-Releases`, lädt das Release-Paket und installiert es nur, wenn die
SHA-256-Prüfsumme stimmt.
