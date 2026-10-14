# macify

Make an Ubuntu GNOME desktop look and feel like macOS, reversibly, on any Ubuntu release.

```
git clone https://github.com/jashshah999/macify.git ~/macify && cd ~/macify
./install.sh            # dark appearance (default)
./install.sh --light
./install.sh --preview  # whole desktop in a window, from a private copy of your settings (X11)
./install.sh --dry-run  # print what would change
./install.sh --revert   # put everything back
```

## What it does

| Area | What you get | How |
|---|---|---|
| Look | Big Sur/Sonoma-style windows, dialogs, menus, light + dark | WhiteSur GTK 2/3/4 + GNOME Shell theme (`-l` libadwaita on GNOME 42+) |
| Icons, cursor | macOS-style app, folder and system icons; macOS cursor | WhiteSur icon theme (`-a` Finder/App Store variants), WhiteSur cursors |
| Wallpaper | Sonoma / Ventura / Monterey / Big Sur 4K wallpapers, lock screen too | WhiteSur wallpapers → `/usr/share/backgrounds` |
| Fonts | Inter (open SF Pro look-alike) as UI font, DejaVu Sans Mono (Menlo's parent) for code, grayscale smoothing | `fonts-inter`, fontconfig aliases so "SF Pro", "Menlo", "-apple-system" resolve to them |
| Windows | traffic lights on the left, new windows centered, sheets attached, double-click title to zoom | gsettings |
| Menu bar | Apple-style logo menu (About, Settings, Sleep/Restart/Shut Down, Lock…), app name next to it, clock on the far right (12h, weekday, date), monochrome tray icons, no "Activities", no hot corner | Logo Menu, Just Perfection, Unite |
| Dock | bottom, auto-hide, running-app dots, Trash, Launchpad button, dot indicators | Dash to Dock (Ubuntu Dock disabled) |
| Effects | frosted-glass panel/dock/overview, genie minimize animation | Blur my Shell, Compiz-alike magic lamp |
| Notifications | top-right banners | Unite (Notification Banner Reloaded on any shell version Unite has no build for) |
| Keys | Super+Space search, Super+Q close, Super+H hide, Super+Tab app switcher, Super+D desktop, Super+, Settings, Super+Shift+3/4 screenshots | gsettings |
| Login screen | WhiteSur GDM theme with blurred wallpaper, no distro logo, 12h clock, Inter | `tweaks.sh -g` (keeps a `.bak` of the original), `/etc/gdm3/greeter.dconf-defaults` (original kept) |
| Firefox | Safari-like Monterey theme (userChrome) | `tweaks.sh -f monterey` |
| Terminal | "macOS" gnome-terminal profile: Terminal.app palette, 80×24, header bar, no menu bar | dconf |
| Desktop | no Home/Trash icons on the desktop (Trash lives in the dock) | gsettings |
| Boot splash | black screen, white logo, thin progress bar (like a Mac boot) | Plymouth two-step theme, initramfs rebuilt for the running kernel |
| Snap apps | WhiteSur GTK theme and icons inside Slack, VLC, Snap Store | theme copied into each snap's private home (`~/snap/<app>/current/.themes`), `icon-theme-whitesur` snap connected to each snap's icon-themes plug |

Extensions are downloaded from extensions.gnome.org for the **running GNOME Shell version**, so the same
script works on Ubuntu 20.04 (GNOME 3.36), 22.04 (42), 24.04 (46) and newer. Anything with no build for
your shell is skipped with a warning instead of breaking the install. All settings use `gsettings` keys
that are checked for existence first, so missing keys on older/newer GNOME are skipped, not errors.

Verified: installed live on Ubuntu 20.04 / GNOME 3.36 (X11). For 22.04 and 24.04, every extension above has
an extensions.gnome.org build for GNOME 42, 44, 46 and 48, every apt dependency exists on focal, jammy and
noble, and the GNOME 42 and 46 code paths were exercised with `--dry-run` against a stubbed shell version.

## Opt-in extras (not installed by default)

| Flag | What | Source |
|---|---|---|
| `--launcher` | Ulauncher as Spotlight on Super+Space (GNOME search moves to Super+S) | GitHub release `.deb`, no PPA |
| `--gestures` | Touchégg + X11 Gestures: 3-finger swipe = Spaces/Mission Control, pinch = Launchpad | GitHub release `.deb` (older release or source build on 20.04), no PPA |
| `--mac-keys` | Cmd+C/V/X/Z/A/W/T/Q… in every app, terminals keep Ctrl+C. Installs Toshy through the same flags its own bootstrap uses. Toshy's keymapper needs Python 3.10+, so on 20.04 (Python 3.8) its environment is rebuilt on python3.10-3.12 if present, else on a standalone CPython 3.11 build fetched from GitHub into `~/.cache/macify` (no PPA, nothing system-wide) | Toshy (RedBearAK), xwaykeyz |

## Revert

`./install.sh --revert` restores the dconf snapshot taken before the first install (`backup/ORIGINAL`),
uninstalls the extensions it added, removes the themes, font aliases, Firefox and login-screen theme, the boot
splash (initramfs rebuilt) and the snap icon theme, and restarts the shell. Log out and back in afterwards for a
fully clean slate. Toshy, if you installed it, is removed with its own `setup_toshy.py uninstall`.

## Layout

```
install.sh            entry point / flags
lib/common.sh         env detection (GNOME version, X11/Wayland, SSH), safe gsettings/dconf helpers, shell restart
lib/deps.sh           apt packages (only ones that exist on this release)
lib/fonts.sh          Inter + fontconfig aliases
lib/themes.sh         WhiteSur theme/icons/cursors/wallpapers, GDM, Firefox
lib/settings.sh       all gsettings/dconf changes (look, keys, dock favorites, terminal profile)
lib/extensions.sh     version-matched extension fetch/enable + per-extension macOS settings
lib/optional.sh       --launcher, --gestures, --mac-keys
lib/revert.sh         backup + revert
lib/boot.sh           Plymouth boot splash
assets/plymouth/      the boot splash theme file
tools/xephyr-preview.sh  --preview: full second GNOME session in an Xephyr window, screenshots of desktop/apps/overview/menus
assets/fontconfig/    font alias config
backup/               created on first install
```

## Known limits

* Snap apps get the theme through a copy in their private home; Electron apps like Slack draw their own UI anyway, so only their GTK dialogs change.
* Mouse scroll direction is left as you had it (trackpad gets natural scrolling); change it in Settings if you want the full Mac feel.
* Apple's own fonts, sounds and wallpapers are not redistributable, so look-alikes are used (Inter, WhiteSur renders).
* On Wayland sessions GNOME Shell cannot restart in place; log out and back in after installing. `--preview` needs X11.
* On GNOME 3.x the menu-bar blur is left off (the old Blur my Shell build paints it flat grey); the theme's translucent dark bar is used instead.
