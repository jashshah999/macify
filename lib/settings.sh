#!/usr/bin/env bash
# macify: apply macOS-like GNOME settings. Idempotent; skips keys this GNOME lacks.
# shellcheck source=common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

theme_names() {   # sets GTK_THEME SHELL_THEME ICON_THEME from MACIFY_VARIANT
  if [ "$MACIFY_VARIANT" = light ]; then
    GTK_THEME=WhiteSur-Light; SHELL_THEME=WhiteSur-Light; ICON_THEME=WhiteSur-light
  else
    GTK_THEME=WhiteSur-Dark;  SHELL_THEME=WhiteSur-Dark;  ICON_THEME=WhiteSur-dark
  fi
}

pick_wallpaper() {   # echo path of the best installed macOS-style wallpaper
  local v="$MACIFY_VARIANT" c
  for c in "/usr/share/backgrounds/Sonoma/Sonoma-$v.jpg" \
           "/usr/share/backgrounds/Ventura/Ventura-$v.jpg" \
           "/usr/share/backgrounds/Monterey/Monterey-$v.jpg" \
           "/usr/share/backgrounds/WhiteSur/WhiteSur.jpg" \
           "$HOME/.local/share/backgrounds/Sonoma-$v.jpg"; do
    [ -f "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

apply_look() {
  theme_names
  [ -d "$HOME/.themes/$GTK_THEME" ] || [ -d "/usr/share/themes/$GTK_THEME" ] || warn "GTK theme $GTK_THEME is not installed yet"
  gset org.gnome.desktop.interface gtk-theme "'$GTK_THEME'"
  gset org.gnome.desktop.interface icon-theme "'$ICON_THEME'"
  gset org.gnome.desktop.interface cursor-theme "'WhiteSur-cursors'"
  if [ "$MACIFY_VARIANT" = light ]; then
    gset org.gnome.desktop.interface color-scheme "'default'"
  else
    gset org.gnome.desktop.interface color-scheme "'prefer-dark'"
  fi
  # shell theme (read by the User Themes extension once enabled)
  dset /org/gnome/shell/extensions/user-theme/name "'$SHELL_THEME'"

  # Fonts: Inter is the closest open font to SF Pro; DejaVu Sans Mono is what Menlo was derived from.
  local ui=Inter mono="DejaVu Sans Mono"
  fc-list : family 2>/dev/null | grep -qx "Inter" || { warn "Inter font missing, keeping current UI font"; ui=""; }
  if [ -n "$ui" ]; then
    gset org.gnome.desktop.interface font-name "'$ui 11'"
    gset org.gnome.desktop.interface document-font-name "'$ui 11'"
    gset org.gnome.desktop.wm.preferences titlebar-font "'$ui Semi Bold 11'"
  fi
  gset org.gnome.desktop.interface monospace-font-name "'$mono 12'"
  # macOS-style text rendering: grayscale antialiasing, light hinting (3.x keys and 42+ keys)
  gset org.gnome.settings-daemon.plugins.xsettings antialiasing "'grayscale'"
  gset org.gnome.settings-daemon.plugins.xsettings hinting "'slight'"
  gset org.gnome.desktop.interface font-antialiasing "'grayscale'"
  gset org.gnome.desktop.interface font-hinting "'slight'"

  # Window controls on the left in macOS order; sheets attached to their parent; new windows centered
  gset org.gnome.desktop.wm.preferences button-layout "'close,minimize,maximize:'"
  gset org.gnome.desktop.wm.preferences action-double-click-titlebar "'toggle-maximize'"
  gset org.gnome.mutter center-new-windows true
  gset org.gnome.mutter attach-modal-dialogs true

  # Menu bar clock like macOS ("Tue Oct 14  9:41 PM"), no hot corner, animations on
  gset org.gnome.desktop.interface clock-format "'12h'"
  gset org.gnome.desktop.interface clock-show-weekday true
  gset org.gnome.desktop.interface clock-show-date true
  gset org.gnome.desktop.interface clock-show-seconds false
  gset org.gnome.desktop.interface enable-hot-corners false
  gset org.gnome.desktop.interface enable-animations true

  # Wallpaper + lock screen
  local wp; if wp="$(pick_wallpaper)"; then
    gset org.gnome.desktop.background picture-uri "'file://$wp'"
    gset org.gnome.desktop.background picture-uri-dark "'file://$wp'"
    gset org.gnome.desktop.background picture-options "'zoom'"
    gset org.gnome.desktop.screensaver picture-uri "'file://$wp'"
    gset org.gnome.desktop.screensaver picture-options "'zoom'"
  else
    warn "no macOS-style wallpaper found; keeping the current one"
  fi

  # Desktop: no Home/Trash icons (macOS keeps Trash in the dock)
  gset org.gnome.shell.extensions.desktop-icons show-home false
  gset org.gnome.shell.extensions.desktop-icons show-trash false
  gset org.gnome.shell.extensions.ding show-home false
  gset org.gnome.shell.extensions.ding show-trash false

  # Touchpad like a Mac trackpad (mouse scroll direction is left alone on purpose)
  gset org.gnome.desktop.peripherals.touchpad tap-to-click true
  gset org.gnome.desktop.peripherals.touchpad natural-scroll true
  gset org.gnome.desktop.peripherals.touchpad two-finger-scrolling-enabled true

  # Input defaults as on a Mac: natural scrolling (touchpad and mouse), tap to click, two-finger secondary click,
  # macOS key-repeat timing (375 ms delay, ~11 repeats/s), screenshots land on the Desktop
  gset org.gnome.desktop.peripherals.touchpad natural-scroll true
  gset org.gnome.desktop.peripherals.touchpad tap-to-click true
  gset org.gnome.desktop.peripherals.touchpad two-finger-scrolling-enabled true
  gset org.gnome.desktop.peripherals.mouse natural-scroll true
  gset org.gnome.desktop.peripherals.keyboard delay 375
  gset org.gnome.desktop.peripherals.keyboard repeat-interval 90
  mkdir -p "$HOME/Desktop"
  gset org.gnome.gnome-screenshot auto-save-directory "'file://$HOME/Desktop'"
  gset org.gnome.gnome-screenshot last-save-directory "'file://$HOME/Desktop'"
}

apply_keys() {
  # Cmd+Space -> search (GNOME overview search), freeing Super+Space from input-source switching
  gset org.gnome.desktop.wm.keybindings switch-input-source "['XF86Keyboard']"
  gset org.gnome.desktop.wm.keybindings switch-input-source-backward "['<Shift>XF86Keyboard']"
  if have ulauncher || [ "${DO_LAUNCHER:-0}" = 1 ]; then   # Ulauncher owns Super+Space; GNOME search moves to Super+S
    gset org.gnome.shell.keybindings toggle-overview "['<Super>s']"
  else
    gset org.gnome.shell.keybindings toggle-overview "['<Super>space']"
  fi
  # Cmd+Q closes the window (Alt+F4 still works); Cmd+H hides (GNOME default: Super+H minimizes)
  gset org.gnome.desktop.wm.keybindings close "['<Alt>F4', '<Super>q']"
  gset org.gnome.desktop.wm.keybindings minimize "['<Super>h']"
  # Cmd+Tab switches between apps (GNOME default already does)
  gset org.gnome.desktop.wm.keybindings switch-applications "['<Super>Tab', '<Alt>Tab']"
  gset org.gnome.desktop.wm.keybindings switch-applications-backward "['<Shift><Super>Tab', '<Shift><Alt>Tab']"
  # Cmd+Shift+3 / Cmd+Shift+4 screenshots (GNOME 3.x media-keys; GNOME 42+ screenshot UI), Cmd+D show desktop
  gset org.gnome.settings-daemon.plugins.media-keys screenshot "['Print', '<Shift><Super>3']"
  gset org.gnome.settings-daemon.plugins.media-keys area-screenshot "['<Shift>Print', '<Shift><Super>4']"
  gset org.gnome.shell.keybindings show-screenshot-ui "['Print', '<Shift><Super>4']"
  gset org.gnome.desktop.wm.keybindings show-desktop "['<Super>d']"
  # Cmd+, opens System Settings (custom media-keys binding)
  local base=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings
  dset "$base/macify-settings/name" "'System Settings'"
  dset "$base/macify-settings/command" "'gnome-control-center'"
  dset "$base/macify-settings/binding" "'<Super>comma'"
  local cur; cur="$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings 2>/dev/null)"
  if ! printf '%s' "$cur" | grep -q macify-settings; then
    if [ "$cur" = "@as []" ] || [ -z "$cur" ]; then cur="['$base/macify-settings/']"; else cur="${cur%]}, '$base/macify-settings/']"; fi
    gset org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$cur"
  fi
}

apply_favorites() {
  # Files first (Finder), Settings last (System Settings); keep whatever the user already pinned, drop Help.
  local cur new
  cur="$(gsettings get org.gnome.shell favorite-apps 2>/dev/null)"
  new="$(python3 -I - "$cur" <<'PY'
import ast, sys
cur = ast.literal_eval(sys.argv[1]) if sys.argv[1] else []
drop = {'org.gnome.Nautilus.desktop', 'gnome-control-center.desktop', 'yelp.desktop'}
out = ['org.gnome.Nautilus.desktop'] + [a for a in cur if a not in drop]
for extra in ('org.gnome.Terminal.desktop',):
    if extra not in out: out.append(extra)
out.append('gnome-control-center.desktop')
print(repr(out))
PY
)"
  # keep only entries whose .desktop file exists; a stale "foo.desktop" is mapped to the snap's "foo_*.desktop"
  local filtered="["; local first=1; local a snapid
  for a in $(printf '%s' "$new" | tr -d "[]'," ); do
    if ! desktop_file_exists "$a"; then
      local base="${a%.desktop}"; base="${base%%_*}"
      snapid="/var/lib/snapd/desktop/applications/${base}_${base}.desktop"
      [ -f "$snapid" ] || snapid="$(ls /var/lib/snapd/desktop/applications/"${base}"_*.desktop 2>/dev/null | head -1)"
      [ -n "$snapid" ] && a="$(basename "$snapid")" || continue
    fi
    [ $first = 1 ] || filtered+=", "; filtered+="'$a'"; first=0
  done
  filtered+="]"
  gset org.gnome.shell favorite-apps "$filtered"
}

apply_terminal() {
  have gnome-terminal || { log "gnome-terminal not installed, skipping terminal profile"; return 0; }
  local base=/org/gnome/terminal/legacy/profiles: uuid="" p n
  for p in $(dconf list "$base/" 2>/dev/null | grep '^:'); do
    n="$(dconf read "$base/${p}visible-name" 2>/dev/null)"
    [ "$n" = "'macOS'" ] && { uuid="${p#:}"; uuid="${uuid%/}"; }
  done
  [ -z "$uuid" ] && uuid="$(cat /proc/sys/kernel/random/uuid)"
  local P="$base/:$uuid"
  dset "$P/visible-name" "'macOS'"
  dset "$P/use-theme-colors" false
  if [ "$MACIFY_VARIANT" = light ]; then
    dset "$P/background-color" "'rgb(255,255,255)'"; dset "$P/foreground-color" "'rgb(0,0,0)'"
  else
    dset "$P/background-color" "'rgb(30,30,30)'";    dset "$P/foreground-color" "'rgb(255,255,255)'"
  fi
  # Terminal.app ANSI palette
  dset "$P/palette" "['rgb(0,0,0)', 'rgb(153,0,0)', 'rgb(0,166,0)', 'rgb(153,153,0)', 'rgb(0,0,178)', 'rgb(178,0,178)', 'rgb(0,166,178)', 'rgb(191,191,191)', 'rgb(102,102,102)', 'rgb(229,0,0)', 'rgb(0,217,0)', 'rgb(229,229,0)', 'rgb(0,0,255)', 'rgb(229,0,229)', 'rgb(0,229,229)', 'rgb(229,229,229)']"
  dset "$P/use-system-font" false
  dset "$P/font" "'DejaVu Sans Mono 12'"
  dset "$P/cursor-shape" "'block'"
  dset "$P/audible-bell" false
  dset "$P/default-size-columns" 80
  dset "$P/default-size-rows" 24
  dset "$P/use-transparent-background" true
  dset "$P/background-transparency-percent" 8
  # register + make default
  local list; list="$(gsettings get org.gnome.Terminal.ProfilesList list 2>/dev/null)"
  if ! printf '%s' "$list" | grep -q "$uuid"; then
    if [ "$list" = "@as []" ] || [ -z "$list" ]; then list="['$uuid']"; else list="${list%]}, '$uuid']"; fi
    gset org.gnome.Terminal.ProfilesList list "$list"
  fi
  gset org.gnome.Terminal.ProfilesList default "'$uuid'"
  gset org.gnome.Terminal.Legacy.Settings default-show-menubar false
  gset org.gnome.Terminal.Legacy.Settings headerbar "true"
  gset org.gnome.Terminal.Legacy.Settings theme-variant "'$MACIFY_VARIANT'"
}

apply_settings() {
  ensure_session_bus
  apply_look
  apply_keys
  apply_favorites
  apply_terminal
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then detect_env; apply_settings; fi
