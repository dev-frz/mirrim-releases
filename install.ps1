# otto installer (Windows): downloads the latest self-contained release
# (no .NET required), verifies its SHA-256 checksum, installs it per-user, and
# registers a Scheduled Task that runs otto as a *background* service — no
# terminal window to accidentally close — and keeps it running (watchdog +
# restart-on-failure, on battery power too).
#
#   irm https://raw.githubusercontent.com/ferozhussain/otto-releases/main/install.ps1 | iex
#
# On a first install it asks two questions (skipped on upgrades):
#   - which port the web console should listen on          (default 5080)
#   - whether to expose the console to your local network  (default no; when
#     yes, a CONSOLE_API_TOKEN is generated so access is always authenticated)
# Non-interactive/scripted installs can preset both: $env:OTTO_PORT and
# $env:OTTO_EXPOSE_LAN ("true"/"false"). These also work on re-runs to change
# the settings later.
#
# This is the public release channel — no token is needed to install. You can
# optionally set $env:GITHUB_TOKEN to avoid GitHub's unauthenticated API rate
# limit when looking up the latest release.
#
# Re-running upgrades the binary in place and keeps your data (.env, agent.db).
# Pin a version with $env:OTTO_VERSION = "v1.2.3".
$ErrorActionPreference = "Stop"
# PS5's Invoke-WebRequest progress bar slows downloads dramatically; we print our own detail lines.
$ProgressPreference = "SilentlyContinue"

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
$FirewallRuleName = "otto web console"

function Say($msg)    { Write-Host "==> $msg" -ForegroundColor Cyan }
function Detail($msg) { Write-Host "    $msg" -ForegroundColor DarkGray }
function Warn($msg)   { Write-Host "warn: $msg" -ForegroundColor Yellow }

# --- Small helpers -----------------------------------------------------------
function Get-EnvValue([string]$File, [string]$Key) {
    if (-not (Test-Path $File)) { return $null }
    $m = Select-String -Path $File -Pattern "^$([regex]::Escape($Key))=(.*)$" | Select-Object -Last 1
    if ($m) { $v = $m.Matches[0].Groups[1].Value.Trim(); if ($v) { return $v } }
    return $null
}

function Set-EnvValue([string]$File, [string]$Key, [string]$Value) {
    $line = "$Key=$Value"
    $pattern = "^$([regex]::Escape($Key))="
    if ((Test-Path $File) -and (Select-String -Path $File -Pattern $pattern -Quiet)) {
        $content = Get-Content $File | ForEach-Object { if ($_ -match $pattern) { $line } else { $_ } }
        Set-Content -Path $File -Value $content
    } else {
        Add-Content -Path $File -Value $line
    }
}

function New-RandomToken {
    $bytes = New-Object byte[] 32
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return ([System.BitConverter]::ToString($bytes) -replace '-', '').ToLowerInvariant()
}

function Test-TruthyFlag($value) {
    return $value -and ($value.ToString().Trim() -match '^(1|y|yes|true)$')
}

$Interactive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected

# --- What this run is going to do --------------------------------------------
Say "otto installer starting."
Detail "Machine:      $env:COMPUTERNAME (Windows, x64) — PowerShell $($PSVersionTable.PSVersion)"
Detail "Install root: $Root"
Detail "  app (binary, replaced on upgrade): $AppDir"
Detail "  data (.env, agent.db — always kept): $DataDir"
Detail "Release channel: github.com/$Repo"

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

# --- First install? Ask the two setup questions up front ----------------------
$envFile = Join-Path $DataDir ".env"
$firstInstall = -not (Test-Path $envFile)

# Defaults / presets. On upgrades the current .env values are the defaults, so
# re-running the installer never silently changes an existing setup.
$Port = $null
$ExposeLan = $null
if ($env:OTTO_PORT) {
    if (($env:OTTO_PORT -match '^\d+$') -and ([int]$env:OTTO_PORT -ge 1) -and ([int]$env:OTTO_PORT -le 65535)) {
        $Port = [int]$env:OTTO_PORT
        Detail "Console port preset via OTTO_PORT: $Port"
    } else {
        Warn "Ignoring invalid OTTO_PORT '$($env:OTTO_PORT)' (expected 1-65535)."
    }
}
if ($null -ne $env:OTTO_EXPOSE_LAN -and $env:OTTO_EXPOSE_LAN -ne "") {
    $ExposeLan = Test-TruthyFlag $env:OTTO_EXPOSE_LAN
    Detail "Local-network exposure preset via OTTO_EXPOSE_LAN: $ExposeLan"
}

if (-not $firstInstall) {
    if ($null -eq $Port) {
        $existing = Get-EnvValue $envFile "Console__Port"
        $Port = if ($existing -match '^\d+$') { [int]$existing } else { 5080 }
    }
    if ($null -eq $ExposeLan) { $ExposeLan = Test-TruthyFlag (Get-EnvValue $envFile "Console__ExposeToNetwork") }
    Say "Existing install detected - upgrading in place (settings kept: port $Port, network exposure: $(if ($ExposeLan) { 'yes' } else { 'no' }))."
} elseif ($Interactive) {
    Say "First install - two quick questions (press Enter for the default):"
    while ($null -eq $Port) {
        $answer = Read-Host "    Web console port [5080]"
        if ([string]::IsNullOrWhiteSpace($answer)) { $Port = 5080 }
        elseif (($answer -match '^\d+$') -and ([int]$answer -ge 1) -and ([int]$answer -le 65535)) { $Port = [int]$answer }
        else { Warn "'$answer' is not a valid port (1-65535)." }
    }
    if ($null -eq $ExposeLan) {
        Write-Host "    Expose the web console to your local network (other devices on your Wi-Fi/LAN)?" -ForegroundColor Gray
        Write-Host "    A console token is generated so access always requires signing in. Default is no" -ForegroundColor DarkGray
        Write-Host "    (localhost only); you can change it later with: otto config set Console__ExposeToNetwork true" -ForegroundColor DarkGray
        $answer = Read-Host "    Expose to local network? [y/N]"
        $ExposeLan = Test-TruthyFlag $answer
    }
} else {
    if ($null -eq $Port) { $Port = 5080 }
    if ($null -eq $ExposeLan) { $ExposeLan = $false }
    Detail "Non-interactive session: using defaults (port $Port, exposure $ExposeLan)."
    Detail "Preset them with `$env:OTTO_PORT / `$env:OTTO_EXPOSE_LAN when scripting this installer."
}

# --- Pick the release ---------------------------------------------------------
$version = if ($env:OTTO_VERSION) { $env:OTTO_VERSION } else { $env:SELF_ASSIST_VERSION }
if ($version) {
    Say "Using pinned version $version (from OTTO_VERSION)."
} else {
    Say "Looking up the latest release..."
    Detail "GET https://api.github.com/repos/$Repo/releases/latest$(if ($Token) { ' (authenticated)' })"
    try {
        $version = (Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest" -Headers $AuthHeaders).tag_name
    } catch {
        throw "Could not determine the latest release. Are releases published yet? See https://github.com/$Repo/releases, or pin one with `$env:OTTO_VERSION. ($_)"
    }
    if (-not $version) { throw "Could not determine the latest release. Pin one with `$env:OTTO_VERSION." }
    Detail "Latest release: $version"
}
$asset = "otto-$version-win-x64.zip"

# --- Download and verify ------------------------------------------------------
$tmp = Join-Path ([IO.Path]::GetTempPath()) "otto-install"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$zip = Join-Path $tmp $asset

Say "Downloading $asset ..."
Detail "GET https://github.com/$Repo/releases/download/$version/$asset"
Invoke-WebRequest -Uri "https://github.com/$Repo/releases/download/$version/$asset" -OutFile $zip
Detail ("Downloaded {0:N1} MB to {1}" -f ((Get-Item $zip).Length / 1MB), $zip)

Say "Verifying the SHA-256 checksum..."
$sumsFile = Join-Path $tmp "SHA256SUMS"
$expected = $null
try {
    Invoke-WebRequest -Uri "https://github.com/$Repo/releases/download/$version/SHA256SUMS" -OutFile $sumsFile
    $line = Select-String -Path $sumsFile -Pattern ([regex]::Escape($asset)) | Select-Object -First 1
    if ($line) { $expected = ($line.Line -split '\s+')[0].ToLowerInvariant() }
} catch {
    $expected = $null
}
if ($expected) {
    $actual = (Get-FileHash -Path $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) {
        throw "Checksum mismatch for ${asset}: expected $expected but got $actual. Aborting - the download is corrupt or tampered with."
    }
    Detail "OK: sha256 $actual matches the release's SHA256SUMS."
} else {
    Warn "No SHA256SUMS entry found for $asset on release $version - skipping verification."
}

# Stop a running instance before replacing the binary (ignore if not installed).
Say "Stopping any running otto instance..."
Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue | Stop-ScheduledTask -ErrorAction SilentlyContinue
Get-Process -Name "otto" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

Say "Installing to $AppDir ..."
if (Test-Path $AppDir) { Remove-Item -Recurse -Force $AppDir }
New-Item -ItemType Directory -Force -Path $AppDir, $DataDir | Out-Null
Expand-Archive -Path $zip -DestinationPath $AppDir -Force
Remove-Item -Recurse -Force $tmp
Detail "Extracted $((Get-ChildItem $AppDir -Recurse -File | Measure-Object).Count) files."

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

# --- Write the chosen console settings to .env --------------------------------
# First install: seed the data directory with the .env template.
if ($firstInstall) { Copy-Item (Join-Path $AppDir ".env.example") $envFile }

Say "Applying console settings to $envFile ..."
Set-EnvValue $envFile "Console__Port" "$Port"
Set-EnvValue $envFile "Console__ExposeToNetwork" $(if ($ExposeLan) { "true" } else { "false" })
Detail "Console__Port=$Port"
Detail "Console__ExposeToNetwork=$(if ($ExposeLan) { 'true' } else { 'false' })"
$consoleToken = Get-EnvValue $envFile "CONSOLE_API_TOKEN"
$tokenGenerated = $false
if ($ExposeLan -and -not $consoleToken) {
    # Network exposure is refused by the app unless a console token exists — generate one
    # so the exposed console always requires signing in.
    $consoleToken = New-RandomToken
    Set-EnvValue $envFile "CONSOLE_API_TOKEN" $consoleToken
    $tokenGenerated = $true
    Detail "CONSOLE_API_TOKEN=<generated 64-char token> (required for network access; stored only in .env)"
} elseif ($ExposeLan) {
    Detail "CONSOLE_API_TOKEN already set - keeping it."
}

# --- Register the scheduled task ----------------------------------------------
# The task runs otto.exe with --hidden so no terminal window appears (closing such a
# window used to kill the agent). Preferred logon type is S4U: the task then runs in
# the background — outside the interactive desktop, even before you log on — which is
# what a 24/7 service should do. Some environments (e.g. Azure AD-only accounts or
# restrictive policy) reject S4U; those fall back to an interactive logon task whose
# console window otto hides itself.
function Register-OttoTask([string]$LogonType) {
    $action = New-ScheduledTaskAction -Execute (Join-Path $AppDir "otto.exe") -Argument "--hidden" -WorkingDirectory $DataDir
    $logonTrigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    # Watchdog: fires every 5 minutes (for 10 years — effectively forever, and a finite
    # duration serializes reliably where [TimeSpan]::MaxValue can be rejected);
    # MultipleInstances=IgnoreNew makes it a no-op while otto runs and a restart when it
    # doesn't (crash, Task Manager kill, or a reboot nobody logged on after).
    $watchdog = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
        -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 3650)
    $settings = New-ScheduledTaskSettingsSet `
        -MultipleInstances IgnoreNew `
        -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -RestartCount 10 -RestartInterval (New-TimeSpan -Minutes 1) `
        -ExecutionTimeLimit ([TimeSpan]::Zero) -StartWhenAvailable
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType $LogonType -RunLevel Limited
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $logonTrigger, $watchdog `
        -Settings $settings -Principal $principal -Force | Out-Null
}

function Start-OttoAndConfirm {
    try { Start-ScheduledTask -TaskName $TaskName } catch { return $false }
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 750
        if (Get-Process -Name "otto" -ErrorAction SilentlyContinue) { return $true }
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($task -and $task.State -eq "Running") { return $true }
    }
    return $false
}

Say "Registering the background service (Scheduled Task '$TaskName')..."
Detail "Action:    otto.exe --hidden (working dir $DataDir) - runs with no terminal window"
Detail "Triggers:  at logon + a 5-minute watchdog that restarts otto if it ever stops"
Detail "Policy:    restart on failure (10x, 1 min apart); keeps running on battery power"
$serviceMode = "background task (S4U): no window, starts even before you log on"
$started = $false
try {
    Register-OttoTask -LogonType "S4U"
    $started = Start-OttoAndConfirm
    if (-not $started) { throw "the background task did not start" }
} catch {
    Warn "Background (S4U) task unavailable here ($($_.Exception.Message.Trim())) - using an interactive logon task instead (otto hides its own window)."
    $serviceMode = "logon task (hidden window)"
    try {
        Register-OttoTask -LogonType "Interactive"
        $started = Start-OttoAndConfirm
    } catch {
        Warn "Could not register the scheduled task at all ($($_.Exception.Message.Trim()))."
        Warn "otto is installed but has no service. Start it manually with:  cd $DataDir; & '$AppDir\otto.exe'"
        $serviceMode = "NOT registered - manual start required"
        $started = $false
    }
}
if ($started) {
    Say "Service registered and running: $serviceMode."
} else {
    $info = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue
    $lastResult = if ($info) { "0x{0:X}" -f $info.LastTaskResult } else { "unknown" }
    Warn "otto did not confirm startup (last task result: $lastResult)."
    Warn "Try:  schtasks /Run /TN $TaskName   then check logs in $DataDir\logs\ (or 'otto logs')."
}

# --- Firewall (only relevant when exposing to the local network) --------------
if ($ExposeLan) {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        Say "Configuring Windows Firewall for the console port..."
        Get-NetFirewallRule -DisplayName $FirewallRuleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
        New-NetFirewallRule -DisplayName $FirewallRuleName -Direction Inbound -Action Allow `
            -Protocol TCP -LocalPort $Port -Profile Domain, Private | Out-Null
        Detail "Rule '$FirewallRuleName': allow inbound TCP $Port on Private/Domain networks."
    } else {
        Say "Windows Firewall will likely block other devices until TCP $Port is allowed."
        Detail "Run this once from an *elevated* (Administrator) PowerShell:"
        Write-Host "        New-NetFirewallRule -DisplayName '$FirewallRuleName' -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port -Profile Domain,Private"
    }
}

# --- Done -----------------------------------------------------------------------
$lanIp = $null
if ($ExposeLan) {
    $lanIp = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254)' } |
        Select-Object -First 1).IPAddress
}

Write-Host ""
Say "Install summary"
Detail "Version:   $version"
Detail "App:       $AppDir"
Detail "Data:      $DataDir  (.env, agent.db, logs - kept across upgrades)"
Detail "Service:   Scheduled Task '$TaskName' - $serviceMode"
Detail "Console:   http://localhost:$Port$(if ($ExposeLan) { if ($lanIp) { "  +  http://${lanIp}:$Port (local network)" } else { '  + your machine''s IP on the local network' } } else { '  (localhost only)' })"
if ($ExposeLan -and $consoleToken) {
    Detail "Sign-in token for other devices (from CONSOLE_API_TOKEN in $envFile):"
    Detail "  $consoleToken"
}
Detail "Logs:      $DataDir\logs\   (or 'otto logs')"
Detail "Uninstall: irm https://raw.githubusercontent.com/$Repo/main/uninstall.ps1 | iex"
Write-Host ""
if ($firstInstall) {
    Say "Installed. Finish setup in your browser:"
    Write-Host ""
    Write-Host "        http://localhost:$Port"
    Write-Host ""
    Write-Host "    Pick a provider and paste your key — it's saved to $envFile"
    Write-Host "    and the agent restarts into normal mode automatically."
    if ($ExposeLan) {
        Write-Host "    Note: for safety, first-run setup only answers on THIS machine (localhost)."
        Write-Host "    The local-network URL starts working right after setup completes."
    }
    Write-Host "    Prefer the terminal (or a headless/Server Core host)? Run:  otto setup"
    Write-Host "    Remote box with no local browser? Forward the port from your machine:"
    Write-Host "        ssh -L ${Port}:localhost:$Port <user>@<this-host>   # then open http://localhost:$Port"
    Write-Host ""
} else {
    Say "Upgraded to $version. Your data in $DataDir was kept."
    Say "Open http://localhost:$Port"
}
