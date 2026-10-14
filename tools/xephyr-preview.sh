#!/usr/bin/env bash
# macify: run a complete second GNOME session inside an Xephyr window on the current X11 display, using a
# private copy of your settings; open a few apps; take screenshots; exit. Your real session is not touched.
# usage: tools/xephyr-preview.sh OUTDIR [WxH] [:display]
set -u
OUT="${1:?outdir}"; SIZE="${2:-2560x1600}"; XN="${3:-:7}"
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
detect_env; ensure_session_bus
[ -n "${DISPLAY:-}" ] || die "needs an X11 host session"
have Xephyr || as_root apt-get install -y -q xserver-xephyr >/dev/null
have import || as_root apt-get install -y -q imagemagick >/dev/null
mkdir -p "$OUT"
PH="$MACIFY_CACHE/preview-home"; rm -rf "$PH"; mkdir -p "$PH/.config/dconf" "$PH/.config/autostart"
for f in "$HOME"/.config/*; do b="$(basename "$f")"; case "$b" in dconf|autostart) continue;; esac; ln -s "$f" "$PH/.config/$b"; done
dconf dump / > "$PH/current.ini"
XDG_CONFIG_HOME="$PH/.config" dbus-run-session -- bash -c 'dconf load / < "$1"; for u in $2; do cur="$(gsettings get org.gnome.shell enabled-extensions)"; gsettings set org.gnome.shell enabled-extensions "$(printf "%s" "$cur" | sed "s/'"'"'$u'"'"'//; s/, ,/,/; s/\[, /[/; s/, \]/]/")"; done; sleep 1' _ "$PH/current.ini" "${MACIFY_PREVIEW_DISABLE:-}" 2>/dev/null
setsid Xephyr "$XN" -screen "$SIZE" -ac -br -noreset -title "macify preview" >"$OUT/xephyr.log" 2>&1 &
XPID=$!; sleep 3
kill -0 "$XPID" 2>/dev/null || { cat "$OUT/xephyr.log"; die "Xephyr failed to start on $XN"; }
( export DISPLAY="$XN" XDG_CONFIG_HOME="$PH/.config" XDG_SESSION_TYPE=x11 XDG_CURRENT_DESKTOP=ubuntu:GNOME GNOME_SHELL_SESSION_MODE=ubuntu DESKTOP_SESSION=ubuntu GDMSESSION=ubuntu
  unset XAUTHORITY WAYLAND_DISPLAY XDG_SESSION_ID
  setsid dbus-run-session -- gnome-session --builtin --disable-acceleration-check --session=ubuntu >"$OUT/session.log" 2>&1 &
  echo $! > "$OUT/session.pid" )
SPID="$(cat "$OUT/session.pid")"
NPID=""
for _ in $(seq 1 90); do
  sleep 1
  for p in $(pgrep -u "$(id -u)" -x gnome-shell); do
    d="$(tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null | sed -n 's/^DISPLAY=//p')"; [ "$d" = "$XN" ] && NPID="$p"
  done
  [ -n "$NPID" ] && break
done
[ -n "$NPID" ] || { tail -20 "$OUT/session.log"; pkill -s "$SPID"; kill "$XPID"; die "no gnome-shell came up on $XN"; }
NBUS="$(tr '\0' '\n' < "/proc/$NPID/environ" | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p')"
log "preview shell pid=$NPID on $XN; waiting for it to settle"
sleep 20
APP=(env DISPLAY="$XN" DBUS_SESSION_BUS_ADDRESS="$NBUS" XDG_CONFIG_HOME="$PH/.config" XDG_SESSION_TYPE=x11 XDG_CURRENT_DESKTOP=ubuntu:GNOME)
shot()   { import -display "$XN" -window root "$OUT/$1.png" 2>/dev/null && log "shot $1.png" || warn "shot $1 failed"; }
jseval() { DBUS_SESSION_BUS_ADDRESS="$NBUS" timeout 15 gdbus call --session --dest org.gnome.Shell --object-path /org/gnome/Shell --method org.gnome.Shell.Eval "$1" 2>&1; }
shot 01-desktop
"${APP[@]}" nautilus --new-window "$HOME" >/dev/null 2>&1 & A1=$!; sleep 6
"${APP[@]}" gnome-terminal --geometry=96x26 -- bash -c 'uname -a; echo; ls -la ~ | head -14; exec bash' >/dev/null 2>&1 & A2=$!; sleep 7
shot 02-apps
jseval 'Main.overview.show()' >/dev/null; sleep 3; shot 03-overview; jseval 'Main.overview.hide()' >/dev/null; sleep 1.5
jseval 'Main.panel.statusArea.menuButton.menu.open()' >/dev/null; sleep 1.5; shot 04-logo-menu; jseval 'Main.panel.statusArea.menuButton.menu.close()' >/dev/null
jseval 'Main.panel.statusArea.aggregateMenu.menu.open()' >/dev/null; sleep 1.5; shot 05-status-menu; jseval 'Main.panel.statusArea.aggregateMenu.menu.close()' >/dev/null
jseval 'Main.overview.show(); Main.overview.viewSelector.showApps()' >/dev/null; sleep 3; shot 06-launchpad; jseval 'Main.overview.hide()' >/dev/null
jseval '(function(){ const St = imports.gi.St; const Clutter = imports.gi.Clutter; let t = St.ThemeContext.get_for_stage(global.stage).get_theme(); let n = Main.panel.get_theme_node(); let c = n.get_background_color(); let fg = n.get_foreground_color(); return JSON.stringify({mode: Main.sessionMode.currentMode, def: t.default_stylesheet ? t.default_stylesheet.get_uri() : null, app: t.application_stylesheet ? t.application_stylesheet.get_path() : null, panel_style: Main.panel.get_style(), panel_classes: Main.panel.get_style_class_name(), panel_bg: [c.red,c.green,c.blue,c.alpha].join(","), panel_fg: [fg.red,fg.green,fg.blue,fg.alpha].join(","), ext: Array.from(Main.extensionManager._extensions.values()).filter(e => e.state != 6).map(e => e.uuid.split("@")[0] + ":" + e.state).join(" ")}); })()' > "$OUT/state.txt"
grep -E "JS ERROR|had error" "$OUT/session.log" | head -30 > "$OUT/errors.txt" || true
kill "$A1" "$A2" 2>/dev/null; pkill -s "$SPID" 2>/dev/null; sleep 2; kill -9 "$NPID" 2>/dev/null; pkill -9 -s "$SPID" 2>/dev/null; kill "$XPID" 2>/dev/null
log "done: $(ls "$OUT"/*.png 2>/dev/null | wc -l) screenshots in $OUT; JS errors: $(wc -l < "$OUT/errors.txt")"
