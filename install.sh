#!/usr/bin/env bash
# macify — make an Ubuntu GNOME desktop look and feel like macOS, reversibly.
# Works across Ubuntu releases: it detects the GNOME Shell version and fetches matching extension builds.
set -u
MACIFY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; export MACIFY_DIR
. "$MACIFY_DIR/lib/common.sh"
. "$MACIFY_DIR/lib/deps.sh"; . "$MACIFY_DIR/lib/fonts.sh"; . "$MACIFY_DIR/lib/themes.sh"
. "$MACIFY_DIR/lib/settings.sh"; . "$MACIFY_DIR/lib/extensions.sh"; . "$MACIFY_DIR/lib/optional.sh"
. "$MACIFY_DIR/lib/revert.sh"; . "$MACIFY_DIR/lib/boot.sh"

usage() {
  cat <<USAGE
usage: ./install.sh [options]

  default            full install: themes, icons, cursors, wallpapers, fonts, login screen, Firefox theme,
                     GNOME settings, dock + menu bar extensions, then an in-place shell restart (X11)
  --light | --dark   appearance (default: dark)
  --preview          run a complete second GNOME session in a window with a private copy of your settings
                     and save screenshots (X11 hosts); changes nothing on your real desktop
  --revert           restore the pre-macify state from backup/ORIGINAL
  --launcher         also install Ulauncher (Spotlight, Super+Space) from its GitHub .deb
  --gestures         also install Touchégg + X11 Gestures (3-finger macOS trackpad gestures)
  --mac-keys         Cmd-style shortcuts in every app: runs Toshy's (interactive) installer
  --no-splash        leave the boot splash alone        --no-snap         leave snap apps alone
  --no-gdm           leave the login screen alone        --no-firefox      leave Firefox alone
  --no-extensions    themes and settings only            --no-deps         skip apt
  --no-restart       do not restart GNOME Shell          --dry-run         print what would be done
USAGE
}

DO_GDM=1 DO_FIREFOX=1 DO_EXT=1 DO_DEPS=1 DO_RESTART=1 DO_LAUNCHER=0 DO_GESTURES=0 DO_MACKEYS=0 DO_SPLASH=1 DO_SNAP=1 REVERT=0 PREVIEW=0
while [ $# -gt 0 ]; do
  case "$1" in
    --light) MACIFY_VARIANT=light ;; --dark) MACIFY_VARIANT=dark ;;
    --no-gdm) DO_GDM=0 ;; --no-firefox) DO_FIREFOX=0 ;; --no-extensions) DO_EXT=0 ;; --no-deps) DO_DEPS=0 ;; --no-restart) DO_RESTART=0 ;;
    --launcher) DO_LAUNCHER=1 ;; --gestures) DO_GESTURES=1 ;; --mac-keys) DO_MACKEYS=1 ;;
    --no-splash) DO_SPLASH=0 ;; --no-snap) DO_SNAP=0 ;;
    --preview) PREVIEW=1 ;; --revert) REVERT=1 ;; --dry-run) MACIFY_DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; die "unknown option: $1" ;;
  esac; shift
done
export MACIFY_VARIANT MACIFY_DRY_RUN

detect_env
[ -n "$GS_VERSION_FULL" ] || die "GNOME Shell not found; macify targets Ubuntu's GNOME desktop"
log "Ubuntu ${DISTRO_VER}, GNOME Shell ${GS_VERSION_FULL} (${SESSION_TYPE}), appearance: ${MACIFY_VARIANT}"

if [ "$REVERT" = 1 ]; then revert_all; exit 0; fi
if [ "$PREVIEW" = 1 ]; then
  [ "$SESSION_TYPE" = x11 ] || die "--preview needs an X11 session"
  out="$MACIFY_CACHE/preview-shots"; bash "$MACIFY_DIR/tools/xephyr-preview.sh" "$out" "${PREVIEW_SIZE:-1920x1200}" ":7" && ok "screenshots in $out"; exit $?
fi

backup_state
[ "$DO_DEPS" = 1 ] && install_deps
install_fonts
install_themes
[ "$DO_GDM" = 1 ] && { install_gdm_theme; configure_greeter_defaults; }
[ "$DO_FIREFOX" = 1 ] && install_firefox_theme
[ "$DO_SPLASH" = 1 ] && install_boot_splash
[ "$DO_SNAP" = 1 ] && { install_snap_icons; theme_snaps; }
apply_settings
[ "$DO_EXT" = 1 ] && setup_extensions
[ "$DO_LAUNCHER" = 1 ] && install_launcher
[ "$DO_GESTURES" = 1 ] && install_gestures
[ "$DO_MACKEYS" = 1 ] && mac_keys
if [ "$NEED_SHELL_RESTART" = 1 ] && [ "$DO_RESTART" = 1 ] && [ "$MACIFY_DRY_RUN" != 1 ]; then restart_shell; fi

cat <<DONE

[macify] done. What changed:
  • WhiteSur ${MACIFY_VARIANT} theme for GTK apps + GNOME Shell, WhiteSur icons & cursors, macOS-style wallpaper
  • Inter as the system font (SF Pro look-alike), DejaVu Sans Mono for code, grayscale text smoothing
  • traffic-light window buttons on the left, centered new windows, menu-bar clock on the right (12h, weekday + date)
  • Dock at the bottom (auto-hide, running dots, Trash), Apple-style logo menu top-left, notifications top-right
  • genie minimize effect, frosted-glass panel/dock, no hot corner, "Finder"-style app name in the menu bar
  • Super+Space = search (Ulauncher if --launcher, else GNOME search), Super+Q = close, Super+H = hide,
    Super+Tab = switch apps, Super+D = show desktop, Super+, = Settings, Super+Shift+3/4 = screenshots
  • login screen themed, Firefox themed like Safari (next start), gnome-terminal "macOS" profile
  • boot splash: black with logo and progress bar (next boot); snap apps use WhiteSur icons
  Revert everything:  $MACIFY_DIR/install.sh --revert
  Log out and back in once to see the login screen and every app pick up the fonts.
DONE
