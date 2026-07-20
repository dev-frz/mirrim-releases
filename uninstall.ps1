# otto uninstaller (Windows): stops and removes the scheduled task, the
# PATH entry, and the installed binary. Your data (.env, agent.db) is KEPT by
# default — pass -Purge to delete the data directory too.
#
#   irm https://raw.githubusercontent.com/ferozhussain/otto-releases/main/uninstall.ps1 | iex
#   # to also delete data, download and run with the switch:
#   #   iwr https://raw.githubusercontent.com/ferozhussain/otto-releases/main/uninstall.ps1 -OutFile uninstall.ps1; ./uninstall.ps1 -Purge
#
# Honors $env:OTTO_HOME (same as the installer) for a non-default install.
param([switch]$Purge)
$ErrorActionPreference = "Stop"

$Root = if ($env:OTTO_HOME) { $env:OTTO_HOME } else { Join-Path $env:LOCALAPPDATA "otto" }
$AppDir = Join-Path $Root "app"
$DataDir = Join-Path $Root "data"
$TaskName = "otto"

function Say($msg)  { Write-Host "==> $msg" -ForegroundColor Cyan }
function Warn($msg) { Write-Host "warn: $msg" -ForegroundColor Yellow }

# --- Stop and remove the scheduled task -------------------------------------
$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($task) {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Say "Removed the scheduled task '$TaskName'."
}
Get-Process -Name "otto" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# --- Remove the app dir from the user PATH ----------------------------------
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath) {
    $parts = $userPath -split ';' | Where-Object { $_ -and $_ -ne $AppDir }
    $newPath = ($parts -join ';')
    if ($newPath -ne $userPath) {
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        Say "Removed $AppDir from your user PATH (open a new terminal to refresh)."
    }
}

# --- Remove the app directory (always) --------------------------------------
if (Test-Path $AppDir) {
    Remove-Item -Recurse -Force $AppDir
    Say "Removed the app directory $AppDir."
}

# --- Data directory: keep unless -Purge -------------------------------------
if ($Purge) {
    if (Test-Path $DataDir) {
        Remove-Item -Recurse -Force $DataDir
        Say "Purged the data directory $DataDir (.env, agent.db, logs)."
    }
    if ((Test-Path $Root) -and -not (Get-ChildItem -Force $Root -ErrorAction SilentlyContinue)) {
        Remove-Item -Force $Root -ErrorAction SilentlyContinue
    }
} elseif (Test-Path $DataDir) {
    Say "Kept your data in $DataDir (.env, agent.db). Delete it with: Remove-Item -Recurse -Force `"$DataDir`""
    Say "Or re-run with -Purge to remove everything."
}

# --- Legacy self-assist artifacts (pre-rebrand) ------------------------------
# Clean up an old install too, so uninstalling after the rename leaves nothing behind.
if (Get-ScheduledTask -TaskName "self-assist" -ErrorAction SilentlyContinue) {
    Stop-ScheduledTask -TaskName "self-assist" -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName "self-assist" -Confirm:$false -ErrorAction SilentlyContinue
    Say "Removed the legacy scheduled task 'self-assist'."
}
$OldRoot = Join-Path $env:LOCALAPPDATA "self-assist"
$oldApp = Join-Path $OldRoot "app"
if (Test-Path $oldApp) { Remove-Item -Recurse -Force $oldApp }
$oldUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($oldUserPath) {
    $kept = ($oldUserPath -split ';' | Where-Object { $_ -and $_ -ne $oldApp }) -join ';'
    if ($kept -ne $oldUserPath) { [Environment]::SetEnvironmentVariable("Path", $kept, "User") }
}
if (Test-Path $OldRoot) {
    if ($Purge) {
        Remove-Item -Recurse -Force $OldRoot
        Say "Purged the legacy data directory $OldRoot."
    } elseif (-not (Get-ChildItem -Force $OldRoot -ErrorAction SilentlyContinue)) {
        Remove-Item -Force $OldRoot -ErrorAction SilentlyContinue
    } else {
        Say "Kept legacy data in $OldRoot (remove with -Purge)."
    }
}

Write-Host ""
Say "otto uninstalled."
