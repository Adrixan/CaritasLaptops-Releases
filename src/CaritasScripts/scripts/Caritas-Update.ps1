<#
.SYNOPSIS
    Gemeinsamer Selbst-Aktualisierer für TUI und GUI (wird per Dot-Sourcing geladen).
.DESCRIPTION
    Quelle ist das öffentliche Release-Repository Adrixan/CaritasLaptops-Releases. Es enthält nur
    die bereinigte Skriptsammlung ohne Kennwörter (Entscheidung D47 B, 2026-11-15).
    - Manifest: version.json im Zweig main (Version, Download-Adresse, SHA-256 des Pakets).
    - Paket: Release-Asset CaritasScripts.zip; nur Adressen unter dem Release-Pfad sind erlaubt.
    - Das Paket wird vor dem Entpacken gegen die SHA-256 des Manifests geprüft.
#>

$script:CaritasUpdateManifestUrl = "https://raw.githubusercontent.com/Adrixan/CaritasLaptops-Releases/main/version.json"
$script:CaritasUpdateAllowedPrefix = "https://github.com/Adrixan/CaritasLaptops-Releases/releases/download/"

function Test-IsNewerVersion {
    param([string]$LocalVersion, [string]$RemoteVersion)
    try {
        $cleanLocal = ($LocalVersion -replace '[^0-9\.]', '').Trim('.')
        $cleanRemote = ($RemoteVersion -replace '[^0-9\.]', '').Trim('.')
        if (-not $cleanLocal -or -not $cleanRemote) { return $false }
        while (($cleanLocal.Split('.').Count) -lt 2) { $cleanLocal += ".0" }
        while (($cleanRemote.Split('.').Count) -lt 2) { $cleanRemote += ".0" }
        return ([System.Version]$cleanRemote -gt [System.Version]$cleanLocal)
    } catch {
        return $false
    }
}

function Test-CaritasUpdateManifest {
    <# Liefert $null bei gültigem Manifest, sonst den Grund. #>
    param($Manifest)
    if (-not $Manifest) { return "Manifest leer." }
    if (-not ($Manifest.version -match '^\d+\.\d+(\.\d+){0,2}$')) { return "Ungültige Versionsangabe." }
    $url = [string]$Manifest.archiveUrl
    if (-not $url.StartsWith($script:CaritasUpdateAllowedPrefix, [StringComparison]::Ordinal)) { return "Download-Adresse liegt außerhalb des Release-Repositorys." }
    if ($url -match '\.\.|[?#]') { return "Download-Adresse enthält unzulässige Zeichen." }
    if (-not ([string]$Manifest.sha256 -match '^[0-9a-fA-F]{64}$')) { return "SHA-256-Prüfsumme fehlt oder ist ungültig." }
    return $null
}

function Get-CaritasUpdateManifest {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $raw = Invoke-RestMethod -Uri $script:CaritasUpdateManifestUrl -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop
    # raw.githubusercontent.com liefert text/plain; Windows PowerShell 5.1 gibt dann eine Zeichenkette zurück.
    $manifest = if ($raw -is [string]) { $raw | ConvertFrom-Json } else { $raw }
    $problem = Test-CaritasUpdateManifest -Manifest $manifest
    if ($problem) { throw "Update-Manifest abgelehnt: $problem" }
    return $manifest
}

function Install-CaritasUpdate {
    <# Lädt, prüft und installiert das Paket. Gibt die neue Version zurück oder wirft eine Ausnahme. #>
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$ScriptDir,
        [Parameter(Mandatory)][string]$LocalVersionFile,
        [Parameter(Mandatory)][string]$StagingDir
    )
    $problem = Test-CaritasUpdateManifest -Manifest $Manifest
    if ($problem) { throw "Update-Manifest abgelehnt: $problem" }

    if (Test-Path $StagingDir) { Remove-Item -Path $StagingDir -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $StagingDir -Force | Out-Null
    try {
        $zipPath = Join-Path $StagingDir "update.zip"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $Manifest.archiveUrl -OutFile $zipPath -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop

        $actual = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash
        if ($actual -ne ([string]$Manifest.sha256).ToUpperInvariant()) {
            throw "Prüfsumme des Update-Pakets stimmt nicht (erwartet $($Manifest.sha256), erhalten $actual). Update abgebrochen."
        }

        $extractDir = Join-Path $StagingDir "x"
        Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
        $root = Join-Path $extractDir "CaritasScripts"
        if (-not (Test-Path (Join-Path $root "scripts"))) { throw "Paketstruktur unerwartet: Ordner 'CaritasScripts\scripts' fehlt." }

        $files = @(Get-ChildItem -Path (Join-Path $root "scripts") -File | Where-Object { $_.Extension -in @(".ps1", ".cmd") })
        if ($files.Count -eq 0) { throw "Paket enthält keine Skripte." }
        foreach ($f in $files) { Copy-Item -Path $f.FullName -Destination $ScriptDir -Force }

        $pkgVersion = Join-Path $root "version.json"
        if (Test-Path $pkgVersion) { Copy-Item -Path $pkgVersion -Destination $LocalVersionFile -Force }
        return [string]$Manifest.version
    } finally {
        if (Test-Path $StagingDir) { Remove-Item -Path $StagingDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
