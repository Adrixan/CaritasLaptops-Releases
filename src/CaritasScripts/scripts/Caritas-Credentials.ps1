<#
.SYNOPSIS
    Lokaler, geschützter Kennwortspeicher der Caritas-Suite (wird per Dot-Sourcing geladen).
.DESCRIPTION
    Die öffentlich verteilte Skriptsammlung enthält keine Kennwörter. Die Technikerin oder der
    Techniker hinterlegt das Administrator-Kennwort und das Kennwort des Gastkontos 'User'
    einmalig pro Gerät (Kontrollzentrum: Menü [Z] bzw. Karte "Zugangsdaten").

    Speicherort: %ProgramData%\CaritasCredentials\credentials.json
      - liegt außerhalb der Skriptsammlung, wird daher nie kopiert, aktualisiert oder verteilt;
      - Ordner-ACL ohne Vererbung: nur SYSTEM und die lokale Administratoren-Gruppe;
      - jeder Wert ist zusätzlich per DPAPI (Bereich LocalMachine) verschlüsselt.

    Auflösungsreihenfolge (Resolve-CaritasCredential):
      1. explizit übergebener Wert (Parameter eines Skripts),
      2. lokaler Speicher,
      3. nur UserPassword: bestehendes Winlogon-'DefaultPassword' des Kontos 'User',
      4. interaktive Abfrage (nur in einer echten Konsole, nie als SYSTEM oder bei umgeleiteter Ausgabe),
      5. sonst $null; die aufrufenden Skripte überspringen dann kennwortabhängige Schritte.
#>

$script:CaritasCredentialDir = Join-Path $env:ProgramData "CaritasCredentials"
$script:CaritasCredentialFile = Join-Path $script:CaritasCredentialDir "credentials.json"
$script:CaritasCredentialNames = @("AdminPassword", "UserPassword")
$script:CaritasCredentialEntropy = [System.Text.Encoding]::UTF8.GetBytes("CaritasLaptops-Credentials-v1")
$script:CaritasCredentialMinLength = 8
$script:CaritasCredentialMaxLength = 127

function Get-CaritasCredentialLabel {
    param([Parameter(Mandatory)][ValidateSet("AdminPassword", "UserPassword")][string]$Name)
    switch ($Name) {
        "AdminPassword" { return "Administrator-Kennwort (CaritasAdmin und integrierter Administrator)" }
        "UserPassword"  { return "Kennwort des Gastkontos 'User'" }
    }
}

function Test-CaritasCredentialValue {
    <# Liefert $null bei gültigem Wert, sonst eine deutsche Fehlermeldung. #>
    param([AllowNull()][AllowEmptyString()][string]$Value)
    if ([string]::IsNullOrEmpty($Value)) { return "Das Kennwort darf nicht leer sein." }
    if ($Value.Length -lt $script:CaritasCredentialMinLength) { return "Das Kennwort muss mindestens $($script:CaritasCredentialMinLength) Zeichen lang sein." }
    if ($Value.Length -gt $script:CaritasCredentialMaxLength) { return "Das Kennwort darf höchstens $($script:CaritasCredentialMaxLength) Zeichen lang sein." }
    if ($Value -ne $Value.Trim()) { return "Das Kennwort darf nicht mit Leerzeichen beginnen oder enden." }
    if ($Value -match '[\x00-\x1F\x7F]') { return "Das Kennwort enthält unzulässige Steuerzeichen." }
    return $null
}

function Test-CaritasInteractiveSession {
    <# $true nur in einer echten Konsole mit Benutzer: nie als SYSTEM, nie mit umgeleiteter Ein-/Ausgabe (GUI-Hintergrundaufgaben). #>
    try {
        if (-not [Environment]::UserInteractive) { return $false }
        $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        if ($sid -eq "S-1-5-18") { return $false }
        if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) { return $false }
        # GUI-Hintergrundaufgaben starten "powershell.exe -NonInteractive" ohne Umleitung: Read-Host würde dort scheitern.
        if (@([Environment]::GetCommandLineArgs() | Where-Object { $_ -match '^-noni' }).Count -gt 0) { return $false }
        return $true
    } catch {
        return $false
    }
}

function Initialize-CaritasCredentialCrypto {
    try { Add-Type -AssemblyName System.Security -ErrorAction Stop } catch {}
}

function Protect-CaritasSecret {
    param([Parameter(Mandatory)][string]$PlainText)
    Initialize-CaritasCredentialCrypto
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($PlainText)
    $cipher = [System.Security.Cryptography.ProtectedData]::Protect($bytes, $script:CaritasCredentialEntropy, [System.Security.Cryptography.DataProtectionScope]::LocalMachine)
    return [Convert]::ToBase64String($cipher)
}

function Unprotect-CaritasSecret {
    param([Parameter(Mandatory)][string]$CipherText)
    Initialize-CaritasCredentialCrypto
    $cipher = [Convert]::FromBase64String($CipherText)
    $bytes = [System.Security.Cryptography.ProtectedData]::Unprotect($cipher, $script:CaritasCredentialEntropy, [System.Security.Cryptography.DataProtectionScope]::LocalMachine)
    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

function Set-CaritasCredentialDirectoryAcl {
    if (-not (Test-Path $script:CaritasCredentialDir)) {
        New-Item -ItemType Directory -Path $script:CaritasCredentialDir -Force | Out-Null
    }
    $acl = New-Object System.Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sidValue in @("S-1-5-18", "S-1-5-32-544")) {
        $sid = New-Object System.Security.Principal.SecurityIdentifier($sidValue)
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $sid, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
        $acl.AddAccessRule($rule)
    }
    Set-Acl -Path $script:CaritasCredentialDir -AclObject $acl
}

function Read-CaritasCredentialStore {
    $store = @{}
    if (-not (Test-Path $script:CaritasCredentialFile)) { return $store }
    try {
        $json = Get-Content -Path $script:CaritasCredentialFile -Raw -ErrorAction Stop | ConvertFrom-Json
        foreach ($n in $script:CaritasCredentialNames) {
            if ($json.PSObject.Properties.Name -contains $n -and $json.$n) { $store[$n] = [string]$json.$n }
        }
    } catch {}
    return $store
}

function Test-CaritasCredentialStored {
    param([Parameter(Mandatory)][ValidateSet("AdminPassword", "UserPassword")][string]$Name)
    return [bool](Get-CaritasCredential -Name $Name -StoreOnly)
}

function Get-CaritasCredential {
    param(
        [Parameter(Mandatory)][ValidateSet("AdminPassword", "UserPassword")][string]$Name,
        [switch]$StoreOnly
    )
    $store = Read-CaritasCredentialStore
    if ($store.ContainsKey($Name)) {
        try {
            $plain = Unprotect-CaritasSecret -CipherText $store[$Name]
            if (-not (Test-CaritasCredentialValue -Value $plain)) { return $plain }
        } catch {}
    }
    if ($StoreOnly) { return $null }

    if ($Name -eq "UserPassword") {
        # Bereits eingerichtete Geräte: Autologon hält das Kennwort von 'User' ohnehin in Winlogon.
        try {
            $wl = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -ErrorAction Stop
            if ($wl.DefaultUserName -eq "User" -and $wl.DefaultPassword -and -not (Test-CaritasCredentialValue -Value $wl.DefaultPassword)) {
                return [string]$wl.DefaultPassword
            }
        } catch {}
    }
    return $null
}

function Set-CaritasCredential {
    param(
        [Parameter(Mandatory)][ValidateSet("AdminPassword", "UserPassword")][string]$Name,
        [Parameter(Mandatory)][string]$Value
    )
    $problem = Test-CaritasCredentialValue -Value $Value
    if ($problem) { throw $problem }

    Set-CaritasCredentialDirectoryAcl
    $store = Read-CaritasCredentialStore
    $store[$Name] = Protect-CaritasSecret -PlainText $Value

    $out = [ordered]@{ format = 1; updated = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK") }
    foreach ($n in $script:CaritasCredentialNames) {
        if ($store.ContainsKey($n)) { $out[$n] = $store[$n] }
    }
    $tmp = "$($script:CaritasCredentialFile).tmp"
    ($out | ConvertTo-Json) | Set-Content -Path $tmp -Encoding UTF8 -Force
    Move-Item -Path $tmp -Destination $script:CaritasCredentialFile -Force
}

function ConvertFrom-CaritasSecureString {
    param([Parameter(Mandatory)][System.Security.SecureString]$Secure)
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

function Read-CaritasCredentialFromConsole {
    <# Fragt ein Kennwort zweimal verdeckt ab. Leere Eingabe bricht ab ($null). #>
    param([Parameter(Mandatory)][ValidateSet("AdminPassword", "UserPassword")][string]$Name)
    $label = Get-CaritasCredentialLabel -Name $Name
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $first = ConvertFrom-CaritasSecureString -Secure (Read-Host -Prompt "$label eingeben (Enter = abbrechen)" -AsSecureString)
        if (-not $first) { return $null }
        $problem = Test-CaritasCredentialValue -Value $first
        if ($problem) { Write-Host "  $problem" -ForegroundColor Red; continue }
        $second = ConvertFrom-CaritasSecureString -Secure (Read-Host -Prompt "$label wiederholen" -AsSecureString)
        if ($first -cne $second) { Write-Host "  Die Eingaben stimmen nicht überein." -ForegroundColor Red; continue }
        return $first
    }
    return $null
}

function Resolve-CaritasCredential {
    param(
        [Parameter(Mandatory)][ValidateSet("AdminPassword", "UserPassword")][string]$Name,
        [AllowNull()][AllowEmptyString()][string]$Value,
        [switch]$Interactive
    )
    if ($Value) { return $Value }
    $known = Get-CaritasCredential -Name $Name
    if ($known) { return $known }
    if ($Interactive -and (Test-CaritasInteractiveSession)) {
        Write-Host ""
        Write-Host "Das $(Get-CaritasCredentialLabel -Name $Name) ist auf diesem Gerät noch nicht hinterlegt." -ForegroundColor Yellow
        $entered = Read-CaritasCredentialFromConsole -Name $Name
        if ($entered) {
            try {
                Set-CaritasCredential -Name $Name -Value $entered
                Write-Host "  [OK] Geschützt hinterlegt in $($script:CaritasCredentialDir)." -ForegroundColor Green
            } catch {
                Write-Host "  [-] Speichern fehlgeschlagen: $_ (Kennwort gilt nur für diesen Lauf)." -ForegroundColor Yellow
            }
            return $entered
        }
    }
    return $null
}
