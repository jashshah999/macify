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

mac_keys() {   # Cmd-style shortcuts in every app via Toshy (per-app remapper running as your user, X11 + Wayland)
  [ -d "$MACIFY_CACHE/src/toshy/.git" ] || git clone -q --depth 1 https://github.com/RedBearAK/toshy.git "$MACIFY_CACHE/src/toshy" || { warn "could not fetch Toshy"; return 1; }
  cat <<'TXT'
[macify] Toshy gives Cmd+C/V/X/Z/A/W/T/Q... in every app (terminals keep Ctrl+C as interrupt, Cmd+C copies).
         It runs as your user, has a tray icon to pause or disable it, and "./setup_toshy.py uninstall" removes it.
         Log out and back in once afterwards so your user picks up the "input" group it needs.
TXT
  [ "$MACIFY_DRY_RUN" = 1 ] && { log "(dry) Toshy install"; return 0; }
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
    ok "Toshy installed; Mac shortcuts are active after your next login"
  else
    warn "Toshy's installer stopped (it may need an answer only a person can give); run it in a terminal: cd $MACIFY_CACHE/src/toshy && ./setup_toshy.py install"
  fi
}
