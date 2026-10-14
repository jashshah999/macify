#!/usr/bin/env bash
# macify: apt dependencies (names that exist on this release only)
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

install_deps() {
  have apt-get || die "macify targets Ubuntu (apt-based) systems"
  local want=(git curl unzip python3 dconf-cli sassc gtk2-engines-murrine gnome-themes-extra libglib2.0-dev-bin libxml2-utils
              imagemagick gnome-tweaks gnome-shell-extensions gnome-shell-extension-prefs fonts-inter fonts-dejavu-core dialog)
  local avail=() p
  for p in "${want[@]}"; do
    if apt-cache policy "$p" 2>/dev/null | grep -q "Candidate: [^(]"; then avail+=("$p"); else log "package $p not available on this release, skipping"; fi
  done
  if [ "$MACIFY_DRY_RUN" = 1 ]; then log "(dry) apt-get install ${avail[*]}"; return 0; fi
  log "installing: ${avail[*]}"
  as_root apt-get update -q >/dev/null 2>&1 || warn "apt-get update had errors (continuing)"
  as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -q "${avail[@]}" >/dev/null || die "apt-get install failed"
  ok "dependencies installed"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then detect_env; install_deps; fi
