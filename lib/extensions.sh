#!/usr/bin/env bash
# macify: fetch GNOME Shell extensions matching the running shell version from extensions.gnome.org,
# install them per-user, enable them, and apply macOS-like settings for each.
# shellcheck source=common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

EGO=https://extensions.gnome.org

# Extensions we want, in enable order. Each is skipped gracefully when no build exists for this shell.
MACIFY_EXTENSIONS=(
  user-theme@gnome-shell-extensions.gcampax.github.com   # shell theme support (ships with gnome-shell-extensions)
  dash-to-dock@micxgx.gmail.com                           # the Dock
  logomenu@aryan_k                                        # Apple-menu style logo menu, top-left
  just-perfection-desktop@just-perfection                 # hide Activities, clock on the right, no hot corner
  unite@hardpixel.eu                                      # notifications top-right, monochrome tray, "Finder" label
  blur-my-shell@aunetx                                    # frosted-glass panel/dock/overview
  compiz-alike-magic-lamp-effect@hermes83.github.com      # genie minimize effect
)
# Fallbacks used when the primary extension has no build for this shell version.
declare -A MACIFY_EXT_FALLBACK=(
  [unite@hardpixel.eu]=notification-banner-reloaded@marcinjakubowski.github.com
)

ext_metadata_path() {
  local u="$1"
  if   [ -f "$EXT_DIR/$u/metadata.json" ];     then printf '%s' "$EXT_DIR/$u/metadata.json"
  elif [ -f "$SYS_EXT_DIR/$u/metadata.json" ]; then printf '%s' "$SYS_EXT_DIR/$u/metadata.json"
  else return 1; fi
}

ext_supported_locally() {   # installed AND declares support for this shell version
  local m; m="$(ext_metadata_path "$1")" || return 1
  python3 -I - "$m" "$EGO_SHELL" "$GS_VERSION_FULL" <<'PY'
import json, sys
m = json.load(open(sys.argv[1])); sv = [str(x) for x in m.get("shell-version", [])]
ego, full = sys.argv[2], sys.argv[3]
ok = ego in sv or full in sv or full.rsplit('.', 1)[0] in sv
sys.exit(0 if ok else 1)
PY
}

ego_download() {   # uuid -> prints zip path, or fails
  local u="$1" info url out
  mkdir -p "$MACIFY_CACHE/ext"
  info="$(curl -fsSL --max-time 30 "$EGO/extension-info/?uuid=$u&shell_version=$EGO_SHELL" 2>/dev/null)" || return 1
  url="$(printf '%s' "$info" | python3 -I -c 'import sys,json; print(json.load(sys.stdin).get("download_url",""))' 2>/dev/null)"
  [ -n "$url" ] || return 1
  out="$MACIFY_CACHE/ext/$u.gnome-$EGO_SHELL.zip"
  curl -fsSL --max-time 120 -o "$out" "$EGO$url" || return 1
  printf '%s' "$out"
}

ext_install() {   # returns 0 if the extension is usable on this machine
  local u="$1" zip
  if ext_supported_locally "$u"; then log "extension present: $u"; return 0; fi
  [ "$MACIFY_DRY_RUN" = 1 ] && { log "(dry) would fetch $u for GNOME $EGO_SHELL"; return 0; }
  if zip="$(ego_download "$u")"; then
    if gnome-extensions install --force "$zip" >/dev/null 2>&1; then
      ok "installed $u ($(basename "$zip"))"; NEED_SHELL_RESTART=1; return 0
    fi
    warn "gnome-extensions could not install $u"; return 1
  fi
  warn "no build of $u for GNOME $EGO_SHELL on extensions.gnome.org, skipping"; return 1
}

ext_state() { gnome-extensions info "$1" 2>/dev/null | awk -F': ' '/^ *State/ {print $2}'; }

ext_enable() {
  local u="$1"
  [ "$MACIFY_DRY_RUN" = 1 ] && { log "(dry) enable $u"; return 0; }
  [ "${MACIFY_PREVIEW:-0}" = 1 ] || gnome-extensions enable "$u" >/dev/null 2>&1 || true
  # make sure it is in the enabled list even if the running shell has not scanned it yet
  local cur; cur="$(gsettings get org.gnome.shell enabled-extensions)"
  if ! printf '%s' "$cur" | grep -q "'$u'"; then
    if [ "$cur" = "@as []" ]; then cur="['$u']"; else cur="${cur%]}, '$u']"; fi
    gsettings set org.gnome.shell enabled-extensions "$cur"
  fi
  # and not in the disabled list
  local dis; dis="$(gsettings get org.gnome.shell disabled-extensions 2>/dev/null)"
  if printf '%s' "$dis" | grep -q "'$u'"; then
    dis="$(printf '%s' "$dis" | sed "s/'$u'//; s/, ,/,/; s/\[, /[/; s/, \]/]/")"; gsettings set org.gnome.shell disabled-extensions "$dis"
  fi
  [ "${MACIFY_PREVIEW:-0}" = 1 ] && { log "preview: enabled $u"; return 0; }
  local st; st="$(ext_state "$u")"
  case "$st" in ENABLED|ACTIVE) ok "enabled $u";; *) log "enabled $u (state now: ${st:-not loaded yet}; shell restart needed)"; NEED_SHELL_RESTART=1;; esac
}

ext_disable() {
  local u="$1"
  [ "$MACIFY_DRY_RUN" = 1 ] && { log "(dry) disable $u"; return 0; }
  ext_metadata_path "$u" >/dev/null 2>&1 || return 0
  [ "${MACIFY_PREVIEW:-0}" = 1 ] || gnome-extensions disable "$u" >/dev/null 2>&1 || true
  local dis; dis="$(gsettings get org.gnome.shell disabled-extensions 2>/dev/null)"
  if ! printf '%s' "$dis" | grep -q "'$u'"; then
    if [ "$dis" = "@as []" ] || [ -z "$dis" ]; then dis="['$u']"; else dis="${dis%]}, '$u']"; fi
    gsettings set org.gnome.shell disabled-extensions "$dis" 2>/dev/null
  fi
  local en; en="$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null)"
  if printf '%s' "$en" | grep -q "'$u'"; then
    en="$(printf '%s' "$en" | sed "s/'$u'//; s/, ,/,/; s/\[, /[/; s/, \]/]/")"; gsettings set org.gnome.shell enabled-extensions "$en" 2>/dev/null
  fi
  log "disabled $u"
}

# ---------------- per-extension settings ----------------
configure_dash_to_dock() {
  local p=/org/gnome/shell/extensions/dash-to-dock
  dset $p/dock-position "'BOTTOM'"
  dset $p/extend-height false
  dset $p/dock-fixed false
  dset $p/autohide true
  dset $p/intellihide true
  dset $p/intellihide-mode "'FOCUS_APPLICATION_WINDOWS'"
  dset $p/autohide-in-fullscreen false
  dset $p/require-pressure-to-show true
  dset $p/show-delay 0.15
  dset $p/hide-delay 0.2
  dset $p/animation-time 0.25
  dset $p/dash-max-icon-size 48
  dset $p/icon-size-fixed false
  dset $p/show-favorites true
  dset $p/show-running true
  dset $p/show-trash true
  dset $p/show-mounts false
  dset $p/show-show-apps-button true
  dset $p/show-apps-at-top false
  dset $p/animate-show-apps true
  dset $p/show-windows-preview true
  dset $p/click-action "'focus-or-previews'"
  dset $p/scroll-action "'cycle-windows'"
  dset $p/middle-click-action "'launch'"
  dset $p/multi-monitor false
  dset $p/preferred-monitor -1
  dset $p/isolate-workspaces false
  dset $p/apply-custom-theme false
  dset $p/custom-theme-shrink true
  dset $p/transparency-mode "'DEFAULT'"
  dset $p/running-indicator-style "'DOTS'"
  dset $p/custom-theme-customize-running-dots false
  dset $p/height-fraction 0.9
  dset $p/hot-keys true
  dset $p/hotkeys-overlay false
  dset $p/shortcut "@as []"
  dset $p/shortcut-text "''"
  dset $p/disable-overview-on-startup true
}

# Apple logo for the top-left menu. Newer Logo Menu builds accept a custom icon; the GNOME 3.x build only knows
# its bundled distro icons, so there we add WhiteSur's apple glyph as one more bundled entry (idempotent).
logomenu_apple_icon() {
  local d="$EXT_DIR/logomenu@aryan_k" p=/org/gnome/shell/extensions/Logo-menu
  local svg="$MACIFY_CACHE/src/WhiteSur-gtk-theme/src/assets/gnome-shell/activities/activities-apple.svg"
  [ -d "$d" ] && [ -f "$svg" ] || return 0
  if grep -qs "custom-icon" "$d"/schemas/*.gschema.xml; then
    mkdir -p "$HOME/.local/share/macify"; cp "$svg" "$HOME/.local/share/macify/apple-logo-symbolic.svg"
    dset $p/use-custom-icon true
    dset $p/custom-icon-path "'$HOME/.local/share/macify/apple-logo-symbolic.svg'"
    return 0
  fi
  [ -d "$d/Resources" ] && [ -f "$d/constants.js" ] || return 0
  cp "$svg" "$d/Resources/apple-logo-symbolic.svg"
  local idx; idx="$(python3 -I - "$d/constants.js" <<'PY2'
import re, sys
p = sys.argv[1]; s = open(p).read()
if 'apple-logo-symbolic' not in s:
    ms = list(re.finditer(r"\{\s*PATH:\s*'[^']+'\s*\}", s)); end = ms[-1].end()
    s = s[:end] + ",\n    { PATH: '/Resources/apple-logo-symbolic.svg'}" + s[end:]
    open(p, 'w').write(s)
print(re.findall(r"PATH:\s*'([^']+)'", s).index('/Resources/apple-logo-symbolic.svg'))
PY2
)"
  [ -n "$idx" ] && dset $p/menu-button-icon-image "$idx"
}

configure_logomenu() {
  local p=/org/gnome/shell/extensions/Logo-menu
  dset $p/use-custom-icon false        # default first; logomenu_apple_icon (below) turns it on where the build supports it
  dset $p/menu-button-icon-size 22
  dset $p/menu-button-icon-click-type 2       # left click opens the menu
  dset $p/show-power-options true
  dset $p/show-lockscreen true
  dset $p/hide-forcequit false
  dset $p/menu-button-terminal "'gnome-terminal'"
  dset $p/menu-button-system-monitor "'gnome-system-monitor'"
  dset $p/symbolic-icon true
  dset $p/show-activities-button false
  dset $p/hide-icon-shadow true
  logomenu_apple_icon                 # last, so the Apple glyph is not overridden by the defaults above
}

configure_just_perfection() {
  local p=/org/gnome/shell/extensions/just-perfection
  dset $p/activities-button false
  dset $p/app-menu true
  dset $p/app-menu-icon false
  dset $p/hot-corner false
  dset $p/workspace-popup false
  dset $p/clock-menu-position 1          # right side of the menu bar
  dset $p/clock-menu-position-offset 99  # after the status icons, i.e. far right like macOS
  dset $p/startup-status 0               # boot to the desktop, not the overview (GNOME 40+)
  dset $p/animation 1
  dset $p/window-demands-attention-focus false
  dset $p/ripple-box false
  dset $p/theme false
}

configure_unite() {
  local p=/org/gnome/shell/extensions/unite
  dset $p/hide-activities-button "'never'"     # Just Perfection handles it
  dset $p/show-window-title "'never'"
  dset $p/show-window-buttons "'never'"
  dset $p/hide-window-titlebars "'never'"
  dset $p/show-desktop-name true
  dset $p/desktop-name-text "'Finder'"
  dset $p/greyscale-tray-icons true
  dset $p/notifications-position "'right'"
  dset $p/hide-app-menu-icon true
  dset $p/hide-app-menu-arrow true
  dset $p/hide-dropdown-arrows true
  dset $p/hide-aggregate-menu-arrow true
  dset $p/reduce-panel-spacing true
  dset $p/extend-left-box false
  dset $p/autofocus-windows false
  dset $p/restrict-to-primary-screen true
  dset $p/use-system-fonts true
  dset $p/enable-titlebar-actions true
  dset $p/show-legacy-tray false
}

configure_blur_my_shell() {
  local p=/org/gnome/shell/extensions/blur-my-shell
  dset $p/sigma 30
  dset $p/brightness 0.6
  # the GNOME 3.x build of Blur my Shell paints the menu bar flat grey on some GPUs; the theme's own
  # 45% dark panel already gives the macOS look there, so panel blur is only used on GNOME 40+
  if [ "${GS_MAJOR:-0}" -ge 40 ] 2>/dev/null; then dset $p/blur-panel true; else dset $p/blur-panel false; fi
  dset $p/blur-dash true
  dset $p/blur-overview true
  dset $p/blur-lockscreen true
  dset $p/static-blur true
  dset $p/hacks-level 1
  dset $p/dash-opacity 0.12
  # newer (GNOME 42+) layout of the same settings
  dset $p/panel/blur true
  dset $p/dash-to-dock/blur true
  dset $p/overview/blur true
  dset $p/lockscreen/blur true
  dset $p/applications/blur false
}

configure_notification_banner_reloaded() {
  local p=/org/gnome/shell/extensions/notification-banner-reloaded
  dset $p/anchor-horizontal 1   # right
  dset $p/anchor-vertical 0     # top
  dset $p/animation-direction 1
}

configure_magic_lamp() {
  local p=/org/gnome/shell/extensions/com/github/hermes83/compiz-alike-magic-lamp-effect
  dset $p/effect "'default'"
  dset $p/duration 400.0
}

setup_extensions() {
  ensure_session_bus
  local u want=() fb
  for u in "${MACIFY_EXTENSIONS[@]}"; do
    if ext_install "$u"; then want+=("$u")
    elif fb="${MACIFY_EXT_FALLBACK[$u]:-}"; [ -n "$fb" ] && ext_install "$fb"; then want+=("$fb")
    fi
  done
  # Ubuntu's own dock conflicts with Dash to Dock
  if printf '%s\n' "${want[@]}" | grep -q '^dash-to-dock@'; then ext_disable ubuntu-dock@ubuntu.com; fi
  for u in "${want[@]}"; do
    case "$u" in
      dash-to-dock@*)             configure_dash_to_dock ;;
      logomenu@*)                 configure_logomenu ;;
      just-perfection-desktop@*)  configure_just_perfection ;;
      unite@*)                    configure_unite ;;
      blur-my-shell@*)            configure_blur_my_shell ;;
      notification-banner-reloaded@*) configure_notification_banner_reloaded ;;
      compiz-alike-magic-lamp-effect@*) configure_magic_lamp ;;
    esac
    ext_enable "$u"
  done
  MACIFY_ENABLED_EXTENSIONS=("${want[@]}")
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then detect_env; setup_extensions; fi
