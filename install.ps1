<#
    FSpotify (crt-music) installer for Windows.

        irm https://abhinavtomar11345577.github.io/crt-music-apt/install.ps1 | iex

    Installs Python's curses support, mpv, a current yt-dlp and the player
    itself under %LOCALAPPDATA%\crt-music, with no administrator rights.

    To see what it would do, or to remove it again, run:

        & ([scriptblock]::Create((irm https://abhinavtomar11345577.github.io/crt-music-apt/install.ps1))) -DryRun
        & ([scriptblock]::Create((irm https://abhinavtomar11345577.github.io/crt-music-apt/install.ps1))) -Uninstall
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is ~10x faster without it
# PowerShell 7.4 turns a non-zero exit code from a native program into a
# terminating error. Several checks here read $LASTEXITCODE on purpose.
$PSNativeCommandUseErrorActionPreference = $false
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$PagesUrl   = 'https://abhinavtomar11345577.github.io/crt-music-apt'
$Version    = '1.1.0'
$AppSha256  = 'df120db8e47324f88497eee50c4268a52205ada67ce9e21372c4216368588497'
$MinYtdlp   = 20260101
$Root       = Join-Path $env:LOCALAPPDATA 'crt-music'
$BinDir     = Join-Path $Root 'bin'
$AppFile    = Join-Path $Root 'crt-music.py'
$LauncherFile = Join-Path $BinDir 'crt-music.cmd'

function Say  ($m) { Write-Host "==> $m" -ForegroundColor Green }
function Warn ($m) { Write-Host "install.ps1: $m" -ForegroundColor Yellow }
function Die  ($m) { Write-Host "install.ps1: $m" -ForegroundColor Red; exit 1 }

# Every change goes through Step, so -DryRun can print the whole plan.
function Step ($what, [scriptblock]$action) {
    if ($DryRun) { Write-Host "    would $what" ; return $null }
    Say $what
    & $action
}

function Have ($name) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if (-not $cmd) { return $null }
    # The Microsoft Store stubs in WindowsApps are not real interpreters:
    # running one opens the Store instead of starting Python.
    if ($cmd.Source -and $cmd.Source -like '*\WindowsApps\*' -and $name -like 'python*') { return $null }
    return $cmd.Source
}

function Download ($url, $dest) {
    if ($DryRun) { Write-Host "    would download $url"; return }
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
}

# ------------------------------------------------------------- uninstall ---
if ($Uninstall) {
    $shortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'FSpotify.lnk'
    foreach ($path in @($shortcut, $Root)) {
        if (Test-Path $path) {
            Step "remove $path" { Remove-Item -Recurse -Force $path }
        }
    }
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($userPath -and $userPath.Split(';') -contains $BinDir) {
        $kept = ($userPath.Split(';') | Where-Object { $_ -and $_ -ne $BinDir }) -join ';'
        Step "take $BinDir off your PATH" {
            [Environment]::SetEnvironmentVariable('Path', $kept, 'User')
        }
    }
    Say 'FSpotify removed. mpv and yt-dlp installed by winget/scoop/choco were left alone.'
    exit 0
}

Say "Installing FSpotify $Version into $Root"
if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $BinDir | Out-Null }
$env:Path = "$BinDir;$env:Path"

# ----------------------------------------------------------------- python ---
$python = $null
foreach ($candidate in @('py', 'python3', 'python')) {
    $found = Have $candidate
    if (-not $found) { continue }
    try {
        # Built as a statement, not as `$x = if (...) {@('--version')}`:
        # PowerShell unwraps a single-element array out of an if expression,
        # and splatting the bare string then passes no arguments at all -
        # which starts an interactive Python and hangs the installer.
        $versionArgs = @('--version')
        if ($candidate -eq 'py') { $versionArgs = @('-3', '--version') }
        $out = & $found @versionArgs 2>&1
        if ($out -match 'Python (\d+)\.(\d+)' -and [int]$Matches[1] -eq 3 -and [int]$Matches[2] -ge 9) {
            # 'py' is a launcher, not an interpreter: resolve the real one so
            # the launcher and pip both point at the same Python.
            if ($candidate -eq 'py') {
                $python = (& $found -3 -c 'import sys; print(sys.executable)' 2>&1).Trim()
            } else {
                $python = $found
            }
            break
        }
    } catch { }
}

if (-not $python) {
    if (Have 'winget') {
        Step 'install Python 3 with winget' {
            winget install --id Python.Python.3.12 --exact --silent `
                --accept-package-agreements --accept-source-agreements | Out-Null
        }
        # winget puts python on PATH only for new processes.
        $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                    [Environment]::GetEnvironmentVariable('Path', 'User')
        $python = Have 'python'
    }
}
if (-not $python -and -not $DryRun) {
    Die "FSpotify needs Python 3.9 or newer. Install it from https://python.org/downloads
(tick 'Add python.exe to PATH'), then run this installer again."
}
if ($DryRun -and -not $python) { $python = 'python' }
Say "Python: $python"

# curses is not in Python's standard library on Windows.
if (-not $DryRun) {
    & $python -c 'import curses' 2>$null
    if ($LASTEXITCODE -ne 0) {
        Say 'Installing windows-curses'
        & $python -m pip install --user --quiet --disable-pip-version-check windows-curses
        & $python -c 'import curses' 2>$null
        if ($LASTEXITCODE -ne 0) {
            Die "could not install windows-curses. Try it by hand:
    $python -m pip install windows-curses"
        }
    }
} else {
    Write-Host '    would ensure the windows-curses package is installed'
}

# -------------------------------------------------------------------- mpv ---
function Install-Mpv {
    if (Have 'mpv') { return $true }
    if (Have 'winget') {
        Say 'Installing mpv with winget'
        if (-not $DryRun) {
            winget install --id shinchiro.mpv --exact --silent `
                --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
            $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                        [Environment]::GetEnvironmentVariable('Path', 'User') + ";$BinDir"
        }
        if ($DryRun -or (Have 'mpv')) { return $true }
    }
    if (Have 'scoop') {
        Say 'Installing mpv with scoop'
        if (-not $DryRun) { scoop install mpv 2>&1 | Out-Null }
        if ($DryRun -or (Have 'mpv')) { return $true }
    }
    if (Have 'choco') {
        Say 'Installing mpv with Chocolatey'
        if (-not $DryRun) { choco install mpv -y --no-progress 2>&1 | Out-Null }
        if ($DryRun -or (Have 'mpv')) { return $true }
    }

    # No package manager: take the official Windows build. Its archive is
    # .7z, which the tar.exe shipped with Windows 10 1803 and later can read.
    Say 'Fetching the official mpv build for Windows'
    if ($DryRun) { Write-Host '    would download mpv from github.com/shinchiro/mpv-winbuild-cmake'; return $true }
    try {
        $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'aarch64' } else { 'x86_64' }
        $release = Invoke-RestMethod -UseBasicParsing `
            'https://api.github.com/repos/shinchiro/mpv-winbuild-cmake/releases/latest'
        $asset = $release.assets |
            Where-Object { $_.name -like "mpv-$arch-*.7z" -and $_.name -notlike '*dev*' } |
            Select-Object -First 1
        if (-not $asset) { throw "no mpv build for $arch in the latest release" }
        $work = Join-Path $env:TEMP ("crt-music-mpv-" + [guid]::NewGuid())
        New-Item -ItemType Directory -Force -Path $work | Out-Null
        $archive = Join-Path $work $asset.name
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $archive -UseBasicParsing
        & tar.exe -xf $archive -C $work 2>$null
        if ($LASTEXITCODE -ne 0) {
            $sevenZip = (Have '7z'), (Have '7za') | Where-Object { $_ } | Select-Object -First 1
            if (-not $sevenZip) { throw 'cannot unpack the .7z archive on this system' }
            & $sevenZip x "-o$work" -y $archive | Out-Null
        }
        Get-ChildItem -Path $work -File |
            Where-Object { $_.Extension -in '.exe', '.dll', '.com' } |
            ForEach-Object { Copy-Item $_.FullName -Destination $BinDir -Force }
        Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
    } catch {
        Warn "could not install mpv automatically: $_"
        return $false
    }
    return [bool](Have 'mpv')
}

$mpvInstalled = @(Install-Mpv) | Select-Object -Last 1
if (-not $mpvInstalled) {
    Die "FSpotify needs mpv for playback. Install it yourself from https://mpv.io
(or run: winget install shinchiro.mpv) and run this installer again."
}

# ----------------------------------------------------------------- yt-dlp ---
# Always the upstream build: YouTube only serves streams to a current yt-dlp,
# and this is the one thing that otherwise silently stops every track from
# playing. It lands in our own bin directory, which the player puts first on
# its PATH, so it also shadows an older copy installed some other way.
function Get-YtdlpDate {
    $exe = Have 'yt-dlp'
    if (-not $exe) { return 0 }
    try { $raw = (& $exe --version 2>$null | Select-Object -First 1).Trim() } catch { return 0 }
    if ($raw -match '^(\d{4})\.(\d{2})\.(\d{2})') {
        return [int]("$($Matches[1])$($Matches[2])$($Matches[3])")
    }
    return 0
}

if ((Get-YtdlpDate) -ge $MinYtdlp) {
    Say "yt-dlp is current"
} else {
    Step "install the current yt-dlp into $BinDir" {
        Invoke-WebRequest -UseBasicParsing `
            -Uri 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe' `
            -OutFile (Join-Path $BinDir 'yt-dlp.exe')
    }
}

# ----------------------------------------------------------------- player ---
Step "download the player to $AppFile" {
    Download "$PagesUrl/crt-music" $AppFile
    $got = (Get-FileHash -Algorithm SHA256 $AppFile).Hash.ToLower()
    if ($got -ne $AppSha256) {
        Remove-Item -Force $AppFile -ErrorAction SilentlyContinue
        Die "the downloaded player does not match its published checksum.
expected $AppSha256
got      $got"
    }
}

Step "write the launcher $LauncherFile" {
    @"
@echo off
rem FSpotify launcher, written by install.ps1.
set "PATH=%LOCALAPPDATA%\crt-music\bin;%PATH%"
"$python" "$AppFile" %*
"@ | Set-Content -Path $LauncherFile -Encoding ASCII
}

# PATH, for new terminals. Without this the install works but the command is
# not found, which is the usual way a per-user install looks broken.
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not $userPath -or $userPath.Split(';') -notcontains $BinDir) {
    Step "add $BinDir to your PATH" {
        $new = if ($userPath) { "$userPath;$BinDir" } else { $BinDir }
        [Environment]::SetEnvironmentVariable('Path', $new, 'User')
    }
}

Step 'add a Start menu shortcut' {
    $programs = [Environment]::GetFolderPath('Programs')
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut((Join-Path $programs 'FSpotify.lnk'))
    $link.TargetPath = $LauncherFile
    $link.WorkingDirectory = $Root
    $link.Description = 'Search and stream music and internet radio in a terminal'
    $link.Save()
}

if ($DryRun) {
    Say 'Dry run finished; nothing was changed.'
    exit 0
}

Say 'Checking the installation'
& $python $AppFile --check
Write-Host ''
Say 'Done. Open a new terminal and run:  crt-music'
Say 'Windows Terminal draws the interface better than the old console window.'
