#!/usr/bin/env bash
# macify: WhiteSur GTK/Shell theme, icons, cursors, wallpapers, Firefox theme, login screen (GDM)
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

WHITESUR_REPOS=(WhiteSur-gtk-theme WhiteSur-icon-theme WhiteSur-cursors WhiteSur-wallpapers)
SRC="$MACIFY_CACHE/src"

fetch_sources() {
  mkdir -p "$SRC"; local r d
  for r in "${WHITESUR_REPOS[@]}"; do
    d="$SRC/$r"
    if [ -d "$d/.git" ]; then git -C "$d" pull -q --ff-only >/dev/null 2>&1 || warn "could not update $r (using cached copy)"
    else git clone -q --depth 1 "https://github.com/vinceliuice/$r.git" "$d" || die "clone of $r failed (network?)"; fi
  done
  ok "theme sources ready in $SRC"
}

install_gtk_shell_theme() {
  local opts=(-c dark -c light -o normal -t default --shell -i apple -p 45)
  [ "${GS_MAJOR:-0}" -ge 42 ] 2>/dev/null && opts+=(-l)     # libadwaita apps follow the theme on GNOME 42+
  [ "$MACIFY_DRY_RUN" = 1 ] && { log "(dry) WhiteSur-gtk-theme/install.sh ${opts[*]}"; return 0; }
  (cd "$SRC/WhiteSur-gtk-theme" && ./install.sh "${opts[@]}" >/dev/null 2>&1) || die "WhiteSur GTK theme install failed"
  ok "GTK + GNOME Shell theme installed (~/.themes/WhiteSur-Dark, WhiteSur-Light)"
}

install_icons_cursors() {
  [ "$MACIFY_DRY_RUN" = 1 ] && { log "(dry) icon + cursor themes"; return 0; }
  (cd "$SRC/WhiteSur-icon-theme" && ./install.sh -t default -a >/dev/null 2>&1) || die "WhiteSur icon theme install failed"
  (cd "$SRC/WhiteSur-cursors" && ./install.sh >/dev/null 2>&1) || die "WhiteSur cursor install failed"
  ok "icons (WhiteSur, -light, -dark) and cursors installed"
}

install_wallpapers() {
  [ "$MACIFY_DRY_RUN" = 1 ] && { log "(dry) wallpapers"; return 0; }
  (cd "$SRC/WhiteSur-wallpapers" && as_root ./install-gnome-backgrounds.sh -s 4k >/dev/null 2>&1) || warn "wallpaper install failed"
  ok "macOS-style wallpapers installed under /usr/share/backgrounds"
}

install_firefox_theme() {
  [ -d "$HOME/.mozilla/firefox" ] || { log "no Firefox profile, skipping Safari-style Firefox theme"; return 0; }
  [ "$MACIFY_DRY_RUN" = 1 ] && { log "(dry) firefox theme"; return 0; }
  (cd "$SRC/WhiteSur-gtk-theme" && ./tweaks.sh -f monterey >/dev/null 2>&1) && ok "Firefox theme installed (takes effect on next Firefox start)" || warn "Firefox theme install failed"
}

install_gdm_theme() {
  local wp; wp="$(MACIFY_VARIANT="$MACIFY_VARIANT" pick_wallpaper 2>/dev/null || true)"
  [ "$MACIFY_DRY_RUN" = 1 ] && { log "(dry) GDM theme"; return 0; }
  (cd "$SRC/WhiteSur-gtk-theme" && as_root ./tweaks.sh -g ${wp:+-b "$wp"} --silent-mode >/dev/null 2>&1) && ok "login screen (GDM) theme installed" || warn "GDM theme install failed (login screen left unchanged)"
}

configure_greeter_defaults() {   # login screen: no distro logo, 12h clock with weekday/date, Inter font
  local f=/etc/gdm3/greeter.dconf-defaults
  [ -f "$f" ] || return 0
  [ "$MACIFY_DRY_RUN" = 1 ] && { log "(dry) greeter defaults"; return 0; }
  [ -f "$f.macify-orig" ] || as_root cp "$f" "$f.macify-orig"
  as_root python3 -I - "$f" <<'PY2'
import re, sys
p = sys.argv[1]; s = open(p).read()
if '[org/gnome/login-screen]' in s:
    a = s.index('[org/gnome/login-screen]'); b = s.find('\n[', a + 1); b = len(s) if b == -1 else b
    sec = s[a:b]
    sec = re.sub(r'(?m)^#?\s*logo\s*=.*$', "logo=''", sec, count=1) if re.search(r'(?m)^#?\s*logo\s*=', sec) else sec.rstrip('\n') + "\nlogo=''\n"
    s = s[:a] + sec + s[b:]
else:
    s += "\n[org/gnome/login-screen]\nlogo=''\n"
if '# macify:' not in s:
    s += "\n# macify: login screen clock and font like the desktop\n[org/gnome/desktop/interface]\nclock-format='12h'\nclock-show-date=true\nclock-show-weekday=true\nfont-name='Inter 11'\n"
open(p, 'w').write(s)
PY2
  # Ubuntu compiles this file into /var/lib/gdm3/greeter-dconf-defaults at GDM start; do it now the same way
  [ -x /usr/share/gdm/generate-config ] && as_root /usr/share/gdm/generate-config >/dev/null 2>&1
  as_root dconf update >/dev/null 2>&1
  ok "login screen defaults set (no logo, 12h clock, Inter)"
}

theme_snaps() {   # confined snap apps only see their own home: give each a private copy of the GTK theme
  have snap || return 0
  [ "$MACIFY_DRY_RUN" = 1 ] && { log "(dry) snap theme copies"; return 0; }
  local d t n=0 app
  for d in "$HOME"/snap/*/current; do
    [ -d "$d" ] || continue
    app="$(basename "$(dirname "$d")")"
    t="$d/.themes"
    if [ -L "$t" ]; then                        # launcher-made link to the bundled themes: keep them reachable
      readlink "$t" > "$d/.themes.macify-orig-link"; local target; target="$(readlink -f "$t")"
      rm -f "$t"; mkdir -p "$t"
      [ -d "$target" ] && for e in "$target"/*; do [ -e "$e" ] && ln -sfn "$e" "$t/$(basename "$e")"; done
    elif [ ! -e "$t" ]; then
      mkdir -p "$t"
      local bundled="/snap/$app/current/data-dir/themes"
      [ -d "$bundled" ] && for e in "$bundled"/*; do [ -e "$e" ] && ln -sfn "$e" "$t/$(basename "$e")"; done
    fi
    rm -rf "$t/WhiteSur-Dark" "$t/WhiteSur-Light"
    cp -r "$HOME/.themes/WhiteSur-Dark" "$HOME/.themes/WhiteSur-Light" "$t/" 2>/dev/null && n=$((n+1))
  done
  [ $n -gt 0 ] && ok "WhiteSur GTK theme available to $n snap apps (takes effect when each app restarts)"
}

remove_themes() {
  local f=/etc/gdm3/greeter.dconf-defaults
  if [ -f "$f.macify-orig" ]; then as_root mv "$f.macify-orig" "$f"; as_root touch "$f"; [ -x /usr/share/gdm/generate-config ] && as_root /usr/share/gdm/generate-config >/dev/null 2>&1; as_root dconf update >/dev/null 2>&1; fi
  local d; for d in "$HOME"/snap/*/current; do
    rm -rf "$d/.themes/WhiteSur-Dark" "$d/.themes/WhiteSur-Light" 2>/dev/null
    if [ -f "$d/.themes.macify-orig-link" ]; then rm -rf "$d/.themes"; ln -s "$(cat "$d/.themes.macify-orig-link")" "$d/.themes"; rm -f "$d/.themes.macify-orig-link"; fi
  done
  [ -d "$SRC/WhiteSur-gtk-theme" ] || fetch_sources
  (cd "$SRC/WhiteSur-gtk-theme" && as_root ./tweaks.sh -r --silent-mode >/dev/null 2>&1) || true   # GDM + Firefox + flatpak hooks
  (cd "$SRC/WhiteSur-gtk-theme" && ./install.sh -r >/dev/null 2>&1) || true
  (cd "$SRC/WhiteSur-icon-theme" && ./install.sh -r >/dev/null 2>&1) || true
  rm -rf "$HOME/.local/share/icons/WhiteSur-cursors"
  (cd "$SRC/WhiteSur-wallpapers" && as_root ./install-gnome-backgrounds.sh -u >/dev/null 2>&1) || true
  rm -f "$HOME/.local/share/applications/org.gnome.GTK4ThemeSwitcher.desktop" "$HOME/.local/bin/gnome-theme-switcher"
  ok "WhiteSur themes removed"
}

install_themes() { fetch_sources; install_gtk_shell_theme; install_icons_cursors; install_wallpapers; }

if [ "${BASH_SOURCE[0]}" = "$0" ]; then detect_env; . "$(dirname "${BASH_SOURCE[0]}")/settings.sh"; install_themes; fi
