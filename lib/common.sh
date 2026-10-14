#!/usr/bin/env bash
# macify: shared helpers (sourced by install.sh and the lib/*.sh modules)

MACIFY_DIR="${MACIFY_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
MACIFY_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/macify"
MACIFY_VARIANT="${MACIFY_VARIANT:-dark}"        # dark | light
MACIFY_DRY_RUN="${MACIFY_DRY_RUN:-0}"
EXT_DIR="$HOME/.local/share/gnome-shell/extensions"
SYS_EXT_DIR="/usr/share/gnome-shell/extensions"
NEED_SHELL_RESTART=0

log()  { printf '\033[1;34m[macify]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[macify]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[macify] warn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[macify] error:\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# sudo wrapper: passwordless if possible, otherwise prompts once on the terminal
as_root() {
  if [ "$(id -u)" = 0 ]; then "$@"; else sudo "$@"; fi
}

detect_env() {
  . /etc/os-release 2>/dev/null || true
  DISTRO_ID="${ID:-unknown}"; DISTRO_VER="${VERSION_ID:-unknown}"
  if have gnome-shell; then
    GS_VERSION_FULL="$(gnome-shell --version 2>/dev/null | awk '{print $3}')"
  else
    GS_VERSION_FULL=""
  fi
  GS_MAJOR="${GS_VERSION_FULL%%.*}"
  if [ -n "$GS_MAJOR" ] && [ "$GS_MAJOR" -ge 40 ] 2>/dev/null; then
    EGO_SHELL="$GS_MAJOR"                                  # e.g. 42, 46
  else
    EGO_SHELL="$(printf '%s' "$GS_VERSION_FULL" | cut -d. -f1,2)"   # e.g. 3.36
  fi
  SESSION_TYPE="${XDG_SESSION_TYPE:-}"
  if [ -z "$SESSION_TYPE" ] || [ "$SESSION_TYPE" = tty ]; then
    # running over SSH: look up the user's graphical session
    local sid
    for sid in $(loginctl list-sessions --no-legend 2>/dev/null | awk -v u="$USER" '$3==u {print $1}'); do
      local t; t="$(loginctl show-session "$sid" -p Type --value 2>/dev/null)"
      if [ "$t" = x11 ] || [ "$t" = wayland ]; then SESSION_TYPE="$t"; break; fi
    done
  fi
  SESSION_TYPE="${SESSION_TYPE:-unknown}"
  export GS_VERSION_FULL GS_MAJOR EGO_SHELL SESSION_TYPE DISTRO_ID DISTRO_VER
}

# Make gsettings/dconf/gnome-extensions reach the user's live session even over SSH.
ensure_session_bus() {
  local uid; uid="$(id -u)"
  if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && [ -S "/run/user/$uid/bus" ]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus"
  fi
  if [ -z "${DISPLAY:-}" ]; then
    local pid; pid="$(pgrep -u "$uid" -x gnome-shell | head -1)"
    if [ -n "$pid" ]; then
      local d x
      d="$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | sed -n 's/^DISPLAY=//p' | head -1)"
      x="$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | sed -n 's/^XAUTHORITY=//p' | head -1)"
      [ -n "$d" ] && export DISPLAY="$d"
      [ -n "$x" ] && export XAUTHORITY="$x"
    fi
  fi
}

# ---- gsettings / dconf helpers (skip keys that do not exist on this GNOME) ----
_schema_cache=""
has_schema() {
  [ -z "$_schema_cache" ] && _schema_cache="$(gsettings list-schemas 2>/dev/null; gsettings list-relocatable-schemas 2>/dev/null)"
  printf '%s\n' "$_schema_cache" | grep -qx "$1"
}
has_key() { has_schema "${1%%:*}" && gsettings list-keys "$1" 2>/dev/null | grep -qx "$2"; }
gset() {   # gset SCHEMA KEY VALUE
  if has_key "$1" "$2"; then
    if [ "$MACIFY_DRY_RUN" = 1 ]; then log "(dry) gsettings set $1 $2 $3"; return 0; fi
    if gsettings set "$1" "$2" "$3" 2>/dev/null; then log "set $1 $2 = $3"; else warn "could not set $1 $2 = $3"; fi
  else
    log "skip $1 $2 (not available on this GNOME)"
  fi
}
dset() {   # dset /dconf/path/key VALUE  (used for extension settings: no schema needed)
  if [ "$MACIFY_DRY_RUN" = 1 ]; then log "(dry) dconf write $1 $2"; return 0; fi
  if dconf write "$1" "$2" 2>/dev/null; then log "dconf $1 = $2"; else warn "dconf write failed: $1"; fi
}

desktop_file_exists() {
  local f="$1" d
  for d in "$HOME/.local/share/applications" /usr/share/applications /usr/local/share/applications /var/lib/snapd/desktop/applications /var/lib/flatpak/exports/share/applications; do
    [ -f "$d/$f" ] && return 0
  done
  return 1
}

# Restart GNOME Shell in place (X11 only; windows survive). On Wayland the user must log out/in.
restart_shell() {
  ensure_session_bus
  if [ "$SESSION_TYPE" = x11 ]; then
    log "restarting GNOME Shell in place (X11, windows are kept)"
    if [ "$GS_MAJOR" -ge 41 ] 2>/dev/null; then
      # Eval is restricted on 41+; use the Extensions D-Bus API trick: ask the shell to re-exec itself
      busctl --user call org.gnome.Shell /org/gnome/Shell org.gnome.Shell Eval s 'Meta.restart("Restarting…")' >/dev/null 2>&1 \
        || warn "could not restart the shell automatically; press Alt+F2, type r, Enter"
    else
      gdbus call --session --dest org.gnome.Shell --object-path /org/gnome/Shell --method org.gnome.Shell.Eval 'Meta.restart("Restarting…")' >/dev/null 2>&1 \
        || warn "could not restart the shell automatically; press Alt+F2, type r, Enter"
    fi
    sleep 6
  else
    warn "GNOME on Wayland cannot restart in place: log out and back in to load new extensions"
  fi
}
