#!/usr/bin/env bash
# macify: backup before the first install; full revert to that state
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

backup_state() {
  local root="$MACIFY_DIR/backup"; mkdir -p "$root"
  if [ -f "$root/ORIGINAL" ] && [ -f "$(cat "$root/ORIGINAL")/dconf-full.ini" ]; then
    log "original settings backup already exists: $(cat "$root/ORIGINAL")"; return 0
  fi
  local d="$root/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$d"
  ensure_session_bus
  dconf dump / > "$d/dconf-full.ini" 2>/dev/null || warn "dconf dump failed (is a GNOME session running?)"
  ls "$EXT_DIR" > "$d/user-extensions-before.txt" 2>/dev/null || : > "$d/user-extensions-before.txt"
  [ -d "$HOME/.config/fontconfig" ] && cp -r "$HOME/.config/fontconfig" "$d/fontconfig"
  dpkg-query -W -f='${binary:Package}\n' > "$d/packages.txt" 2>/dev/null
  printf '%s' "$d" > "$root/ORIGINAL"
  ok "backed up current settings to $d"
}

revert_all() {
  . "$MACIFY_DIR/lib/fonts.sh"; . "$MACIFY_DIR/lib/themes.sh"; . "$MACIFY_DIR/lib/boot.sh"; . "$MACIFY_DIR/lib/optional.sh"
  ensure_session_bus
  local root="$MACIFY_DIR/backup" d; d="$(cat "$root/ORIGINAL" 2>/dev/null || true)"
  [ -n "$d" ] && [ -f "$d/dconf-full.ini" ] || die "no original backup found under $root; nothing to revert to"
  log "restoring GNOME settings from $d"
  dconf reset -f /org/gnome/ 2>/dev/null || true
  dconf load / < "$d/dconf-full.ini" || warn "dconf load reported errors"
  local u
  for u in $(ls "$EXT_DIR" 2>/dev/null); do
    if ! grep -qx "$u" "$d/user-extensions-before.txt" 2>/dev/null; then
      gnome-extensions uninstall "$u" >/dev/null 2>&1 || rm -rf "${EXT_DIR:?}/$u"; log "removed extension $u"
    fi
  done
  remove_fonts
  remove_themes
  rm -rf "$HOME/.config/gtk-4.0/gtk.css" "$HOME/.config/gtk-4.0/assets" "$HOME/.config/gtk-4.0/windows-assets" 2>/dev/null
  rm -f "$HOME/.config/autostart/ulauncher.desktop"
  remove_boot_splash
  remove_snap_icons
  [ -d "$HOME/.config/toshy" ] && log "Toshy is installed; remove it with: cd $MACIFY_CACHE/src/toshy && ./setup_toshy.py uninstall"
  NEED_SHELL_RESTART=1; restart_shell
  ok "reverted to the pre-macify state (log out and back in to also see the original login screen)"
}
