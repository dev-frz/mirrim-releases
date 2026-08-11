#!/usr/bin/env bash
# otto uninstaller (Linux + macOS): stops and removes the managed service,
# the PATH symlink, and the installed binary. Your data (.env, agent.db) is KEPT
# by default — pass --purge to delete the data directory too.
#
#   curl -fsSL https://raw.githubusercontent.com/dev-frz/otto-releases/main/uninstall.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/dev-frz/otto-releases/main/uninstall.sh | bash -s -- --purge
#
# Honors OTTO_HOME (same as the installer) to locate a non-default install.
set -euo pipefail

ROOT="${OTTO_HOME:-${SELF_ASSIST_HOME:-$HOME/.local/share/otto}}"
APP_DIR="$ROOT/app"
DATA_DIR="$ROOT/data"
BIN_DIR="$HOME/.local/bin"
SERVICE_NAME="otto"
LAUNCHD_LABEL="com.ottoagent.otto"
PURGE=0
for arg in "$@"; do
  case "$arg" in
    --purge) PURGE=1 ;;
    *) printf 'unknown option: %s (supported: --purge)\n' "$arg" >&2; exit 2 ;;
  esac
done

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }

os=$(uname -s)

# --- Stop and remove the managed service ------------------------------------
if [ "$os" = "Linux" ] && command -v systemctl >/dev/null; then
  systemctl --user stop "$SERVICE_NAME" 2>/dev/null || true
  systemctl --user disable "$SERVICE_NAME" 2>/dev/null || true
  unit="$HOME/.config/systemd/user/$SERVICE_NAME.service"
  if [ -f "$unit" ]; then
    rm -f "$unit"
    systemctl --user daemon-reload 2>/dev/null || true
    say "Removed the systemd user service '$SERVICE_NAME'."
  fi
elif [ "$os" = "Darwin" ]; then
  plist="$HOME/Library/LaunchAgents/$LAUNCHD_LABEL.plist"
  launchctl bootout "gui/$(id -u)/$LAUNCHD_LABEL" 2>/dev/null \
    || launchctl unload "$plist" 2>/dev/null || true
  if [ -f "$plist" ]; then
    rm -f "$plist"
    say "Removed the launchd agent '$LAUNCHD_LABEL'."
  fi
fi

# --- Remove the PATH symlink (only if it points into this install) ----------
link="$BIN_DIR/otto"
if [ -L "$link" ]; then
  target=$(readlink "$link" 2>/dev/null || true)
  case "$target" in
    "$APP_DIR"/*) rm -f "$link"; say "Removed the CLI symlink $link." ;;
    *) warn "Left $link in place (points elsewhere: ${target:-unknown})." ;;
  esac
fi

# --- Remove the app directory (always) --------------------------------------
if [ -d "$APP_DIR" ]; then
  rm -rf "$APP_DIR"
  say "Removed the app directory $APP_DIR."
fi

# --- Data directory: keep unless --purge ------------------------------------
if [ "$PURGE" = 1 ]; then
  if [ -d "$DATA_DIR" ]; then
    rm -rf "$DATA_DIR"
    say "Purged the data directory $DATA_DIR (.env, agent.db, logs)."
  fi
  # Remove the now-empty root if nothing else lives there.
  rmdir "$ROOT" 2>/dev/null || true
else
  if [ -d "$DATA_DIR" ]; then
    say "Kept your data in $DATA_DIR (.env, agent.db). Delete it with: rm -rf \"$DATA_DIR\""
    say "Or re-run with --purge to remove everything."
  fi
fi

# --- Legacy self-assist artifacts (pre-rebrand) ------------------------------
# Clean up an old install too, so uninstalling after the rename leaves nothing behind.
if [ "$os" = "Linux" ] && command -v systemctl >/dev/null; then
  systemctl --user stop self-assist 2>/dev/null || true
  systemctl --user disable self-assist 2>/dev/null || true
  if [ -f "$HOME/.config/systemd/user/self-assist.service" ]; then
    rm -f "$HOME/.config/systemd/user/self-assist.service"
    systemctl --user daemon-reload 2>/dev/null || true
    say "Removed the legacy systemd user service 'self-assist'."
  fi
elif [ "$os" = "Darwin" ]; then
  old_plist="$HOME/Library/LaunchAgents/com.selfassist.agent.plist"
  launchctl bootout "gui/$(id -u)/com.selfassist.agent" 2>/dev/null || true
  if [ -f "$old_plist" ]; then
    rm -f "$old_plist"
    say "Removed the legacy launchd agent 'com.selfassist.agent'."
  fi
fi
rm -f "$BIN_DIR/self-assist"
OLD_ROOT="$HOME/.local/share/self-assist"
if [ -d "$OLD_ROOT" ]; then
  rm -rf "$OLD_ROOT/app"
  if [ "$PURGE" = 1 ]; then
    rm -rf "$OLD_ROOT"
    say "Purged the legacy data directory $OLD_ROOT."
  else
    rmdir "$OLD_ROOT" 2>/dev/null || say "Kept legacy data in $OLD_ROOT (remove with --purge)."
  fi
fi

echo
say "otto uninstalled."
if command -v otto >/dev/null 2>&1; then
  warn "A 'otto' command is still resolvable on your PATH — open a new shell, or check for another copy."
fi
