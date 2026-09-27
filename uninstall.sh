#!/usr/bin/env bash
# mirrim uninstaller (Linux + macOS): stops and removes the managed service,
# the PATH symlink, and the installed binary. Your data (.env, agent.db) is KEPT
# by default — pass --purge to delete the data directory too.
#
#   curl -fsSL https://raw.githubusercontent.com/dev-frz/mirrim-releases/main/uninstall.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/dev-frz/mirrim-releases/main/uninstall.sh | bash -s -- --purge
#
# Honors MIRRIM_HOME (same as the installer; OTTO_HOME still works) to locate a
# non-default install. Pre-rename otto and self-assist artifacts are removed too.
set -euo pipefail

DEFAULT_ROOT="$HOME/.local/share/mirrim"
# A pre-rename install that was never upgraded still lives at the otto root.
[ -d "$DEFAULT_ROOT" ] || [ ! -d "$HOME/.local/share/otto" ] || DEFAULT_ROOT="$HOME/.local/share/otto"
ROOT="${MIRRIM_HOME:-${OTTO_HOME:-${SELF_ASSIST_HOME:-$DEFAULT_ROOT}}}"
APP_DIR="$ROOT/app"
DATA_DIR="$ROOT/data"
BIN_DIR="$HOME/.local/bin"
SERVICE_NAME="mirrim"
LAUNCHD_LABEL="com.mirrim.agent"
OTTO_SERVICE_NAME="otto"
OTTO_LAUNCHD_LABEL="com.ottoagent.otto"
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

# --- Remove the PATH symlinks (only if they point into this install) ---------
for name in mirrim otto; do
  link="$BIN_DIR/$name"
  if [ -L "$link" ]; then
    target=$(readlink "$link" 2>/dev/null || true)
    case "$target" in
      "$APP_DIR"/*) rm -f "$link"; say "Removed the CLI symlink $link." ;;
      *) warn "Left $link in place (points elsewhere: ${target:-unknown})." ;;
    esac
  fi
done

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

# --- Pre-rename otto artifacts (otto → mirrim, 2026-08) -----------------------
if [ "$os" = "Linux" ] && command -v systemctl >/dev/null; then
  systemctl --user stop "$OTTO_SERVICE_NAME" 2>/dev/null || true
  systemctl --user disable "$OTTO_SERVICE_NAME" 2>/dev/null || true
  if [ -f "$HOME/.config/systemd/user/$OTTO_SERVICE_NAME.service" ]; then
    rm -f "$HOME/.config/systemd/user/$OTTO_SERVICE_NAME.service"
    systemctl --user daemon-reload 2>/dev/null || true
    say "Removed the pre-rename systemd user service '$OTTO_SERVICE_NAME'."
  fi
elif [ "$os" = "Darwin" ]; then
  otto_plist="$HOME/Library/LaunchAgents/$OTTO_LAUNCHD_LABEL.plist"
  launchctl bootout "gui/$(id -u)/$OTTO_LAUNCHD_LABEL" 2>/dev/null || true
  if [ -f "$otto_plist" ]; then
    rm -f "$otto_plist"
    say "Removed the pre-rename launchd agent '$OTTO_LAUNCHD_LABEL'."
  fi
fi
OTTO_ROOT="$HOME/.local/share/otto"
if [ "$ROOT" != "$OTTO_ROOT" ] && [ -d "$OTTO_ROOT" ]; then
  rm -rf "$OTTO_ROOT/app"
  if [ "$PURGE" = 1 ]; then
    rm -rf "$OTTO_ROOT"
    say "Purged the pre-rename data directory $OTTO_ROOT."
  else
    rmdir "$OTTO_ROOT" 2>/dev/null || say "Kept pre-rename data in $OTTO_ROOT (remove with --purge)."
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
say "mirrim uninstalled."
for name in mirrim otto; do
  if command -v "$name" >/dev/null 2>&1; then
    warn "A '$name' command is still resolvable on your PATH — open a new shell, or check for another copy."
  fi
done
