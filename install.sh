#!/usr/bin/env bash
# self-assist installer (Linux + macOS): downloads the latest self-contained
# release (no .NET required), installs it per-user, and registers a managed
# 24/7 service (systemd --user on Linux, launchd LaunchAgent on macOS).
#
#   curl -fsSL https://raw.githubusercontent.com/ferozhussain/self-assist-releases/main/install.sh | bash
#
# This is the public release channel — no token is needed to install. You can
# optionally export GITHUB_TOKEN to avoid GitHub's unauthenticated API rate
# limit when looking up the latest release:
#
#   export GITHUB_TOKEN=ghp_...
#   curl -fsSL https://raw.githubusercontent.com/ferozhussain/self-assist-releases/main/install.sh | bash
#
# Re-running upgrades the binary in place and keeps your data (.env, agent.db).
# Pin a version with SELF_ASSIST_VERSION=v1.2.3.
set -euo pipefail

REPO="ferozhussain/self-assist-releases"
ROOT="${SELF_ASSIST_HOME:-$HOME/.local/share/self-assist}"
APP_DIR="$ROOT/app"
DATA_DIR="$ROOT/data"
SERVICE_NAME="self-assist"
TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# curl with the token attached when one is set (optional — only lifts the
# unauthenticated GitHub API rate limit on the release lookup below).
gh_curl() {
  if [ -n "$TOKEN" ]; then
    curl -fsSL -H "Authorization: Bearer $TOKEN" "$@"
  else
    curl -fsSL "$@"
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

version="${SELF_ASSIST_VERSION:-}"
if [ -z "$version" ]; then
  say "Looking up the latest release..."
  version=$(gh_curl "https://api.github.com/repos/$REPO/releases/latest" |
    grep -m1 '"tag_name"' | cut -d'"' -f4) || true
  if [ -z "$version" ]; then
    fail "could not determine the latest release. Are releases published yet? (Pin one with SELF_ASSIST_VERSION=vX.Y.Z, or check https://github.com/$REPO/releases)"
  fi
fi

asset="self-assist-$version-$rid.tar.gz"

# --- Download and install ----------------------------------------------------
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

say "Downloading $asset ..."
url="https://github.com/$REPO/releases/download/$version/$asset"
curl -fsSL -o "$tmp/$asset" "$url" ||
  fail "download failed: $url (is $asset attached to release $version?)"

# Stop a running service before replacing the binary (ignore if not installed).
if [ "$os" = "Linux" ] && command -v systemctl >/dev/null; then
  systemctl --user stop "$SERVICE_NAME" 2>/dev/null || true
elif [ "$os" = "Darwin" ]; then
  launchctl bootout "gui/$(id -u)/com.selfassist.agent" 2>/dev/null || true
fi

say "Installing to $APP_DIR ..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR" "$DATA_DIR"
tar -xzf "$tmp/$asset" -C "$APP_DIR"
chmod +x "$APP_DIR/self-assist"

# First install: seed the data directory with the .env template.
if [ ! -f "$DATA_DIR/.env" ]; then
  cp "$APP_DIR/.env.example" "$DATA_DIR/.env"
  first_install=1
else
  first_install=0
fi

# --- Register the service ----------------------------------------------------
if [ "$os" = "Linux" ] && command -v systemctl >/dev/null; then
  mkdir -p "$HOME/.config/systemd/user"
  cat > "$HOME/.config/systemd/user/$SERVICE_NAME.service" <<UNIT
[Unit]
Description=self-assist personal AI agent
After=network-online.target

[Service]
Type=notify
ExecStart=$APP_DIR/self-assist
WorkingDirectory=$DATA_DIR
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
UNIT
  systemctl --user daemon-reload
  systemctl --user enable --now "$SERVICE_NAME"
  say "Registered and started the systemd user service '$SERVICE_NAME'."
  say "Logs: journalctl --user -u $SERVICE_NAME -f   (and $DATA_DIR/logs/)"
  if command -v loginctl >/dev/null && [ "$(loginctl show-user "$USER" --property=Linger --value 2>/dev/null)" != "yes" ]; then
    say "Tip: 'loginctl enable-linger $USER' keeps it running after you log out."
  fi
elif [ "$os" = "Darwin" ]; then
  plist="$HOME/Library/LaunchAgents/com.selfassist.agent.plist"
  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.selfassist.agent</string>
  <key>ProgramArguments</key><array><string>$APP_DIR/self-assist</string></array>
  <key>WorkingDirectory</key><string>$DATA_DIR</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>StandardOutPath</key><string>$DATA_DIR/logs/launchd.out.log</string>
  <key>StandardErrorPath</key><string>$DATA_DIR/logs/launchd.err.log</string>
</dict>
</plist>
PLIST
  mkdir -p "$DATA_DIR/logs"
  launchctl bootstrap "gui/$(id -u)" "$plist" 2>/dev/null || launchctl load "$plist"
  say "Registered and started the launchd agent 'com.selfassist.agent'."
  say "Logs: $DATA_DIR/logs/"
else
  say "No supported service manager found — run it manually:"
  say "  cd $DATA_DIR && $APP_DIR/self-assist"
fi

# --- Done ---------------------------------------------------------------------
echo
if [ "$first_install" = 1 ]; then
  say "Installed. One step left:"
  echo "    1. Edit $DATA_DIR/.env  (set ANTHROPIC_API_KEY, or Llm__Provider=Local)"
  if [ "$os" = "Linux" ]; then
    echo "    2. systemctl --user restart $SERVICE_NAME"
  else
    echo "    2. launchctl kickstart -k gui/$(id -u)/com.selfassist.agent"
  fi
  echo "    3. Open http://localhost:5080"
else
  say "Upgraded to $version. Your data in $DATA_DIR was kept."
  say "Open http://localhost:5080"
fi
