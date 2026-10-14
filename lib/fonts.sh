#!/usr/bin/env bash
# macify: fonts. Inter (open, closest to SF Pro) + aliases so "SF Pro"/"Menlo" requests resolve to open fonts.
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

INTER_URL="https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip"

install_fonts() {
  if ! fc-list : family 2>/dev/null | grep -qx "Inter"; then
    log "Inter not provided by apt here; downloading from GitHub"
    local tmp; tmp="$(mktemp -d)"
    if curl -fsSL --max-time 300 -o "$tmp/inter.zip" "$INTER_URL" && unzip -q "$tmp/inter.zip" -d "$tmp/inter"; then
      mkdir -p "$HOME/.local/share/fonts/Inter"
      find "$tmp/inter" -type f \( -name '*.ttf' -o -name '*.otf' -o -name '*.ttc' \) -not -path '*web*' -exec cp {} "$HOME/.local/share/fonts/Inter/" \;
      ok "Inter installed to ~/.local/share/fonts/Inter"
    else
      warn "could not download Inter; UI font will stay as is"
    fi
    rm -rf "$tmp"
  fi
  mkdir -p "$HOME/.config/fontconfig/conf.d"
  install -m 644 "$MACIFY_DIR/assets/fontconfig/60-macify-aliases.conf" "$HOME/.config/fontconfig/conf.d/60-macify-aliases.conf"
  fc-cache -f >/dev/null 2>&1 || true
  ok "fonts ready: 'SF Pro Text' -> $(fc-match 'SF Pro Text' 2>/dev/null | cut -d: -f2 | xargs), 'Menlo' -> $(fc-match Menlo 2>/dev/null | cut -d: -f2 | xargs)"
}

remove_fonts() {
  rm -f "$HOME/.config/fontconfig/conf.d/60-macify-aliases.conf"
  rm -rf "$HOME/.local/share/fonts/Inter"
  fc-cache -f >/dev/null 2>&1 || true
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then detect_env; install_fonts; fi
