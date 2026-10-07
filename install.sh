#!/usr/bin/env bash
# mirrim installer (Linux + macOS): downloads the latest self-contained
# release (no .NET required), verifies its SHA-256 checksum, installs it
# per-user, and registers a managed 24/7 service (systemd --user on Linux,
# launchd LaunchAgent on macOS).
#
#   curl -fsSL https://raw.githubusercontent.com/dev-frz/mirrim-releases/main/install.sh | bash
#
# On a first install it asks two questions (skipped on upgrades):
#   - which port the web console should listen on          (default 5080)
#   - whether to expose the console to your local network  (default no; when
#     yes, a CONSOLE_API_TOKEN is generated so access is always authenticated)
# Non-interactive/scripted installs can preset both: MIRRIM_PORT=5080 and
# MIRRIM_EXPOSE_LAN=true|false (the pre-rename OTTO_* spellings still work).
# These also work on re-runs to change the settings later.
#
# This is the public release channel — no token is needed to install. You can
# optionally export GITHUB_TOKEN to avoid GitHub's unauthenticated API rate
# limit when looking up the latest release:
#
#   export GITHUB_TOKEN=ghp_...
#   curl -fsSL https://raw.githubusercontent.com/dev-frz/mirrim-releases/main/install.sh | bash
#
# Re-running upgrades the binary in place and keeps your data (.env, agent.db).
# Pin a version with MIRRIM_VERSION=v1.2.3.
#
# Naming: the product was called otto until 2026-08 and is now mirrim. The
# binary, service, and default install root carry the new name; an `otto`
# command alias is kept for one release cycle, every OTTO_* / SELF_ASSIST_*
# environment spelling is still honored, and an existing otto install is
# migrated in place (data kept) the first time this runs.
set -euo pipefail

# The public release channel (renamed from otto-releases on 2026-09-27; GitHub
# redirects the old name, so pre-rename installers keep working too).
REPO="dev-frz/mirrim-releases"
# MIRRIM_HOME wins; OTTO_HOME and SELF_ASSIST_HOME are honored as the older names.
DEFAULT_ROOT="$HOME/.local/share/mirrim"
ROOT="${MIRRIM_HOME:-${OTTO_HOME:-${SELF_ASSIST_HOME:-$DEFAULT_ROOT}}}"
APP_DIR="$ROOT/app"
DATA_DIR="$ROOT/data"
SERVICE_NAME="mirrim"
LAUNCHD_LABEL="com.mirrim.agent"
# Pre-rename install (otto): its root, service, and launchd label.
OTTO_ROOT="$HOME/.local/share/otto"
OTTO_SERVICE_NAME="otto"
OTTO_LAUNCHD_LABEL="com.ottoagent.otto"
TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"

say()    { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
detail() { printf '\033[0;90m    %s\033[0m\n' "$*"; }
warn()   { printf '\033[1;33mwarn:\033[0m %s\n' "$*"; }
fail()   { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# curl with the token attached when one is set (optional — only lifts the
# unauthenticated GitHub API rate limit on the release lookup below).
gh_curl() {
  if [ -n "$TOKEN" ]; then
    curl -fsSL -H "Authorization: Bearer $TOKEN" "$@"
  else
    curl -fsSL "$@"
  fi
}

# Set KEY=VALUE in an .env file: replace the existing line in place (keeping its
# position next to its doc comment) or append when the key is new.
env_set() { # file key value
  if grep -q "^$2=" "$1" 2>/dev/null; then
    sed -i.bak "s|^$2=.*|$2=$3|" "$1" && rm -f "$1.bak"
  else
    printf '%s=%s\n' "$2" "$3" >> "$1"
  fi
}

env_get() { # file key -> value (empty when unset)
  grep "^$2=" "$1" 2>/dev/null | tail -n1 | cut -d'=' -f2- || true
}

service_start_failed() { # the unit did not reach ready in time, or exited
  say "WARNING: '$SERVICE_NAME' did not report ready — the install is complete, but the service is not up yet."
  detail "systemd keeps retrying (Restart=on-failure). The last lines of its log:"
  journalctl --user -u "$SERVICE_NAME" -n 25 --no-pager 2>/dev/null | sed 's/^/    /' || true
  detail "Check:   systemctl --user status $SERVICE_NAME"
  detail "Follow:  journalctl --user -u $SERVICE_NAME -f"
  detail "A first start on an older database may be running a one-time VACUUM; let it finish."
}

gen_token() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
  else
    head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n'
  fi
}

command -v curl >/dev/null || fail "curl is required."
command -v tar  >/dev/null || fail "tar is required."

# --- Pick the release asset for this OS/arch --------------------------------
os=$(uname -s)
arch=$(uname -m)
case "$os/$arch" in
  Linux/x86_64)               rid="linux-x64" ;;
  Linux/aarch64|Linux/arm64)  rid="linux-arm64" ;;
  Darwin/x86_64)              rid="osx-x64" ;;
  Darwin/arm64)               rid="osx-arm64" ;;
  *) fail "unsupported platform: $os/$arch (supported: Linux/macOS on x64/arm64)" ;;
esac

# --- What this run is going to do --------------------------------------------
say "mirrim installer starting."
detail "Platform:     $os/$arch -> release build '$rid'"
detail "Install root: $ROOT"
detail "  app (binary, replaced on upgrade): $APP_DIR"
detail "  data (.env, agent.db - always kept): $DATA_DIR"
detail "Release channel: github.com/$REPO"

# --- Migrate a legacy self-assist install (pre-rebrand) ----------------------
# The product was renamed self-assist → otto. If the old install is present (and
# we're not deliberately reusing its root via SELF_ASSIST_HOME), retire its
# service, carry the data (.env, agent.db) over, and clean up the old artifacts.
OLD_ROOT="$HOME/.local/share/self-assist"
if [ "$ROOT" != "$OLD_ROOT" ] && [ -d "$OLD_ROOT" ]; then
  say "Found a legacy self-assist install — migrating it to mirrim..."
  if [ "$os" = "Linux" ] && command -v systemctl >/dev/null; then
    systemctl --user stop self-assist 2>/dev/null || true
    systemctl --user disable self-assist 2>/dev/null || true
    rm -f "$HOME/.config/systemd/user/self-assist.service"
    systemctl --user daemon-reload 2>/dev/null || true
  elif [ "$os" = "Darwin" ]; then
    launchctl bootout "gui/$(id -u)/com.selfassist.agent" 2>/dev/null || true
    rm -f "$HOME/Library/LaunchAgents/com.selfassist.agent.plist"
  fi
  if [ -d "$OLD_ROOT/data" ] && [ -z "$(ls -A "$DATA_DIR" 2>/dev/null)" ]; then
    rm -rf "$DATA_DIR"
    mkdir -p "$ROOT"
    mv "$OLD_ROOT/data" "$DATA_DIR"
    say "Moved your data (.env, agent.db) to $DATA_DIR."
  fi
  rm -rf "$OLD_ROOT/app"
  rm -f "$HOME/.local/bin/self-assist"
  rmdir "$OLD_ROOT" 2>/dev/null || true
  say "Legacy self-assist service and app removed."
fi

# --- Migrate a pre-rename otto install (otto → mirrim, 2026-08) ----------------
# Two independent steps, because either can apply on its own:
#  1. The service was registered as `otto`. Retire it whatever the root is — an
#     in-place upgrade with OTTO_HOME still exported must not leave two services
#     (otto and mirrim) fighting over the same port and database.
#  2. If the data lives at the old default root and the new root holds none yet,
#     move it (the same pattern as the self-assist migration above). Nothing is
#     deleted until it has been moved.
if [ "$os" = "Linux" ] && command -v systemctl >/dev/null; then
  if [ -f "$HOME/.config/systemd/user/$OTTO_SERVICE_NAME.service" ]; then
    say "Retiring the pre-rename systemd user service '$OTTO_SERVICE_NAME' (it comes back as '$SERVICE_NAME')..."
    systemctl --user stop "$OTTO_SERVICE_NAME" 2>/dev/null || true
    systemctl --user disable "$OTTO_SERVICE_NAME" 2>/dev/null || true
    rm -f "$HOME/.config/systemd/user/$OTTO_SERVICE_NAME.service"
    systemctl --user daemon-reload 2>/dev/null || true
  fi
elif [ "$os" = "Darwin" ]; then
  if [ -f "$HOME/Library/LaunchAgents/$OTTO_LAUNCHD_LABEL.plist" ]; then
    say "Retiring the pre-rename launchd agent '$OTTO_LAUNCHD_LABEL' (it comes back as '$LAUNCHD_LABEL')..."
    launchctl bootout "gui/$(id -u)/$OTTO_LAUNCHD_LABEL" 2>/dev/null || true
    rm -f "$HOME/Library/LaunchAgents/$OTTO_LAUNCHD_LABEL.plist"
  fi
fi
if [ "$ROOT" != "$OTTO_ROOT" ] && [ -d "$OTTO_ROOT" ]; then
  say "Found a pre-rename otto install at $OTTO_ROOT — migrating it to mirrim..."
  if [ -d "$OTTO_ROOT/data" ] && [ -z "$(ls -A "$DATA_DIR" 2>/dev/null)" ]; then
    rm -rf "$DATA_DIR"
    mkdir -p "$ROOT"
    mv "$OTTO_ROOT/data" "$DATA_DIR"
    say "Moved your data (.env, agent.db) to $DATA_DIR."
  fi
  rm -rf "$OTTO_ROOT/app"
  rmdir "$OTTO_ROOT" 2>/dev/null || true
  say "Pre-rename otto app removed (your data was kept)."
fi

# --- First install? Ask the two setup questions up front ----------------------
# Piped `curl | bash` runs with the script on stdin, so prompts read /dev/tty.
if [ -f "$DATA_DIR/.env" ]; then first_install=0; else first_install=1; fi

has_tty=0
if { : < /dev/tty; } 2>/dev/null && [ -w /dev/tty ]; then has_tty=1; fi

ask() { # prompt -> echoes the reply (empty on EOF)
  printf '%s' "$1" > /dev/tty
  local reply=""
  IFS= read -r reply < /dev/tty || true
  printf '%s' "$reply"
}

valid_port() { case "$1" in ''|*[!0-9]*) return 1 ;; *) [ "$1" -ge 1 ] && [ "$1" -le 65535 ] ;; esac; }

PORT="${MIRRIM_PORT:-${OTTO_PORT:-}}"
EXPOSE_LAN="${MIRRIM_EXPOSE_LAN:-${OTTO_EXPOSE_LAN:-}}"
if [ -n "$PORT" ] && ! valid_port "$PORT"; then
  warn "Ignoring invalid MIRRIM_PORT '$PORT' (expected 1-65535)."
  PORT=""
fi
[ -n "$PORT" ] && detail "Console port preset via MIRRIM_PORT: $PORT"
case "$EXPOSE_LAN" in
  1|y|Y|yes|true|TRUE|True) EXPOSE_LAN=1; detail "Local-network exposure preset via MIRRIM_EXPOSE_LAN: yes" ;;
  0|n|N|no|false|FALSE|False) EXPOSE_LAN=0; detail "Local-network exposure preset via MIRRIM_EXPOSE_LAN: no" ;;
  "") ;;
  *) warn "Ignoring invalid MIRRIM_EXPOSE_LAN '$EXPOSE_LAN' (expected true/false)."; EXPOSE_LAN="" ;;
esac

if [ "$first_install" = 0 ]; then
  # Upgrade: current .env values are the defaults, so re-running never silently
  # changes an existing setup (env presets above still override deliberately).
  if [ -z "$PORT" ]; then
    existing=$(env_get "$DATA_DIR/.env" "Console__Port")
    if valid_port "$existing"; then PORT="$existing"; else PORT=5080; fi
  fi
  if [ -z "$EXPOSE_LAN" ]; then
    case "$(env_get "$DATA_DIR/.env" "Console__ExposeToNetwork")" in
      true|True|TRUE|1) EXPOSE_LAN=1 ;;
      *) EXPOSE_LAN=0 ;;
    esac
  fi
  say "Existing install detected — upgrading in place (settings kept: port $PORT, network exposure: $([ "$EXPOSE_LAN" = 1 ] && echo yes || echo no))."
elif [ "$has_tty" = 1 ]; then
  say "First install — two quick questions (press Enter for the default):"
  while [ -z "$PORT" ]; do
    reply=$(ask "    Web console port [5080]: ")
    if [ -z "$reply" ]; then
      PORT=5080
    elif valid_port "$reply"; then
      PORT="$reply"
    else
      warn "'$reply' is not a valid port (1-65535)."
    fi
  done
  if [ -z "$EXPOSE_LAN" ]; then
    printf '    Expose the web console to your local network (other devices on your Wi-Fi/LAN)?\n' > /dev/tty
    printf '    A console token is generated so access always requires signing in. Default is no\n' > /dev/tty
    printf '    (localhost only); change later with: mirrim config set Console__ExposeToNetwork true\n' > /dev/tty
    reply=$(ask "    Expose to local network? [y/N]: ")
    case "$reply" in y|Y|yes|YES|Yes) EXPOSE_LAN=1 ;; *) EXPOSE_LAN=0 ;; esac
  fi
else
  [ -z "$PORT" ] && PORT=5080
  [ -z "$EXPOSE_LAN" ] && EXPOSE_LAN=0
  detail "No terminal available: using defaults (port $PORT, exposure $([ "$EXPOSE_LAN" = 1 ] && echo yes || echo no))."
  detail "Preset them with MIRRIM_PORT / MIRRIM_EXPOSE_LAN when scripting this installer."
fi

# --- Resolve the version ------------------------------------------------------
version="${MIRRIM_VERSION:-${OTTO_VERSION:-${SELF_ASSIST_VERSION:-}}}"
if [ -n "$version" ]; then
  say "Using pinned version $version (from MIRRIM_VERSION)."
else
  say "Looking up the latest release..."
  detail "GET https://api.github.com/repos/$REPO/releases/latest$([ -n "$TOKEN" ] && echo ' (authenticated)')"
  version=$(gh_curl "https://api.github.com/repos/$REPO/releases/latest" |
    grep -m1 '"tag_name"' | cut -d'"' -f4) || true
  if [ -z "$version" ]; then
    fail "could not determine the latest release. Are releases published yet? (Pin one with MIRRIM_VERSION=vX.Y.Z, or check https://github.com/$REPO/releases)"
  fi
  detail "Latest release: $version"
fi

asset="mirrim-$version-$rid.tar.gz"

# --- Download and verify ------------------------------------------------------
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

say "Downloading $asset ..."
url="https://github.com/$REPO/releases/download/$version/$asset"
detail "GET $url"
if ! curl -fsSL -o "$tmp/$asset" "$url"; then
  # Releases published before the binary rename (v0.9.x and older) carry
  # otto-* assets. A pinned old version still installs — under the new layout.
  legacy_asset="otto-$version-$rid.tar.gz"
  legacy_url="https://github.com/$REPO/releases/download/$version/$legacy_asset"
  detail "Not found; trying the pre-rename asset name: GET $legacy_url"
  curl -fsSL -o "$tmp/$legacy_asset" "$legacy_url" ||
    fail "download failed: $url (is $asset attached to release $version?)"
  asset="$legacy_asset"
fi
if command -v du >/dev/null 2>&1; then
  detail "Downloaded $(du -h "$tmp/$asset" | cut -f1 | tr -d ' ') to $tmp/$asset"
fi

say "Verifying the SHA-256 checksum..."
sha_tool=""
if command -v sha256sum >/dev/null 2>&1; then sha_tool="sha256sum"
elif command -v shasum >/dev/null 2>&1; then sha_tool="shasum -a 256"; fi
if [ -z "$sha_tool" ]; then
  warn "no sha256sum/shasum on this host — skipping verification."
elif curl -fsSL -o "$tmp/SHA256SUMS" "https://github.com/$REPO/releases/download/$version/SHA256SUMS" 2>/dev/null; then
  expected=$(grep " $asset\$" "$tmp/SHA256SUMS" | head -n1 | awk '{print $1}' || true)
  if [ -z "$expected" ]; then
    warn "no SHA256SUMS entry for $asset on release $version — skipping verification."
  else
    actual=$($sha_tool "$tmp/$asset" | awk '{print $1}')
    if [ "$actual" != "$expected" ]; then
      fail "checksum mismatch for $asset: expected $expected but got $actual — the download is corrupt or tampered with."
    fi
    detail "OK: sha256 $actual matches the release's SHA256SUMS."
  fi
else
  warn "SHA256SUMS not published for $version — skipping verification."
fi

# Stop a running service before replacing the binary (ignore if not installed).
say "Stopping any running mirrim service..."
if [ "$os" = "Linux" ] && command -v systemctl >/dev/null; then
  systemctl --user stop "$SERVICE_NAME" 2>/dev/null || true
elif [ "$os" = "Darwin" ]; then
  launchctl bootout "gui/$(id -u)/$LAUNCHD_LABEL" 2>/dev/null || true
fi

say "Installing to $APP_DIR ..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR" "$DATA_DIR"
tar -xzf "$tmp/$asset" -C "$APP_DIR"
# The binary is `mirrim`; releases ship an `otto` symlink beside it for one
# release cycle. A pre-rename release only has `otto` — give it the new name too,
# so the service unit and the docs below hold for every installable version.
if [ -e "$APP_DIR/mirrim" ]; then
  chmod +x "$APP_DIR/mirrim"
else
  chmod +x "$APP_DIR/otto"
  ln -s otto "$APP_DIR/mirrim"
fi
[ -e "$APP_DIR/otto" ] || ln -s mirrim "$APP_DIR/otto"
detail "Extracted $(find "$APP_DIR" -type f | wc -l | tr -d ' ') files."

# Put `mirrim` on PATH via a symlink in a per-user bin dir, so the CLI works
# by name (matching the docs) without the operator editing PATH themselves.
# `otto` stays resolvable as an alias for one release cycle.
BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"
ln -sf "$APP_DIR/mirrim" "$BIN_DIR/mirrim"
ln -sf "$APP_DIR/mirrim" "$BIN_DIR/otto"
case ":$PATH:" in
  *":$BIN_DIR:"*) on_path=1 ;;
  *)              on_path=0 ;;
esac

# --- Seed .env and write the chosen console settings --------------------------
if [ "$first_install" = 1 ]; then
  cp "$APP_DIR/.env.example" "$DATA_DIR/.env"
fi

say "Applying console settings to $DATA_DIR/.env ..."
env_set "$DATA_DIR/.env" "Console__Port" "$PORT"
env_set "$DATA_DIR/.env" "Console__ExposeToNetwork" "$([ "$EXPOSE_LAN" = 1 ] && echo true || echo false)"
detail "Console__Port=$PORT"
detail "Console__ExposeToNetwork=$([ "$EXPOSE_LAN" = 1 ] && echo true || echo false)"
console_token=$(env_get "$DATA_DIR/.env" "CONSOLE_API_TOKEN")
if [ "$EXPOSE_LAN" = 1 ] && [ -z "$console_token" ]; then
  # Network exposure is refused by the app unless a console token exists — generate one
  # so the exposed console always requires signing in.
  console_token=$(gen_token)
  env_set "$DATA_DIR/.env" "CONSOLE_API_TOKEN" "$console_token"
  detail "CONSOLE_API_TOKEN=<generated 64-char token> (required for network access; stored only in .env)"
elif [ "$EXPOSE_LAN" = 1 ]; then
  detail "CONSOLE_API_TOKEN already set — keeping it."
fi

# --- Register the service ----------------------------------------------------
if [ "$os" = "Linux" ] && command -v systemctl >/dev/null; then
  say "Registering the systemd user service '$SERVICE_NAME'..."
  detail "Unit:   ~/.config/systemd/user/$SERVICE_NAME.service"
  detail "Policy: Restart=on-failure every 5s; a missing LLM key (exit 78) stops instead of crash-looping"
  mkdir -p "$HOME/.config/systemd/user"
  cat > "$HOME/.config/systemd/user/$SERVICE_NAME.service" <<UNIT
[Unit]
Description=mirrim personal AI agent
After=network-online.target

[Service]
Type=notify
ExecStart=$APP_DIR/mirrim
WorkingDirectory=$DATA_DIR
# Startup counts as done only when the app reports ready, after migrations, a
# one-time VACUUM on an older database, and every connector's handshake. systemd's
# default of 90s has killed healthy upgrades mid-VACUUM; give a slow first start room.
TimeoutStartSec=300
Restart=on-failure
RestartSec=5
# A missing LLM key makes the app exit 78 (EX_CONFIG). Don't crash-loop on a
# configuration error — stop and wait for the operator to set it.
RestartPreventExitStatus=78

[Install]
WantedBy=default.target
UNIT
  systemctl --user daemon-reload
  systemctl --user enable "$SERVICE_NAME"
  # The install itself is complete here; a slow or failed first start must not abort the
  # script with a bare systemd error. Report what happened and where to look instead —
  # Restart=on-failure keeps trying in the background either way.
  if [ "$first_install" = 1 ]; then
    # Start it now: with no key it comes up in first-run SETUP MODE, serving a browser
    # setup page at http://localhost:$PORT so you can finish setup without editing files.
    if systemctl --user start "$SERVICE_NAME"; then
      say "Started the systemd user service '$SERVICE_NAME' in first-run setup mode."
    else
      service_start_failed
    fi
  elif systemctl --user restart "$SERVICE_NAME"; then
    say "Restarted the systemd user service '$SERVICE_NAME'."
  else
    service_start_failed
  fi
  say "Logs: journalctl --user -u $SERVICE_NAME -f   (and $DATA_DIR/logs/, or 'mirrim logs')"
  # A systemd *user* service only starts at boot when lingering is enabled for this
  # account — without it, mirrim stays down after a reboot until someone logs in.
  # Enabling your own linger is allowed without root on most distros; fall back to
  # an explicit instruction where policy forbids it.
  if command -v loginctl >/dev/null && [ "$(loginctl show-user "$USER" --property=Linger --value 2>/dev/null)" != "yes" ]; then
    loginctl enable-linger "$USER" 2>/dev/null || true
    if [ "$(loginctl show-user "$USER" --property=Linger --value 2>/dev/null)" = "yes" ]; then
      say "Enabled lingering: mirrim now starts at boot and keeps running after you log out."
    else
      say "IMPORTANT: could not enable lingering — after a reboot mirrim stays down until you log in."
      say "Fix it once with:  sudo loginctl enable-linger $USER"
    fi
  fi
elif [ "$os" = "Darwin" ]; then
  say "Registering the launchd agent '$LAUNCHD_LABEL'..."
  detail "Plist:  ~/Library/LaunchAgents/$LAUNCHD_LABEL.plist"
  detail "Policy: RunAtLoad + KeepAlive (restarts on any non-clean exit)"
  plist="$HOME/Library/LaunchAgents/$LAUNCHD_LABEL.plist"
  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LAUNCHD_LABEL</string>
  <key>ProgramArguments</key><array><string>$APP_DIR/mirrim</string></array>
  <key>WorkingDirectory</key><string>$DATA_DIR</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>StandardOutPath</key><string>$DATA_DIR/logs/launchd.out.log</string>
  <key>StandardErrorPath</key><string>$DATA_DIR/logs/launchd.err.log</string>
</dict>
</plist>
PLIST
  mkdir -p "$DATA_DIR/logs"
  if [ "$first_install" = 1 ]; then
    # Load it now: with no key it comes up in first-run SETUP MODE, serving a browser
    # setup page at http://localhost:$PORT so you can finish setup without editing files.
    launchctl bootstrap "gui/$(id -u)" "$plist" 2>/dev/null || launchctl load "$plist"
    say "Registered and started the launchd agent '$LAUNCHD_LABEL' in first-run setup mode."
  else
    launchctl bootstrap "gui/$(id -u)" "$plist" 2>/dev/null || launchctl load "$plist"
    say "Registered and started the launchd agent '$LAUNCHD_LABEL'."
  fi
  say "Logs: $DATA_DIR/logs/"
else
  say "No supported service manager found — run it manually:"
  say "  cd $DATA_DIR && $APP_DIR/mirrim"
fi

# --- Firewall (only relevant when exposing to the local network) --------------
if [ "$EXPOSE_LAN" = 1 ]; then
  if [ "$os" = "Darwin" ]; then
    say "macOS may ask to allow incoming connections for 'mirrim' — click Allow."
  elif command -v ufw >/dev/null 2>&1 || command -v firewall-cmd >/dev/null 2>&1; then
    say "This host runs a firewall — allow the console port for your LAN, e.g.:"
    if command -v ufw >/dev/null 2>&1; then
      detail "sudo ufw allow $PORT/tcp"
    else
      detail "sudo firewall-cmd --add-port=$PORT/tcp --permanent && sudo firewall-cmd --reload"
    fi
  fi
fi

# Headless/remote host? No local browser to open the setup page. Treat an SSH
# session, or a Linux box with no display server, as headless and lead with the
# terminal wizard instead of a localhost URL the operator can't reach.
# WSL has no DISPLAY but does have the Windows browser one hop away (wslview or
# cmd.exe), so it is a desktop, not a server.
is_wsl=0
if [ "$os" = "Linux" ] && grep -qi microsoft /proc/version 2>/dev/null; then is_wsl=1; fi
if [ -n "${SSH_CONNECTION:-}" ] || [ -n "${SSH_TTY:-}" ] \
   || { [ "$os" = "Linux" ] && [ "$is_wsl" = 0 ] && [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; }; then
  headless=1
else
  headless=0
fi

# Open the setup page ourselves once the service answers, so the user is not asked to
# copy a URL out of a terminal. Best effort: any failure just leaves the URL on screen.
open_browser() { # url
  if [ "$os" = "Darwin" ]; then
    open "$1" >/dev/null 2>&1 || return 1
  elif [ "$is_wsl" = 1 ]; then
    if command -v wslview >/dev/null 2>&1; then wslview "$1" >/dev/null 2>&1 || return 1
    elif command -v cmd.exe >/dev/null 2>&1; then cmd.exe /c start "" "$1" >/dev/null 2>&1 || return 1
    else return 1; fi
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$1" >/dev/null 2>&1 || return 1
  else
    return 1
  fi
}

wait_for_console() { # url, up to ~15 s
  for _ in $(seq 1 30); do
    if curl -fsS --max-time 1 "$1/health" >/dev/null 2>&1; then return 0; fi
    sleep 0.5
  done
  return 1
}

# The CLI name works only once BIN_DIR is on PATH; otherwise show the full path.
if [ "$on_path" = 1 ]; then cli="mirrim"; else cli="$BIN_DIR/mirrim"; fi

# Best-effort LAN address for the summary when exposing.
lan_ip=""
if [ "$EXPOSE_LAN" = 1 ]; then
  if [ "$os" = "Darwin" ]; then
    lan_ip=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)
  else
    lan_ip=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
  fi
fi

# --- Done ---------------------------------------------------------------------
echo
say "Install summary"
detail "Version:  $version"
detail "App:      $APP_DIR"
detail "Data:     $DATA_DIR  (.env, agent.db, logs - kept across upgrades)"
detail "CLI:      $BIN_DIR/mirrim -> $APP_DIR/mirrim   (and 'otto' as an alias for one more release)"
if [ "$EXPOSE_LAN" = 1 ]; then
  detail "Console:  http://localhost:$PORT  +  http://${lan_ip:-<this-machine>}:$PORT (local network)"
  if [ -n "$console_token" ]; then
    detail "Sign-in token for other devices (from CONSOLE_API_TOKEN in $DATA_DIR/.env):"
    detail "  $console_token"
  fi
else
  detail "Console:  http://localhost:$PORT  (localhost only)"
fi
detail "Uninstall: curl -fsSL https://raw.githubusercontent.com/$REPO/main/uninstall.sh | bash"
if [ "$on_path" = 0 ]; then
  say "$BIN_DIR is not on your PATH. Add it (then open a new shell):"
  echo "        echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.profile"
  echo "    Until then, run the CLI by full path: $BIN_DIR/mirrim"
fi
echo
if [ "$first_install" = 1 ] && [ "$headless" = 1 ]; then
  say "Installed on a headless/remote host. Finish setup in the terminal:"
  echo
  echo "        $cli setup"
  echo
  echo "    It prompts for a provider + key, writes $DATA_DIR/.env, and starts the agent."
  echo "    Prefer a browser? The setup page is loopback-only for safety — forward the port:"
  echo "        ssh -L $PORT:localhost:$PORT $USER@<this-host>"
  echo "    then open http://localhost:$PORT on your machine."
  if [ "$EXPOSE_LAN" = 1 ]; then
    echo "    The local-network URL starts working right after setup completes."
  fi
  if ! { [ "$os" = "Linux" ] && command -v systemctl >/dev/null; } && [ "$os" != "Darwin" ]; then
    echo
    echo "    No service manager was found — start it first with:"
    echo "        cd $DATA_DIR && $APP_DIR/mirrim"
  fi
  echo
elif [ "$first_install" = 1 ]; then
  opened=0
  if wait_for_console "http://localhost:$PORT" && open_browser "http://localhost:$PORT"; then opened=1; fi
  if [ "$opened" = 1 ]; then
    say "Installed. The setup page is opening in your browser:"
  else
    say "Installed. Finish setup in your browser:"
  fi
  echo
  echo "        http://localhost:$PORT"
  echo
  echo "    Pick a provider and paste your key — it's saved to"
  echo "        $DATA_DIR/.env"
  echo "    and the agent restarts into normal mode automatically."
  if [ "$EXPOSE_LAN" = 1 ]; then
    echo "    Note: for safety, first-run setup only answers on THIS machine (localhost)."
    echo "    The local-network URL starts working right after setup completes."
  fi
  echo "    Prefer the terminal? Run:  $cli setup"
  if ! { [ "$os" = "Linux" ] && command -v systemctl >/dev/null; } && [ "$os" != "Darwin" ]; then
    echo
    echo "    No service manager was found — start it first with:"
    echo "        cd $DATA_DIR && $APP_DIR/mirrim"
  fi
  echo
else
  say "Upgraded to $version. Your data in $DATA_DIR was kept."
  say "Open http://localhost:$PORT"
fi
