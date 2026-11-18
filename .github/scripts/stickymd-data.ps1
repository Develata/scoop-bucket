#Requires -Version 5.1
<#
.SYNOPSIS
    Checks that bucket/stickymd.json carries the note folder across `scoop update` and
    `scoop uninstall`, and that a failing hook never damages the saved copy.
.DESCRIPTION
    For a disposable Windows CI runner with Scoop installed. It installs real StickyMD
    releases from a local, non-git bucket named 'stickymdtest' and runs Scoop in a separate
    process of the same PowerShell edition as this script, so the script's own settings do
    not leak into Scoop. Assertions check the resulting files, never Scoop's exit code.
#>
param(
    [string] $Manifest = (Join-Path $PSScriptRoot '..\..\bucket\stickymd.json'),
    [string] $OldVersion = '0.1.3',
    [string] $OldHash = '19e659638556df453affa2891d20944c8c9c3e48209f01c63a9eb658192ad179'
)

$ErrorActionPreference = 'Stop'

$scoopRoot = if ($env:SCOOP) { $env:SCOOP } else { Join-Path $env:USERPROFILE 'scoop' }
$scoopScript = Join-Path $scoopRoot 'apps\scoop\current\bin\scoop.ps1'
$bucketDir = Join-Path $scoopRoot 'buckets\stickymdtest\bucket'
$shell = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$base = Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json
$newVersion = $base.version
$newHash = $base.architecture.'64bit'.hash
if ($newVersion -eq $OldVersion) { throw "The old version $OldVersion must differ from the manifest version." }
New-Item -ItemType Directory -Force -Path $bucketDir | Out-Null
Write-Host "Scoop $scoopScript under $shell; $OldVersion -> $newVersion"

function Invoke-Scoop([string[]] $Arguments) {
    Write-Host "> scoop $($Arguments -join ' ')"
    # Windows PowerShell turns a child's stderr into terminating errors under 'Stop'.
    $ErrorActionPreference = 'Continue'
    $output = & $shell -NoProfile -ExecutionPolicy Bypass -File $scoopScript @Arguments 2>&1 | ForEach-Object { "$_" }
    $output | ForEach-Object { Write-Host "  $_" }
    ($output -join "`n")
}

function Set-TestManifest {
    param([string] $Name, [string] $Version, [string] $Hash, [string] $PreInstallFault, [string] $PreUninstallFault)
    $m = Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json
    $m.version = $Version
    $m.architecture.'64bit'.url = "https://github.com/Develata/StickyMD/releases/download/v$Version/StickyMD-$Version-windows-x64-portable.zip"
    $m.architecture.'64bit'.hash = $Hash
    if ($PreInstallFault -eq 'start') { $m.pre_install = @("throw 'injected pre_install fault'") + @($m.pre_install) }
    if ($PreInstallFault -eq 'end') { $m.pre_install = @($m.pre_install) + @("throw 'injected pre_install fault'") }
    if ($PreUninstallFault -eq 'start') { $m.pre_uninstall = @("throw 'injected pre_uninstall fault'") + @($m.pre_uninstall) }
    $json = $m | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText((Join-Path $bucketDir "$Name.json"), $json, (New-Object System.Text.UTF8Encoding $false))
}

function Get-AppDir([string] $App) { Join-Path $scoopRoot "apps\$App" }
function Get-PersistNote([string] $App, [string] $Leaf = 'note') { Join-Path $scoopRoot "persist\$App\$Leaf" }

function Get-InstalledVersion([string] $App) {
    $installed = Join-Path (Get-AppDir $App) 'current\manifest.json'
    if (Test-Path -LiteralPath $installed) { (Get-Content -LiteralPath $installed -Raw | ConvertFrom-Json).version } else { $null }
}

# Every entry below the root, sorted ordinally: directories by name, files with their SHA-256
# and the read-only and hidden attributes. The archive bit is ignored.
function Get-Tree([string] $Root) {
    if (!(Test-Path -LiteralPath $Root -PathType Container)) { return "<missing $Root>" }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $lines = foreach ($path in [System.IO.Directory]::EnumerateFileSystemEntries($Root, '*', 'AllDirectories')) {
        $relative = $path.Substring($Root.Length + 1)
        $attributes = [System.IO.File]::GetAttributes($path)
        if ($attributes -band [System.IO.FileAttributes]::Directory) {
            "D $relative"
        } else {
            $hash = [System.BitConverter]::ToString($sha.ComputeHash([System.IO.File]::ReadAllBytes($path))).Replace('-', '')
            $flags = ''
            if ($attributes -band [System.IO.FileAttributes]::ReadOnly) { $flags += 'R' }
            if ($attributes -band [System.IO.FileAttributes]::Hidden) { $flags += 'H' }
            "F $relative $hash $flags"
        }
    }
    $sorted = [string[]] @($lines)
    [System.Array]::Sort($sorted, [System.StringComparer]::Ordinal)
    $sorted -join "`n"
}

function Assert-True([bool] $Condition, [string] $What) {
    if (!$Condition) { throw "FAILED: $What" }
    Write-Host "ok: $What"
}

function Assert-Tree([string] $Expected, [string] $Root, [string] $What) {
    $actual = Get-Tree $Root
    if ($actual -cne $Expected) {
        Write-Host "expected:`n$Expected`nactual:`n$actual"
        throw "FAILED: $What"
    }
    Write-Host "ok: $What"
}

# A note folder shaped like StickyMD's, plus the awkward cases a plain copy can drop.
function New-NoteTree([string] $Root) {
    $utf8 = New-Object System.Text.UTF8Encoding $false
    # Non-ASCII text from code points keeps this file ASCII, which both PowerShell editions read alike.
    $draft = [string] [char] 0x8349 + [char] 0x7A3F + ' ' + [char] 0x2713
    $picture = [string] [char] 0x56FE + [char] 0x7247
    foreach ($sub in 'images', '.trash', 'images\empty') { New-Item -ItemType Directory -Force -Path (Join-Path $Root $sub) | Out-Null }
    [System.IO.File]::WriteAllText((Join-Path $Root 'note.md'), "# $draft`r`n`r`n`$`$x^2 + y^2`$`$`r`n", $utf8)
    [System.IO.File]::WriteAllText((Join-Path $Root 'note.md.tmp'), "unsaved residue`r`n", $utf8)
    [System.IO.File]::WriteAllText((Join-Path $Root 'config.toml'), "opacity = 0.9`r`n", $utf8)
    $bytes = [byte[]] (0..4095 | ForEach-Object { ($_ * 31 + 7) % 256 })
    $managed = 'stickymd-' + ('0123456789abcdef' * 4) + '.png'
    [System.IO.File]::WriteAllBytes((Join-Path $Root "images\$managed"), $bytes)
    [System.IO.File]::WriteAllBytes((Join-Path $Root ".trash\$managed"), $bytes)
    $user = Join-Path $Root "images\user [copy] $picture.png"
    [System.IO.File]::WriteAllBytes($user, [byte[]] $bytes[0..1023])
    [System.IO.File]::SetAttributes($user, [System.IO.FileAttributes]::ReadOnly)
    $log = Join-Path $Root 'crash.log'
    [System.IO.File]::WriteAllText($log, "hidden`r`n", $utf8)
    [System.IO.File]::SetAttributes($log, [System.IO.FileAttributes]::Hidden)
}

# 1. Normal path: guard, update, uninstall, reinstall.
$app = 'stickymd'
Set-TestManifest -Name $app -Version $OldVersion -Hash $OldHash
Invoke-Scoop @('install', "stickymdtest/$app") | Out-Null
Assert-True ((Get-InstalledVersion $app) -eq $OldVersion) "$app $OldVersion installed"
$oldDir = Join-Path (Get-AppDir $app) $OldVersion
New-NoteTree (Join-Path $oldDir 'note')
$original = Get-Tree (Join-Path $oldDir 'note')

$probe = Join-Path $oldDir 'probe.exe'
Copy-Item -LiteralPath (Join-Path $env:SystemRoot 'System32\cmd.exe') -Destination $probe
$process = Start-Process -FilePath $probe -ArgumentList '/c', 'ping -n 300 127.0.0.1 >nul' -WindowStyle Hidden -PassThru
Start-Sleep -Seconds 2
Set-TestManifest -Name $app -Version $newVersion -Hash $newHash
Invoke-Scoop @('update', $app) | Out-Null
Assert-True ((Get-InstalledVersion $app) -eq $OldVersion) 'update skipped while a process runs from the app directory'
Invoke-Scoop @('uninstall', $app) | Out-Null
Assert-True ((Get-InstalledVersion $app) -eq $OldVersion) 'uninstall refused while a process runs from the app directory'
Assert-True (!(Test-Path -LiteralPath (Get-PersistNote $app))) 'nothing saved while a process runs from the app directory'
Stop-Process -Id $process.Id -Force
$process.WaitForExit()
Start-Sleep -Seconds 1
Remove-Item -LiteralPath $probe -Force

Invoke-Scoop @('update', $app) | Out-Null
Assert-True ((Get-InstalledVersion $app) -eq $newVersion) "updated to $newVersion"
Assert-Tree $original (Join-Path (Get-AppDir $app) 'current\note') 'note carried into the new version'
Assert-Tree $original (Get-PersistNote $app) 'saved copy equals the note'
Assert-Tree $original (Join-Path $oldDir 'note') 'old version directory left untouched'

$currentNote = Join-Path (Get-AppDir $app) 'current\note'
[System.IO.File]::AppendAllText((Join-Path $currentNote 'note.md'), "edited in $newVersion`r`n")
[System.IO.File]::WriteAllText((Join-Path $currentNote 'images\added.png'), 'added')
$edited = Get-Tree $currentNote
Invoke-Scoop @('uninstall', $app) | Out-Null
Assert-True (!(Test-Path -LiteralPath (Get-AppDir $app))) 'uninstall removed the app directory'
Assert-Tree $edited (Get-PersistNote $app) 'uninstall saved the edited note'
Assert-Tree $original (Get-PersistNote $app 'note.previous') 'uninstall kept the copy before it'
Invoke-Scoop @('install', "stickymdtest/$app") | Out-Null
Assert-True ((Get-InstalledVersion $app) -eq $newVersion) "reinstalled $newVersion"
Assert-Tree $edited (Join-Path (Get-AppDir $app) 'current\note') 'reinstall restored the edited note'

# 2. A failing pre_uninstall stops `scoop update` before anything is uninstalled.
$app = 'stickymd-save-fault'
Set-TestManifest -Name $app -Version $OldVersion -Hash $OldHash -PreUninstallFault 'start'
Invoke-Scoop @('install', "stickymdtest/$app") | Out-Null
$oldNote = Join-Path (Get-AppDir $app) "$OldVersion\note"
New-NoteTree $oldNote
Set-TestManifest -Name $app -Version $newVersion -Hash $newHash
Invoke-Scoop @('update', $app) | Out-Null
Assert-True ((Get-InstalledVersion $app) -eq $OldVersion) 'failed save left the old version installed'
Assert-Tree $original $oldNote 'failed save left the note untouched'

# 3. A failing pre_install, before or after the restore, never damages the saved copy, and
#    what a user would try next brings the note back.
foreach ($position in 'start', 'end') {
    $app = "stickymd-restore-fault-$position"
    Set-TestManifest -Name $app -Version $OldVersion -Hash $OldHash
    Invoke-Scoop @('install', "stickymdtest/$app") | Out-Null
    New-NoteTree (Join-Path (Get-AppDir $app) "$OldVersion\note")
    Set-TestManifest -Name $app -Version $newVersion -Hash $newHash -PreInstallFault $position
    Invoke-Scoop @('update', $app) | Out-Null
    Assert-Tree $original (Get-PersistNote $app) "pre_install fault at $position kept the saved copy"

    Set-TestManifest -Name $app -Version $newVersion -Hash $newHash
    foreach ($attempt in @(@('update', $app), @('uninstall', $app), @('install', "stickymdtest/$app"))) {
        if ((Get-InstalledVersion $app) -eq $newVersion) { break }
        Invoke-Scoop $attempt | Out-Null
        Assert-Tree $original (Get-PersistNote $app) "saved copy intact after 'scoop $($attempt -join ' ')'"
    }
    Assert-True ((Get-InstalledVersion $app) -eq $newVersion) "recovered to $newVersion after a pre_install fault at $position"
    Assert-Tree $original (Join-Path (Get-AppDir $app) 'current\note') "note restored after a pre_install fault at $position"
}

Write-Host 'All StickyMD carry-over checks passed.'
