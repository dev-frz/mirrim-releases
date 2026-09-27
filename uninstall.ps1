# mirrim uninstaller (Windows): stops and removes the scheduled task, the
# PATH entry, and the installed binary. Your data (.env, agent.db) is KEPT by
# default — pass -Purge to delete the data directory too.
#
#   irm https://raw.githubusercontent.com/dev-frz/mirrim-releases/main/uninstall.ps1 | iex
#   # to also delete data, download and run with the switch:
#   #   iwr https://raw.githubusercontent.com/dev-frz/mirrim-releases/main/uninstall.ps1 -OutFile uninstall.ps1; ./uninstall.ps1 -Purge
#
# Honors $env:MIRRIM_HOME (same as the installer; $env:OTTO_HOME still works) for
# a non-default install. Pre-rename otto and self-assist artifacts are removed too.
param([switch]$Purge)
$ErrorActionPreference = "Stop"

$DefaultRoot = Join-Path $env:LOCALAPPDATA "mirrim"
$OttoRoot = Join-Path $env:LOCALAPPDATA "otto"
# A pre-rename install that was never upgraded still lives at the otto root.
if (-not (Test-Path $DefaultRoot) -and (Test-Path $OttoRoot)) { $DefaultRoot = $OttoRoot }
$Root = if ($env:MIRRIM_HOME) { $env:MIRRIM_HOME } elseif ($env:OTTO_HOME) { $env:OTTO_HOME } else { $DefaultRoot }
$AppDir = Join-Path $Root "app"
$DataDir = Join-Path $Root "data"
$TaskName = "mirrim"
$OttoTaskName = "otto"

function Say($msg)  { Write-Host "==> $msg" -ForegroundColor Cyan }
function Warn($msg) { Write-Host "warn: $msg" -ForegroundColor Yellow }

# --- Stop and remove the scheduled task -------------------------------------
$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($task) {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Say "Removed the scheduled task '$TaskName'."
}
Get-Process -Name "mirrim", "otto" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# --- Remove the firewall rules the installer may have added (needs elevation; best-effort)
foreach ($ruleName in @("mirrim web console", "otto web console")) {
    try {
        $fw = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
        if ($fw) {
            $fw | Remove-NetFirewallRule -ErrorAction Stop
            Say "Removed the '$ruleName' firewall rule."
        }
    } catch {
        Warn "Could not remove the '$ruleName' firewall rule (needs an elevated PowerShell)."
    }
}

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

# --- Pre-rename otto artifacts (otto -> mirrim, 2026-08) -----------------------
if (Get-ScheduledTask -TaskName $OttoTaskName -ErrorAction SilentlyContinue) {
    Stop-ScheduledTask -TaskName $OttoTaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $OttoTaskName -Confirm:$false -ErrorAction SilentlyContinue
    Say "Removed the pre-rename scheduled task '$OttoTaskName'."
}
if (($Root -ne $OttoRoot) -and (Test-Path $OttoRoot)) {
    $ottoApp = Join-Path $OttoRoot "app"
    if (Test-Path $ottoApp) { Remove-Item -Recurse -Force $ottoApp }
    $ottoUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($ottoUserPath) {
        $kept = ($ottoUserPath -split ';' | Where-Object { $_ -and $_ -ne $ottoApp }) -join ';'
        if ($kept -ne $ottoUserPath) { [Environment]::SetEnvironmentVariable("Path", $kept, "User") }
    }
    if ($Purge) {
        Remove-Item -Recurse -Force $OttoRoot
        Say "Purged the pre-rename data directory $OttoRoot."
    } elseif (-not (Get-ChildItem -Force $OttoRoot -ErrorAction SilentlyContinue)) {
        Remove-Item -Force $OttoRoot -ErrorAction SilentlyContinue
    } else {
        Say "Kept pre-rename data in $OttoRoot (remove with -Purge)."
    }
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
Say "mirrim uninstalled."
