#!/usr/bin/env bash
# macify: opt-in extras (not installed unless asked): Spotlight-like launcher, trackpad gestures, Mac keyboard shortcuts
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

_github_latest_deb() {   # repo pattern -> url of a .deb asset in the latest release
  curl -fsSL --max-time 30 "https://api.github.com/repos/$1/releases/latest" 2>/dev/null \
    | python3 -I -c 'import sys,json,re; pat=sys.argv[1]; a=[x["browser_download_url"] for x in json.load(sys.stdin).get("assets",[]) if re.search(pat, x["name"])]; print(a[0] if a else "")' "$2"
}

install_launcher() {   # Ulauncher = Spotlight. Installed from its GitHub release .deb (no PPA).
  [ "$MACIFY_DRY_RUN" = 1 ] && { log "(dry) Ulauncher .deb + autostart, Super+Space -> Ulauncher, overview -> Super+S"; return 0; }
  if ! have ulauncher; then
    local url deb="$MACIFY_CACHE/ulauncher.deb"
    url="$(_github_latest_deb Ulauncher/Ulauncher '_all\.deb$')"
    [ -n "$url" ] || { warn "could not locate the Ulauncher .deb; skipping launcher"; return 1; }
    curl -fsSL --max-time 300 -o "$deb" "$url" || { warn "Ulauncher download failed"; return 1; }
    as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -q "$deb" >/dev/null || { warn "Ulauncher install failed"; return 1; }
  fi
  mkdir -p "$HOME/.config/ulauncher" "$HOME/.config/autostart"
  python3 -I - "$HOME/.config/ulauncher/settings.json" "$MACIFY_VARIANT" <<'PY'
import json, sys, os
p, variant = sys.argv[1], sys.argv[2]
s = {}
if os.path.exists(p):
    try: s = json.load(open(p))
    except Exception: s = {}
s.update({"hotkey-show-app": "<Super>space", "show-indicator-icon": False, "theme-name": "dark" if variant == "dark" else "light",
          "hotkey_show_app": "<Super>space", "show_indicator_icon": False})
json.dump(s, open(p, "w"), indent=2)
PY
  cat > "$HOME/.config/autostart/ulauncher.desktop" <<'DESK'
[Desktop Entry]
Type=Application
Name=Ulauncher
Exec=ulauncher --hide-window
X-GNOME-Autostart-enabled=true
DESK
  # Cmd+Space belongs to the launcher now; GNOME search moves to Super+S
  gset org.gnome.shell.keybindings toggle-overview "['<Super>s']"
  pgrep -x ulauncher >/dev/null || (setsid ulauncher --hide-window >/dev/null 2>&1 &)
  ok "Ulauncher installed: press Super+Space (set the hotkey in its preferences if it did not take)"
}

install_gestures() {   # Touchégg daemon + X11 Gestures extension = 3/4-finger macOS gestures on X11
  [ "$MACIFY_DRY_RUN" = 1 ] && { log "(dry) Touchégg .deb + service, X11 Gestures extension, 3/4-finger gesture config"; return 0; }
  if ! have touchegg; then
    local url deb="$MACIFY_CACHE/touchegg.deb" v done=0
    # newest release first, then older ones whose .deb still installs on older glib (20.04 needs <= 2.0.16)
    for url in "$(_github_latest_deb JoseExposito/touchegg '_amd64\.deb$')" \
               https://github.com/JoseExposito/touchegg/releases/download/2.0.17/touchegg_2.0.17_amd64.deb \
               https://github.com/JoseExposito/touchegg/releases/download/2.0.16/touchegg_2.0.16_amd64.deb; do
      [ -n "$url" ] || continue
      curl -fsSL --max-time 300 -o "$deb" "$url" || continue
      if as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -q "$deb" >/dev/null 2>&1; then done=1; ok "Touchégg installed from $(basename "$url")"; break; fi
    done
    if [ "$done" = 0 ]; then
      log "no prebuilt Touchégg fits this release; building from source"
      as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -q build-essential cmake libudev-dev libinput-dev libpugixml-dev libcairo2-dev libx11-dev libxtst-dev libxrandr-dev libxi-dev libglib2.0-dev libgtk-3-dev >/dev/null 2>&1
      rm -rf "$MACIFY_CACHE/src/touchegg"
      git clone -q --depth 1 --branch 2.0.17 https://github.com/JoseExposito/touchegg.git "$MACIFY_CACHE/src/touchegg" \
        && mkdir -p "$MACIFY_CACHE/src/touchegg/build" && (cd "$MACIFY_CACHE/src/touchegg/build" && cmake -DCMAKE_BUILD_TYPE=Release .. >/dev/null && make -j"$(nproc)" >/dev/null && as_root make install >/dev/null) \
        && ok "Touchégg built and installed" || { warn "Touchégg build failed; skipping gestures"; return 1; }
    fi
  fi
  as_root systemctl daemon-reload >/dev/null 2>&1 || true
  as_root systemctl enable --now touchegg.service >/dev/null 2>&1 || warn "could not start touchegg.service"
  if [ "$SESSION_TYPE" = x11 ]; then
    . "$MACIFY_DIR/lib/extensions.sh"
    ext_install x11gestures@joseexposito.github.io && ext_enable x11gestures@joseexposito.github.io
    ok "gestures: 3-finger swipe up = Mission Control, 3-finger left/right = switch Spaces, pinch = Launchpad"
  else
    ok "GNOME on Wayland already has native 3-finger gestures; Touchégg installed for X11 sessions"
  fi
}

install_snap_icons() {   # snap apps are confined: they can use WhiteSur icons via a theme snap, their GTK theme stays bundled
  have snap || return 0
  [ "$MACIFY_DRY_RUN" = 1 ] && { log "(dry) snap icon theme"; return 0; }
  if ! snap list icon-theme-whitesur >/dev/null 2>&1; then
    as_root snap install icon-theme-whitesur --edge >/dev/null 2>&1 || { log "icon-theme-whitesur snap not installable here; snap apps keep their icons"; return 0; }
  fi
  local s n=0
  for s in $(snap list 2>/dev/null | awk 'NR>1 && $1 !~ /^(core|snapd|gtk-common-themes|icon-theme-|gnome-|kf6-|mesa-|bare)/ {print $1}'); do
    if snap connections "$s" 2>/dev/null | grep -q '^content\[icon-themes\]'; then
      as_root snap connect "$s:icon-themes" icon-theme-whitesur:icon-themes >/dev/null 2>&1 && n=$((n+1))
    fi
  done
  ok "snap apps using WhiteSur icons: $n (no WhiteSur GTK theme snap exists, so their widgets keep the bundled look)"
}

remove_snap_icons() {
  have snap || return 0
  snap list icon-theme-whitesur >/dev/null 2>&1 || return 0
  local s; for s in $(snap connections icon-theme-whitesur 2>/dev/null | awk '/icon-themes/ && $2 !~ /^-/ {print $2}' | cut -d: -f1 | sort -u); do
    as_root snap disconnect "$s:icon-themes" >/dev/null 2>&1; as_root snap connect "$s:icon-themes" gtk-common-themes:icon-themes >/dev/null 2>&1
  done
  as_root snap remove icon-theme-whitesur >/dev/null 2>&1 || true
}

TOSHY_DIR="${MACIFY_TOSHY_DIR:-$HOME/.config/toshy}"

_py_ok() {   # interpreter usable for Toshy's venv: 3.10-3.12 with venv + tkinter (the versions its keymapper and GUI are built for)
  [ -x "$1" ] || return 1
  "$1" -c 'import sys, venv, tkinter; sys.exit(0 if (3, 10) <= sys.version_info[:2] <= (3, 12) else 1)' >/dev/null 2>&1
}

fetch_standalone_python() {   # CPython 3.11 from python-build-standalone (astral-sh) into the macify cache: ~45 MB, no PPA, no system change
  local arch dir url tgz
  case "$(uname -m)" in x86_64) arch=x86_64 ;; aarch64) arch=aarch64 ;; *) warn "no standalone Python build for $(uname -m)"; return 1 ;; esac
  dir="$MACIFY_CACHE/python311"
  if _py_ok "$dir/bin/python3.11"; then echo "$dir/bin/python3.11"; return 0; fi
  url="$(curl -fsSL --max-time 30 https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest 2>/dev/null \
    | python3 -I -c 'import sys,json,re; pat=sys.argv[1]; a=[x["browser_download_url"] for x in json.load(sys.stdin).get("assets",[]) if re.search(pat, x["name"])]; print(a[0] if a else "")' \
      "^cpython-3\.11\.[0-9]+\+[0-9]+-${arch}-unknown-linux-gnu-install_only\.tar\.gz$")"
  [ -n "$url" ] || { warn "could not locate a standalone CPython 3.11 build on GitHub"; return 1; }
  log "downloading a standalone Python 3.11 for Toshy: $(basename "$url")"
  tgz="$(mktemp)"
  curl -fsSL --max-time 900 -o "$tgz" "$url" || { rm -f "$tgz"; warn "Python download failed"; return 1; }
  rm -rf "$dir" "$dir.tmp"; mkdir -p "$dir.tmp"
  tar -xzf "$tgz" -C "$dir.tmp" && mv "$dir.tmp/python" "$dir"; rm -rf "$tgz" "$dir.tmp"
  _py_ok "$dir/bin/python3.11" && { echo "$dir/bin/python3.11"; return 0; }
  warn "the standalone Python does not run here"; return 1
}

find_toshy_python() {   # newest usable interpreter: $MACIFY_PYTHON, python3.12/3.11/3.10 on PATH, uv-managed builds, else a standalone build
  local v p
  if [ -n "${MACIFY_PYTHON:-}" ]; then
    _py_ok "$MACIFY_PYTHON" && { echo "$MACIFY_PYTHON"; return 0; }
    warn "MACIFY_PYTHON=$MACIFY_PYTHON is not a usable Python 3.10-3.12 (needs venv + tkinter)"
  fi
  for v in 3.12 3.11 3.10; do
    p="$(command -v "python$v" 2>/dev/null)" && _py_ok "$p" && { echo "$p"; return 0; }
    for p in "$HOME/.local/share/uv/python/cpython-$v."*"/bin/python$v"; do _py_ok "$p" && { echo "$p"; return 0; }; done
  done
  fetch_standalone_python
}

rebuild_toshy_venv() {   # the steps setup_toshy.py runs (venv, pip/wheel/setuptools/pillow, its package list, vendored keymapper) on interpreter $1
  local py="$1" venv="$TOSHY_DIR/.venv" src="$MACIFY_CACHE/src/toshy" vp vpip cons rc
  local pkgs=(dbus-python lockfile psutil pygobject sv_ttk systemd-python tk watchdog "xkbcommon<1.1" anyascii appdirs evdev hyprpy i3ipc inotify-simple ordered-set "python-xlib==0.31" pywayland six)
  [ -f "$src/vendors/xwaykeyz-main/pyproject.toml" ] || { warn "Toshy sources missing in $src"; return 1; }
  if have apt-get; then   # headers the pip builds need (Toshy's own installer covers most; wayland-protocols is new for a non-system Python)
    as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -q wayland-protocols libgirepository1.0-dev libcairo2-dev libdbus-1-dev \
      libsystemd-dev libxkbcommon-dev build-essential pkg-config >/dev/null 2>&1 || warn "could not install all build headers; continuing"
  fi
  [ "${MACIFY_TOSHY_NO_SERVICES:-0}" = 1 ] || systemctl --user stop toshy-config.service toshy-session-monitor.service >/dev/null 2>&1 || true
  if [ -d "$venv" ]; then rm -rf "$venv.macify-prev"; mv "$venv" "$venv.macify-prev"; fi
  "$py" -m venv "$venv" || { warn "could not create Toshy's venv with $py"; return 1; }   # symlinked (not --copies) so a standalone build finds its own Tcl/Tk
  vp="$venv/bin/python"; vpip="$venv/bin/pip"; cons="$(mktemp)"; printf 'pygobject<=3.50.0\n' > "$cons"   # PyGObject 3.51+ needs girepository-2.0
  (
    unset PYTHONPATH; export PIP_CONSTRAINT="$cons" PIP_DISABLE_PIP_VERSION_CHECK=1
    "$vp" -m pip install -q --upgrade pip && "$vpip" install -q --upgrade wheel setuptools pillow || exit 1
    if ! "$vpip" install -q --upgrade "${pkgs[@]}"; then
      printf 'pygobject==3.48.2\n' > "$cons"; "$vpip" install -q --upgrade "${pkgs[@]}" || exit 1   # older releases: last PyGObject that builds on GLib 2.64
    fi
    "$vpip" install -q --upgrade "$src/vendors/xwaykeyz-main"
  ) > "$MACIFY_CACHE/toshy-venv.log" 2>&1; rc=$?
  rm -f "$cons"
  if [ $rc -ne 0 ] || ! "$vp" -c 'import gi, dbus, evdev, xwaykeyz, tkinter' >/dev/null 2>&1; then
    warn "Toshy venv rebuild failed (log: $MACIFY_CACHE/toshy-venv.log); restoring the previous one"
    rm -rf "$venv"; [ -d "$venv.macify-prev" ] && mv "$venv.macify-prev" "$venv"; return 1
  fi
  rm -rf "$venv.macify-prev"
  ok "Toshy now runs on Python $("$vp" -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])')"
  if [ "${MACIFY_TOSHY_NO_SERVICES:-0}" != 1 ]; then
    systemctl --user reset-failed toshy-config.service >/dev/null 2>&1
    systemctl --user start toshy-session-monitor.service toshy-config.service >/dev/null 2>&1 || warn "could not start Toshy's services; they start at your next login"
    pgrep -u "$USER" -f 'toshy_tray[.]py' >/dev/null 2>&1 || [ ! -x "$HOME/.local/bin/toshy-tray" ] || (nohup setsid "$HOME/.local/bin/toshy-tray" >/dev/null 2>&1 </dev/null &)
  fi
}

toshy_python_floor() {   # Toshy's keymapper (xwaykeyz 1.25) needs Python >= 3.10; Ubuntu 20.04's python3 is 3.8, so its venv must move to a newer one
  local vp="$TOSHY_DIR/.venv/bin/python" py
  [ -x "$vp" ] || return 0
  if "$vp" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' >/dev/null 2>&1 && "$vp" -c 'import xwaykeyz' >/dev/null 2>&1; then return 0; fi
  log "Toshy's venv uses Python $("$vp" -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null); the keymapper needs 3.10+"
  py="$(find_toshy_python)" || { warn "no Python 3.10-3.12 available for Toshy; Mac shortcuts stay off"; return 1; }
  [ "$MACIFY_DRY_RUN" = 1 ] && { log "(dry) rebuild Toshy's venv on $py"; return 0; }
  rebuild_toshy_venv "$py"
}

mac_keys() {   # Cmd-style shortcuts in every app via Toshy (per-app remapper running as your user, X11 + Wayland)
  [ -d "$MACIFY_CACHE/src/toshy/.git" ] || git clone -q --depth 1 https://github.com/RedBearAK/toshy.git "$MACIFY_CACHE/src/toshy" || { warn "could not fetch Toshy"; return 1; }
  cat <<'TXT'
[macify] Toshy gives Cmd+C/V/X/Z/A/W/T/Q... in every app (terminals keep Ctrl+C as interrupt, Cmd+C copies).
         It runs as your user, has a tray icon to pause or disable it, and "./setup_toshy.py uninstall" removes it.
         If shortcuts do not work right away, log out and back in once so your user picks up the "input" group.
TXT
  [ "$MACIFY_DRY_RUN" = 1 ] && { log "(dry) Toshy install"; return 0; }
  if [ -x "$TOSHY_DIR/.venv/bin/python" ]; then
    log "Toshy is already installed in $TOSHY_DIR"
  else
    # Toshy requires the tray-indicator extension to be listed as enabled (Ubuntu enables it implicitly)
    if [ -d "$SYS_EXT_DIR/ubuntu-appindicators@ubuntu.com" ]; then
      gsettings get org.gnome.shell enabled-extensions | grep -q ubuntu-appindicators || gnome-extensions enable ubuntu-appindicators@ubuntu.com >/dev/null 2>&1
    fi
    # Toshy checks the live extension state; on the lock screen GNOME reports every extension disabled
    if [ "$(loginctl show-session "$(loginctl list-sessions --no-legend 2>/dev/null | awk -v u="$USER" '$3==u && $0 ~ /seat/ {print $1; exit}')" -p LockedHint --value 2>/dev/null)" = yes ]; then
      warn "the desktop is locked; Toshy's install check needs an unlocked session. Unlock and run: $MACIFY_DIR/install.sh --mac-keys"; return 1
    fi
    # same flags Toshy's own bootstrap.sh passes after asking its two questions (system updated? admin rights?)
    if (cd "$MACIFY_CACHE/src/toshy" && ./setup_toshy.py install --skip-update-check --admin-capable yes < /dev/null); then
      ok "Toshy installed"
    else
      warn "Toshy's installer stopped (it may need an answer only a person can give); run it in a terminal: cd $MACIFY_CACHE/src/toshy && ./setup_toshy.py install"
      return 1
    fi
  fi
  toshy_python_floor
}
