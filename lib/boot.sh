#!/usr/bin/env bash
# macify: macOS-style boot splash (Plymouth "two-step" theme: black, white logo, thin progress bar)
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

PLY_THEME_DIR=/usr/share/plymouth/themes/macify

install_boot_splash() {
  have plymouth || { log "plymouth not installed, skipping boot splash"; return 0; }
  local svg="$MACIFY_CACHE/src/WhiteSur-gtk-theme/src/assets/gnome-shell/activities/activities-apple.svg"
  [ -f "$svg" ] || { warn "logo asset missing (theme sources not fetched); skipping boot splash"; return 0; }
  [ "$MACIFY_DRY_RUN" = 1 ] && { log "(dry) plymouth theme + initramfs rebuild"; return 0; }
  have convert || as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -q imagemagick >/dev/null
  local tmp; tmp="$(mktemp -d)"
  convert -background none -density 600 "$svg" -resize 180x180 -fill white -colorize 100 -type TrueColorAlpha "PNG32:$tmp/watermark.png" || { warn "could not render logo"; return 0; }
  as_root mkdir -p "$PLY_THEME_DIR"
  as_root cp "$tmp/watermark.png" "$MACIFY_DIR/assets/plymouth/macify.plymouth" "$PLY_THEME_DIR/"
  local f; for f in bullet.png entry.png lock.png; do [ -f "/usr/share/plymouth/themes/spinner/$f" ] && as_root cp "/usr/share/plymouth/themes/spinner/$f" "$PLY_THEME_DIR/"; done
  rm -rf "$tmp"
  as_root update-alternatives --install /usr/share/plymouth/themes/default.plymouth default.plymouth "$PLY_THEME_DIR/macify.plymouth" 200 >/dev/null 2>&1
  as_root update-alternatives --set default.plymouth "$PLY_THEME_DIR/macify.plymouth" >/dev/null 2>&1
  if as_root update-initramfs -u -k "$(uname -r)" >/dev/null 2>&1; then
    ok "boot splash: macify theme is the default and is inside the initramfs for $(uname -r)"
  else
    warn "initramfs rebuild failed; restoring the previous boot splash"
    as_root update-alternatives --remove default.plymouth "$PLY_THEME_DIR/macify.plymouth" >/dev/null 2>&1
  fi
}

remove_boot_splash() {
  have plymouth || return 0
  as_root update-alternatives --remove default.plymouth "$PLY_THEME_DIR/macify.plymouth" >/dev/null 2>&1 || true
  as_root rm -rf "$PLY_THEME_DIR"
  as_root update-initramfs -u -k "$(uname -r)" >/dev/null 2>&1 || warn "initramfs rebuild failed after removing the splash theme"
  ok "boot splash restored to the distro default"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then detect_env; install_boot_splash; fi
