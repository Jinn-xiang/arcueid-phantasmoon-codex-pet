#requires -Version 5.1
<# Phantasmoon local pet installer. ASCII source for Windows PowerShell 5.1. #>
[CmdletBinding()]
param(
    [ValidateSet('pro', 'codex', 'auto')][string]$App = 'auto',
    [string]$CodexHome = '',
    [string]$Repository = '',
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')][string]$Ref = 'v1.0.0',
    [string]$AssetRoot = '',
    [switch]$DryRun
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$petSha = '431b65abdadc656c0950487ea5107cc86c2b6a079bc686242ae9bc990f2ee8d1'
$spriteSha = 'b95e8cc0fee6649747ba0a7f69bc83cbf5f4691442c4844a5bc7ae93cc747b6a'

function Assert-DirectoryNotLink([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        $item = Get-Item -LiteralPath $Path -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing symbolic link or junction: $Path"
        }
        if (-not $item.PSIsContainer) { throw "Expected a directory: $Path" }
    }
}
if ($Repository -and ($Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' -or $Repository -eq 'OWNER/REPO')) {
    throw 'Replace OWNER/REPO with the published GitHub repository (USER/REPO).'
}
if (-not $CodexHome) {
    $userDirectory = [Environment]::GetFolderPath('UserProfile')
    switch ($App) {
        'pro' { $CodexHome = Join-Path $userDirectory '.codex-pro' }
        'codex' { $CodexHome = Join-Path $userDirectory '.codex' }
        'auto' {
            if ($env:CODEX_HOME) { $CodexHome = $env:CODEX_HOME }
            elseif (Test-Path -LiteralPath (Join-Path $userDirectory '.codex-pro') -PathType Container) {
                $CodexHome = Join-Path $userDirectory '.codex-pro'
            }
            elseif (Test-Path -LiteralPath (Join-Path $userDirectory '.codex') -PathType Container) {
                $CodexHome = Join-Path $userDirectory '.codex'
            }
            else { throw 'No app state directory found. Run the desktop app first, or use -CodexHome.' }
        }
    }
}
if (-not (Test-Path -LiteralPath $CodexHome -PathType Container)) {
    throw "App state directory does not exist: $CodexHome"
}
$CodexHome = (Resolve-Path -LiteralPath $CodexHome).ProviderPath
$target = Join-Path $CodexHome 'pets/phantasmoon'
if (-not $AssetRoot -and $PSScriptRoot) {
    $candidate = Join-Path $PSScriptRoot 'pet/phantasmoon'
    if (Test-Path -LiteralPath $candidate -PathType Container) { $AssetRoot = $candidate }
}
if ($AssetRoot) {
    foreach ($name in @('pet.json', 'spritesheet.png')) {
        if (-not (Test-Path -LiteralPath (Join-Path $AssetRoot $name) -PathType Leaf)) { throw 'Incomplete local payload.' }
    }
    $source = "local: $AssetRoot"
}
else {
    if (-not $Repository) { throw 'No local payload. Supply -Repository USER/REPO for online installation.' }
    $source = "https://raw.githubusercontent.com/$Repository/$Ref/pet/phantasmoon"
}
Write-Output "Phantasmoon 1.0.0 (R17)`nSource: $source`nTarget: $target"
if ($DryRun) { Write-Output 'Dry run: no files changed or downloaded.'; return }

$stage = $null
$backup = $null
$lock = Join-Path $CodexHome '.phantasmoon-install.lock'
$lockStream = $null
$previousTls = [Net.ServicePointManager]::SecurityProtocol
try {
    # CreateNew + FileShare.None prevents simultaneous installers replacing each other.
    try { $lockStream = [IO.File]::Open($lock, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None) }
    catch { throw "Another installation may be running. Check: $lock" }
    foreach ($path in @((Join-Path $CodexHome 'pets'), $target, (Join-Path $CodexHome 'pet-backups'), (Join-Path $CodexHome 'pet-backups/phantasmoon'))) {
        Assert-DirectoryNotLink $path
    }
    $stage = Join-Path $CodexHome ('.phantasmoon-stage.' + [guid]::NewGuid().ToString('N'))
    $payload = Join-Path $stage 'payload'
    [void][IO.Directory]::CreateDirectory($payload)
    if (-not $AssetRoot) {
        [Net.ServicePointManager]::SecurityProtocol = $previousTls -bor [Net.SecurityProtocolType]::Tls12
    }
    foreach ($name in @('pet.json', 'spritesheet.png')) {
        $destination = Join-Path $payload $name
        if ($AssetRoot) { [IO.File]::Copy((Join-Path $AssetRoot $name), $destination) }
        else { Invoke-WebRequest -UseBasicParsing -Uri "$source/$name" -OutFile $destination -TimeoutSec 180 }
    }
    $manifestPath = Join-Path $payload 'pet.json'
    $spritePath = Join-Path $payload 'spritesheet.png'
    if ((Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash -ne $petSha) { throw 'pet.json checksum mismatch; installation cancelled.' }
    if ((Get-FileHash -LiteralPath $spritePath -Algorithm SHA256).Hash -ne $spriteSha) { throw 'spritesheet.png checksum mismatch; installation cancelled.' }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.spriteVersionNumber -ne 2 -or $manifest.spritesheetPath -ne 'spritesheet.png') { throw 'Unexpected pet manifest.' }
    $imageBytes = [IO.File]::ReadAllBytes($spritePath)
    if ([BitConverter]::ToString($imageBytes, 0, 24) -ne '89-50-4E-47-0D-0A-1A-0A-00-00-00-0D-49-48-44-52-00-00-06-00-00-00-08-F0') { throw 'Unexpected PNG dimensions or header.' }
    $same = $true
    foreach ($name in @('pet.json', 'spritesheet.png')) {
        $oldFile = Join-Path $target $name
        if (-not (Test-Path -LiteralPath $oldFile -PathType Leaf)) { $same = $false; break }
        if ((Get-FileHash -LiteralPath $oldFile -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath (Join-Path $payload $name) -Algorithm SHA256).Hash) { $same = $false; break }
    }
    if ($same) { Write-Output 'This version is already installed. No replacement needed.'; return }
    [void][IO.Directory]::CreateDirectory((Join-Path $CodexHome 'pets'))
    if (Test-Path -LiteralPath $target -PathType Container) {
        $backupRoot = Join-Path $CodexHome 'pet-backups/phantasmoon'
        [void][IO.Directory]::CreateDirectory($backupRoot)
        $backup = Join-Path $backupRoot ((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ') + '-' + [guid]::NewGuid().ToString('N'))
        [IO.Directory]::Move($target, $backup)
    }
    [IO.Directory]::Move($payload, $target)
    Write-Output 'Installed. Open desktop app Settings > Pets, refresh, and select Phantasmoon.'
    if ($backup) { Write-Output "Previous version backup: $backup" }
}
catch {
    if ($backup -and (Test-Path -LiteralPath $backup -PathType Container) -and -not (Test-Path -LiteralPath $target)) {
        try { [IO.Directory]::Move($backup, $target) }
        catch { Write-Warning "Recovery needed: previous pet remains at $backup" }
    }
    throw
}
finally {
    [Net.ServicePointManager]::SecurityProtocol = $previousTls
    if ($stage -and (Test-Path -LiteralPath $stage -PathType Container)) { Remove-Item -LiteralPath $stage -Recurse -Force }
    if ($null -ne $lockStream) {
        $lockStream.Dispose()
        Remove-Item -LiteralPath $lock -Force
    }
}
