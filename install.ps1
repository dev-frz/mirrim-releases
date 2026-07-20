# otto installer (Windows): downloads the latest self-contained release
# (no .NET required), installs it per-user, and registers a Scheduled Task that
# starts the agent at logon and keeps it running.
#
#   irm https://raw.githubusercontent.com/ferozhussain/otto-releases/main/install.ps1 | iex
#
# This is the public release channel — no token is needed to install. You can
# optionally set $env:GITHUB_TOKEN to avoid GitHub's unauthenticated API rate
# limit when looking up the latest release.
#
# Re-running upgrades the binary in place and keeps your data (.env, agent.db).
# Pin a version with $env:OTTO_VERSION = "v1.2.3".
$ErrorActionPreference = "Stop"

$Repo = "ferozhussain/otto-releases"
$Token = if ($env:GITHUB_TOKEN) { $env:GITHUB_TOKEN } elseif ($env:GH_TOKEN) { $env:GH_TOKEN } else { $null }
$AuthHeaders = if ($Token) { @{ Authorization = "Bearer $Token" } } else { @{} }
# OTTO_HOME wins; SELF_ASSIST_HOME is honored as the legacy (pre-rebrand) name.
$Root = if ($env:OTTO_HOME) { $env:OTTO_HOME }
        elseif ($env:SELF_ASSIST_HOME) { $env:SELF_ASSIST_HOME }
        else { Join-Path $env:LOCALAPPDATA "otto" }
$AppDir = Join-Path $Root "app"
$DataDir = Join-Path $Root "data"
$TaskName = "otto"

function Say($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

# --- Migrate a legacy self-assist install (pre-rebrand) ---------------------------
# The product was renamed self-assist -> otto. If the old install is present (and we
# aren't deliberately reusing its root via SELF_ASSIST_HOME), retire its scheduled
# task, carry the data (.env, agent.db) over, and clean up the old artifacts.
$OldRoot = Join-Path $env:LOCALAPPDATA "self-assist"
if (($Root -ne $OldRoot) -and (Test-Path $OldRoot)) {
    Say "Found a legacy self-assist install - migrating it to otto..."
    if (Get-ScheduledTask -TaskName "self-assist" -ErrorAction SilentlyContinue) {
        Stop-ScheduledTask -TaskName "self-assist" -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName "self-assist" -Confirm:$false -ErrorAction SilentlyContinue
    }
    Get-Process -Name "self-assist" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    $oldData = Join-Path $OldRoot "data"
    $newDataEmpty = -not (Test-Path $DataDir) -or -not (Get-ChildItem -Force $DataDir -ErrorAction SilentlyContinue)
    if ((Test-Path $oldData) -and $newDataEmpty) {
        if (Test-Path $DataDir) { Remove-Item -Recurse -Force $DataDir }
        New-Item -ItemType Directory -Force -Path $Root | Out-Null
        Move-Item $oldData $DataDir
        Say "Moved your data (.env, agent.db) to $DataDir."
    }
    $oldApp = Join-Path $OldRoot "app"
    if (Test-Path $oldApp) { Remove-Item -Recurse -Force $oldApp }
    # Drop the old app dir from the user PATH.
    $legacyPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($legacyPath) {
        $kept = ($legacyPath -split ';' | Where-Object { $_ -and $_ -ne $oldApp }) -join ';'
        if ($kept -ne $legacyPath) { [Environment]::SetEnvironmentVariable("Path", $kept, "User") }
    }
    if (-not (Get-ChildItem -Force $OldRoot -ErrorAction SilentlyContinue)) {
        Remove-Item -Force $OldRoot -ErrorAction SilentlyContinue
    }
    Say "Legacy self-assist task and app removed."
}

# --- Pick the release ---------------------------------------------------------
$version = if ($env:OTTO_VERSION) { $env:OTTO_VERSION } else { $env:SELF_ASSIST_VERSION }
if (-not $version) {
    Say "Looking up the latest release..."
    try {
        $version = (Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest" -Headers $AuthHeaders).tag_name
    } catch {
        throw "Could not determine the latest release. Are releases published yet? See https://github.com/$Repo/releases, or pin one with `$env:OTTO_VERSION. ($_)"
    }
    if (-not $version) { throw "Could not determine the latest release. Pin one with `$env:OTTO_VERSION." }
}
$asset = "otto-$version-win-x64.zip"

# --- Download and install ------------------------------------------------------
$tmp = Join-Path ([IO.Path]::GetTempPath()) "otto-install"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$zip = Join-Path $tmp $asset

Say "Downloading $asset ..."
Invoke-WebRequest -Uri "https://github.com/$Repo/releases/download/$version/$asset" -OutFile $zip

# Stop a running instance before replacing the binary (ignore if not installed).
Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue | Stop-ScheduledTask -ErrorAction SilentlyContinue
Get-Process -Name "otto" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

Say "Installing to $AppDir ..."
if (Test-Path $AppDir) { Remove-Item -Recurse -Force $AppDir }
New-Item -ItemType Directory -Force -Path $AppDir, $DataDir | Out-Null
Expand-Archive -Path $zip -DestinationPath $AppDir -Force
Remove-Item -Recurse -Force $tmp

# Put `otto` on PATH (user scope) so the CLI works by name — matching the docs —
# without the user editing PATH themselves. Idempotent across re-runs/upgrades.
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if (-not (($userPath -split ';') -contains $AppDir)) {
    $newPath = if ([string]::IsNullOrEmpty($userPath)) { $AppDir } else { "$userPath;$AppDir" }
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    Say "Added $AppDir to your user PATH (open a new terminal to use 'otto')."
} else {
    Say "$AppDir is already on your user PATH."
}
# Make it usable in this session too, so the steps printed below work right away.
if (-not (($env:Path -split ';') -contains $AppDir)) { $env:Path = "$env:Path;$AppDir" }

# First install: seed the data directory with the .env template.
$envFile = Join-Path $DataDir ".env"
$firstInstall = -not (Test-Path $envFile)
if ($firstInstall) { Copy-Item (Join-Path $AppDir ".env.example") $envFile }

# --- Register the scheduled task (per-user, starts at logon, restarts on crash) --
$action = New-ScheduledTaskAction -Execute (Join-Path $AppDir "otto.exe") -WorkingDirectory $DataDir
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet `
    -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -StartWhenAvailable
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
if ($firstInstall) {
    # Start it now: with no key it comes up in first-run SETUP MODE, serving a browser
    # setup page at http://localhost:5080 so you can finish setup without editing files.
    Start-ScheduledTask -TaskName $TaskName
    Say "Registered and started the scheduled task '$TaskName' in first-run setup mode."
} else {
    Start-ScheduledTask -TaskName $TaskName
    Say "Registered and started the scheduled task '$TaskName' (runs at logon)."
}

# --- Done -----------------------------------------------------------------------
Write-Host ""
if ($firstInstall) {
    Say "Installed. Finish setup in your browser:"
    Write-Host ""
    Write-Host "        http://localhost:5080"
    Write-Host ""
    Write-Host "    Pick a provider and paste your key — it's saved to $envFile"
    Write-Host "    and the agent restarts into normal mode automatically."
    Write-Host "    Prefer the terminal (or a headless/Server Core host)? Run:  otto setup"
    Write-Host "    Remote box with no local browser? Forward the port from your machine:"
    Write-Host "        ssh -L 5080:localhost:5080 <user>@<this-host>   # then open http://localhost:5080"
    Write-Host ""
} else {
    Say "Upgraded to $version. Your data in $DataDir was kept."
    Say "Open http://localhost:5080"
}
