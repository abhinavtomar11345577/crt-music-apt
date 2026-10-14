#!/bin/sh
# FSpotify (crt-music) installer for Linux, macOS, BSD and Termux.
#
#     curl -fsSL https://abhinavtomar11345577.github.io/crt-music-apt/setup.sh | sh
#
# On Debian, Ubuntu and derivatives this adds the signed APT repository and
# installs the package, so the app updates with the rest of the system.
# Everywhere else it installs the player and its two helpers (mpv, yt-dlp)
# with whatever package manager the system has. Windows has its own
# installer: see https://abhinavtomar11345577.github.io/crt-music-apt for the PowerShell one-liner.
#
# --dry-run prints every change it would make and touches nothing.
set -eu

PAGES_URL=https://abhinavtomar11345577.github.io/crt-music-apt
PACKAGE=crt-music
VERSION=1.1.0
SUITE=stable
COMPONENT=main
APP_SHA256=df120db8e47324f88497eee50c4268a52205ada67ce9e21372c4216368588497
ICON_SHA256=a4628a79681ffdc79d1b4ea3663808ac4bbdad3c169f813d925d38d2e398e4bc
# Architectures the APT repository publishes an index for. The package is
# Architecture: all, but APT only reads the index for its own architecture.
REPO_ARCHES="amd64 arm64 armhf i386"
KEYRING=/usr/share/keyrings/crt-music.gpg
SOURCES_LIST=/etc/apt/sources.list.d/crt-music.list

DRY_RUN=false
MODE=auto
DO_UNINSTALL=false
INSTALLED=

usage() {
    cat <<USAGE
usage: setup.sh [--dry-run] [--portable] [--apt] [--uninstall]

  --dry-run    print every change that would be made, change nothing
  --portable   skip APT even on Debian/Ubuntu and install under \$HOME
  --apt        require the APT path and fail if it is unavailable
  --uninstall  remove a portable installation made by this script
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=true ;;
        --portable|--no-apt) MODE=portable ;;
        --apt) MODE=apt ;;
        --uninstall) DO_UNINSTALL=true ;;
        -h|--help) usage; exit 0 ;;
        *) echo "setup.sh: unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

say()  { printf '==> %s\n' "$*"; }
warn() { printf 'setup.sh: %s\n' "$*" >&2; }
die()  { printf 'setup.sh: %s\n' "$*" >&2; exit 1; }

# Every change to the system goes through run(), so --dry-run can show the
# whole plan and a dry run cannot alter anything by accident.
run() {
    if $DRY_RUN; then
        printf '    would run:'
        printf ' %s' "$@"
        printf '\n'
        return 0
    fi
    "$@"
}

fetch() {  # fetch URL DEST
    if command -v curl >/dev/null 2>&1; then
        curl --fail --silent --show-error --location --retry 3 --retry-delay 2 "$1" -o "$2"
    elif command -v wget >/dev/null 2>&1; then
        wget --quiet --tries=3 -O "$2" "$1"
    else
        die "need curl or wget to download $1"
    fi
}

# Returns the SHA-256 of $1, or an empty string if this system has no tool
# for it. Verification is then skipped rather than failing the install.
sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | cut -d' ' -f1
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "$1" | awk '{print $NF}'
    else
        echo ""
    fi
}

verify_sha256() {  # verify_sha256 FILE EXPECTED WHAT
    got=$(sha256_of "$1")
    if [ -z "$got" ]; then
        warn "no SHA-256 tool here; cannot verify $3"
        return 0
    fi
    [ "$got" = "$2" ] || die "$3 does not match its published checksum.
expected $2
got      $got
Check the network (a proxy or captive portal may have replaced the file)."
}

case "$(uname -s 2>/dev/null || echo unknown)" in
    MINGW*|MSYS*|CYGWIN*|Windows_NT)
        die "this is the Unix installer. On Windows, run in PowerShell:
    irm https://abhinavtomar11345577.github.io/crt-music-apt/install.ps1 | iex" ;;
    Darwin) OS=macos ;;
    Linux)  OS=linux ;;
    *)      OS=other ;;
esac

# Termux is Android: no sudo, no system directories, its own prefix.
IS_TERMUX=false
case "${PREFIX:-}" in
    *com.termux*) IS_TERMUX=true ;;
esac

if [ "$(id -u)" -eq 0 ]; then
    SUDO=
elif command -v sudo >/dev/null 2>&1; then
    SUDO=sudo
elif command -v doas >/dev/null 2>&1; then
    SUDO=doas
else
    SUDO=
fi
$IS_TERMUX && SUDO=

# ---------------------------------------------------------------- portable --
# Paths for the no-package-manager installation. A root install goes to
# /usr/local so every user gets it; otherwise everything stays under $HOME
# and no password is needed for the app itself.
if [ "$(id -u)" -eq 0 ] && ! $IS_TERMUX; then
    PREFIX_DIR=/usr/local
    XDG_DATA=/usr/local/share
elif $IS_TERMUX; then
    PREFIX_DIR="${PREFIX:-$HOME}"
    XDG_DATA="${PREFIX:-$HOME}/share"
else
    PREFIX_DIR="$HOME/.local"
    XDG_DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
fi
BIN_DIR="$PREFIX_DIR/bin"
LIB_DIR="$XDG_DATA/crt-music"
# Where a helper binary we fetch ourselves goes. The player puts this exact
# directory at the front of its own PATH, so a current yt-dlp here wins over
# the distribution's packaged one even for a system-wide install.
if [ "$(id -u)" -eq 0 ] && ! $IS_TERMUX; then
    HELPER_BIN=/usr/local/bin
else
    HELPER_BIN="$XDG_DATA/crt-music/bin"
fi
DESKTOP_DIR="$XDG_DATA/applications"
ICON_DIR="$XDG_DATA/icons/hicolor/512x512/apps"

uninstall_portable() {
    say "Removing the portable installation"
    for path in \
        "$BIN_DIR/crt-music" \
        "$LIB_DIR/crt-music" \
        "$HELPER_BIN/yt-dlp" \
        "$DESKTOP_DIR/crt-music.desktop" \
        "$ICON_DIR/crt-music.png"
    do
        [ -e "$path" ] && run rm -f "$path"
    done
    # Only ever remove directories that are ours: for a root install
    # HELPER_BIN is /usr/local/bin, which must obviously stay.
    case "$HELPER_BIN" in
        */crt-music/bin) [ -d "$HELPER_BIN" ] && run rmdir "$HELPER_BIN" 2>/dev/null || true ;;
    esac
    [ -d "$LIB_DIR" ] && run rmdir "$LIB_DIR" 2>/dev/null || true
    say "Done. mpv and yt-dlp installed by your package manager were left alone."
    case ":$PATH:" in
        *":$BIN_DIR:"*) say "The PATH line this installer added to your shell profile is harmless;
    remove it by hand if you want it gone." ;;
    esac
    if command -v dpkg >/dev/null 2>&1 && dpkg -s "$PACKAGE" >/dev/null 2>&1; then
        say "A packaged copy is still installed; remove it with: $SUDO apt remove $PACKAGE"
    fi
}

# Name of TOOL in the package manager PM, where it differs from the command.
package_for() {  # package_for PM TOOL
    case "$1:$2" in
        pacman:python3|termux:python3) echo python ;;
        emerge:python3) echo dev-lang/python ;;
        emerge:mpv) echo media-video/mpv ;;
        emerge:yt-dlp) echo net-misc/yt-dlp ;;
        *) echo "$2" ;;
    esac
}

# Detects the package manager once; sets PM and PM_INSTALL.
PM=
PM_INSTALL=
detect_pm() {
    if [ "$OS" = macos ]; then
        if command -v brew >/dev/null 2>&1; then
            PM=brew; PM_INSTALL="brew install"      # never with sudo
        elif command -v port >/dev/null 2>&1; then
            PM=port; PM_INSTALL="$SUDO port install"
        fi
        return 0
    fi
    if $IS_TERMUX && command -v pkg >/dev/null 2>&1; then
        PM=termux; PM_INSTALL="pkg install -y"
        return 0
    fi
    if command -v apt-get >/dev/null 2>&1; then
        PM=apt; PM_INSTALL="$SUDO apt-get install -y"
    elif command -v dnf >/dev/null 2>&1; then
        PM=dnf; PM_INSTALL="$SUDO dnf install -y"
    elif command -v yum >/dev/null 2>&1; then
        PM=yum; PM_INSTALL="$SUDO yum install -y"
    elif command -v pacman >/dev/null 2>&1; then
        PM=pacman; PM_INSTALL="$SUDO pacman -S --needed --noconfirm"
    elif command -v zypper >/dev/null 2>&1; then
        PM=zypper; PM_INSTALL="$SUDO zypper --non-interactive install"
    elif command -v apk >/dev/null 2>&1; then
        PM=apk; PM_INSTALL="$SUDO apk add"
    elif command -v xbps-install >/dev/null 2>&1; then
        PM=xbps; PM_INSTALL="$SUDO xbps-install -Sy"
    elif command -v eopkg >/dev/null 2>&1; then
        PM=eopkg; PM_INSTALL="$SUDO eopkg install -y"
    elif command -v emerge >/dev/null 2>&1; then
        PM=emerge; PM_INSTALL="$SUDO emerge --ask=n"
    elif command -v pkg >/dev/null 2>&1; then
        PM=pkg; PM_INSTALL="$SUDO pkg install -y"          # FreeBSD
    elif command -v nix-env >/dev/null 2>&1; then
        PM=nix; PM_INSTALL="nix-env -iA"
    fi
}

PM_UPDATED=false
pm_install() {  # pm_install TOOL -> 0 if it is installed afterwards
    tool=$1
    [ -n "$PM_INSTALL" ] || return 1
    name=$(package_for "$PM" "$tool")
    # APT refuses to install from an index it has never read, which is the
    # usual state of a fresh container or a machine that has not updated.
    if [ "$PM" = apt ] && ! $PM_UPDATED; then
        PM_UPDATED=true
        run $SUDO apt-get update >/dev/null 2>&1 || true
    fi
    if [ "$PM" = nix ]; then
        name="nixpkgs.$name"
    fi
    say "Installing $tool"
    # shellcheck disable=SC2086
    run $PM_INSTALL "$name" >/dev/null 2>&1 || return 1
    $DRY_RUN && return 0
    command -v "$tool" >/dev/null 2>&1
}

# YouTube only serves streams to a current yt-dlp. Distributions ship one
# that is often a year or more old, and such a build still searches but
# cannot play a single track - the one failure that makes the player look
# broken. So the version matters, not merely that the command exists.
MIN_YTDLP=20260101

ytdlp_date() {  # 2026.08.19 -> 20260819, empty if it cannot be read
    command -v yt-dlp >/dev/null 2>&1 || return 0
    yt-dlp --version 2>/dev/null | head -1 \
        | awk -F. 'NF>=3 { printf "%04d%02d%02d", $1, $2, $3 }'
}

ytdlp_current() {
    have=$(ytdlp_date)
    [ -n "$have" ] || return 1
    [ "$have" -ge "$MIN_YTDLP" ] 2>/dev/null
}

ensure_ytdlp() {
    if ! command -v yt-dlp >/dev/null 2>&1; then
        pm_install yt-dlp >/dev/null 2>&1 || true
    fi
    if $DRY_RUN; then
        ytdlp_current && return 0
        printf '    would install the current yt-dlp into %s\n' "$HELPER_BIN"
        return 0
    fi
    if ytdlp_current; then
        say "yt-dlp $(yt-dlp --version 2>/dev/null | head -1) is current"
        return 0
    fi
    if command -v yt-dlp >/dev/null 2>&1; then
        warn "the installed yt-dlp ($(yt-dlp --version 2>/dev/null | head -1)) is too old
for YouTube; installing the current build alongside it."
    fi
    install_ytdlp_upstream || {
        warn "could not install yt-dlp: radio will work, YouTube will not.
Install it yourself from https://github.com/yt-dlp/yt-dlp"
        return 1
    }
    ytdlp_current || warn "yt-dlp still looks out of date; YouTube may not play."
    return 0
}

# The upstream standalone build runs anywhere and is always current.
install_ytdlp_upstream() {
    base=https://github.com/yt-dlp/yt-dlp/releases/latest/download
    case "$OS:$(uname -m 2>/dev/null || echo unknown)" in
        macos:*)          asset=yt-dlp_macos ;;
        linux:x86_64|linux:amd64) asset=yt-dlp_linux ;;
        linux:aarch64|linux:arm64) asset=yt-dlp_linux_aarch64 ;;
        linux:armv7l|linux:armv7*) asset=yt-dlp_linux_armv7l ;;
        *)                asset=yt-dlp ;;   # the portable zipapp; needs python3
    esac
    say "Fetching yt-dlp ($asset) from the official release"
    if $DRY_RUN; then
        printf '    would download: %s/%s -> %s/yt-dlp\n' "$base" "$asset" "$HELPER_BIN"
        return 0
    fi
    mkdir -p "$HELPER_BIN"
    fetch "$base/$asset" "$tmpdir/yt-dlp" || return 1
    chmod 0755 "$tmpdir/yt-dlp"
    mv "$tmpdir/yt-dlp" "$HELPER_BIN/yt-dlp"
    PATH="$HELPER_BIN:$PATH"
    export PATH
    command -v yt-dlp >/dev/null 2>&1
}

find_python() {
    for candidate in python3 python python3.13 python3.12 python3.11 python3.10 python3.9; do
        if command -v "$candidate" >/dev/null 2>&1 \
            && "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)' \
                >/dev/null 2>&1; then
            command -v "$candidate"
            return 0
        fi
    done
    return 1
}

portable_install() {
    say "Installing FSpotify $VERSION for $OS under $PREFIX_DIR"
    detect_pm
    [ -n "$PM" ] && say "Package manager: $PM"

    PYTHON=$(find_python || true)
    if [ -z "$PYTHON" ]; then
        pm_install python3 || true
        PYTHON=$(find_python || true)
    fi
    if [ -z "$PYTHON" ]; then
        $DRY_RUN && PYTHON=python3 || die "FSpotify needs Python 3.9 or newer.
Install python3 with your package manager and run this again."
    fi
    say "Python: $PYTHON"

    # Debian splits curses out of the python3 package on minimal images, and
    # a Python built without it cannot draw the interface at all.
    if ! $DRY_RUN && ! "$PYTHON" -c 'import curses' >/dev/null 2>&1; then
        case "$PM" in
            apt) pm_install python3-curses || true ;;
            dnf|yum) pm_install python3-libs || true ;;
        esac
        "$PYTHON" -c 'import curses' >/dev/null 2>&1 \
            || die "this Python has no curses module; install a full python3 package."
    fi

    if ! command -v mpv >/dev/null 2>&1; then
        pm_install mpv || true
    fi
    if ! $DRY_RUN && ! command -v mpv >/dev/null 2>&1; then
        if [ "$OS" = macos ]; then
            die "FSpotify needs mpv for playback. Install Homebrew from
https://brew.sh and run this installer again, or install mpv yourself:
    brew install mpv"
        fi
        die "FSpotify needs mpv for playback, and it could not be installed
automatically. Install the 'mpv' package with your package manager, then run
this installer again."
    fi

    ensure_ytdlp || true

    say "Fetching the player"
    if $DRY_RUN; then
        printf '    would download: %s/crt-music -> %s/crt-music\n' "$PAGES_URL" "$LIB_DIR"
    else
        fetch "$PAGES_URL/crt-music" "$tmpdir/crt-music" \
            || die "could not download $PAGES_URL/crt-music"
        verify_sha256 "$tmpdir/crt-music" "$APP_SHA256" "the downloaded player"
    fi

    run mkdir -p "$BIN_DIR" "$LIB_DIR"
    run install -m 0755 "$tmpdir/crt-music" "$LIB_DIR/crt-music"

    # A launcher rather than the script itself: it pins the interpreter found
    # just now, so the install does not depend on '#!/usr/bin/env python3'
    # resolving to a new enough Python on this machine.
    say "Writing $BIN_DIR/crt-music"
    if $DRY_RUN; then
        printf '    would write: %s/crt-music (launcher for %s)\n' "$BIN_DIR" "$PYTHON"
    else
        cat > "$tmpdir/launcher" <<LAUNCHER
#!/bin/sh
# FSpotify launcher, written by setup.sh.
PY="$PYTHON"
[ -x "\$PY" ] || PY=python3
exec "\$PY" "$LIB_DIR/crt-music" "\$@"
LAUNCHER
        install -m 0755 "$tmpdir/launcher" "$BIN_DIR/crt-music"
    fi

    if [ "$OS" = linux ] && ! $IS_TERMUX; then
        say "Adding the desktop entry"
        run mkdir -p "$DESKTOP_DIR" "$ICON_DIR"
        if ! $DRY_RUN; then
            if fetch "$PAGES_URL/fspotify.png" "$tmpdir/fspotify.png"; then
                verify_sha256 "$tmpdir/fspotify.png" "$ICON_SHA256" "the downloaded icon"
                install -m 0644 "$tmpdir/fspotify.png" "$ICON_DIR/crt-music.png"
            else
                warn "could not download the icon; the menu entry will have none"
            fi
            cat > "$DESKTOP_DIR/crt-music.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=FSpotify
Comment=Search and stream music and internet radio in a terminal
Exec=$BIN_DIR/crt-music
Icon=crt-music
Terminal=true
Categories=AudioVideo;Player;
Keywords=music;audio;radio;youtube;terminal;
DESKTOP
            command -v update-desktop-database >/dev/null 2>&1 \
                && update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
        fi
    fi

    # PATH. Without this the install "works" but the command is not found,
    # which is the single most common way a per-user install looks broken.
    case ":$PATH:" in
        *":$BIN_DIR:"*) ;;
        *)
            say "Adding $BIN_DIR to your PATH"
            line="export PATH=\"$BIN_DIR:\$PATH\"  # added by crt-music setup.sh"
            for rc in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc"; do
                [ -f "$rc" ] || [ "$rc" = "$HOME/.profile" ] || continue
                if [ -f "$rc" ] && grep -Fq "added by crt-music setup.sh" "$rc"; then
                    continue
                fi
                if $DRY_RUN; then
                    printf '    would append to %s: %s\n' "$rc" "$line"
                else
                    printf '\n%s\n' "$line" >> "$rc"
                fi
            done
            say "Open a new terminal, or run:  export PATH=\"$BIN_DIR:\$PATH\""
            ;;
    esac
}

# --------------------------------------------------------------------- apt --
apt_install() {
    tmp_need=
    command -v curl >/dev/null 2>&1 || tmp_need="$tmp_need curl"
    command -v gpg  >/dev/null 2>&1 || tmp_need="$tmp_need gnupg"
    [ -e /etc/ssl/certs/ca-certificates.crt ] || tmp_need="$tmp_need ca-certificates"
    if [ -n "$tmp_need" ]; then
        say "Installing prerequisites:$tmp_need"
        run $SUDO apt-get update || warn "apt-get update reported errors; continuing"
        # shellcheck disable=SC2086
        run $SUDO apt-get install -y $tmp_need || { warn "could not install:$tmp_need"; return 1; }
    fi

    say "Fetching the FSpotify signing key"
    fetch "$PAGES_URL/apt-key.asc" "$tmpdir/apt-key.asc" \
        || { warn "could not download $PAGES_URL/apt-key.asc"; return 1; }
    # A captive portal or proxy answers with an HTML page and a 200, which
    # would otherwise end up installed as the repository key.
    grep -q 'BEGIN PGP PUBLIC KEY BLOCK' "$tmpdir/apt-key.asc" \
        || { warn "what came back from $PAGES_URL/apt-key.asc is not an OpenPGP key"; return 1; }
    gpg --dearmor --batch --yes --output "$tmpdir/crt-music.gpg" "$tmpdir/apt-key.asc" \
        || { warn "could not convert the signing key"; return 1; }

    # /usr/share/keyrings only exists once some package has shipped a keyring
    # into it, so on a clean system gpg -o /usr/share/keyrings/... fails with
    # "can't create". Create the directory, and write the key with install(1)
    # so a failed run cannot leave a truncated keyring behind.
    say "Installing the signing key to $KEYRING"
    run $SUDO install -d -m 0755 "$(dirname "$KEYRING")" || return 1
    run $SUDO install -m 0644 "$tmpdir/crt-music.gpg" "$KEYRING" || return 1

    arch=$(dpkg --print-architecture 2>/dev/null || echo unknown)
    arch_published=false
    for a in $REPO_ARCHES; do
        [ "$a" = "$arch" ] && arch_published=true
    done

    if $arch_published; then
        say "Writing $SOURCES_LIST"
        line="deb [arch=$arch signed-by=$KEYRING] $PAGES_URL $SUITE $COMPONENT"
        if $DRY_RUN; then
            printf '    would write: %s\n' "$line"
        else
            printf '%s\n' "$line" | $SUDO tee "$SOURCES_LIST" >/dev/null || return 1
        fi

        # Read only this list file. On a machine with some other third-party
        # repository already broken, a plain apt-get update fails and would
        # take this install down with it.
        say "Reading the FSpotify repository"
        run $SUDO apt-get update \
            -o Dir::Etc::sourcelist="$SOURCES_LIST" \
            -o Dir::Etc::sourceparts=- \
            -o APT::Get::List-Cleanup=0 \
            || { warn "could not read $PAGES_URL"; return 1; }

        say "Installing $PACKAGE"
        if ! run $SUDO apt-get install -y "$PACKAGE"; then
            # The dependencies come from the distribution's own sources, and
            # a stale index there is the usual reason the first try fails.
            say "Retrying after a full apt-get update"
            run $SUDO apt-get update || true
            run $SUDO apt-get install -y "$PACKAGE" \
                || { warn "apt could not install $PACKAGE"; return 1; }
        fi
    else
        # Rare architecture with no published index. The package is
        # Architecture: all, so the .deb itself still installs.
        warn "no package index is published for this architecture ($arch)"
        warn "installing the .deb directly; it will not update automatically."
        deb="${PACKAGE}_${VERSION}_all.deb"
        fetch "$PAGES_URL/pool/main/c/$PACKAGE/$deb" "$tmpdir/$deb" \
            || { warn "could not download $deb"; return 1; }
        run $SUDO apt-get install -y "$tmpdir/$deb" || { warn "could not install $deb"; return 1; }
    fi

    # yt-dlp is a Recommends, so APT skips it silently on releases that do not
    # package it - and where it is packaged, it is usually too old to play
    # anything. Either way this leaves a working one in place.
    ensure_ytdlp || true
    return 0
}

# -------------------------------------------------------------------- main --
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT INT TERM

if $DO_UNINSTALL; then
    uninstall_portable
    exit 0
fi

if [ "$MODE" = auto ]; then
    if command -v apt-get >/dev/null 2>&1 && command -v dpkg >/dev/null 2>&1; then
        MODE=apt
    else
        MODE=portable
    fi
fi

if [ "$MODE" = apt ]; then
    command -v apt-get >/dev/null 2>&1 || die "--apt was given, but this system has no APT."
    if [ "$(id -u)" -ne 0 ] && [ -z "$SUDO" ]; then
        warn "no root privileges for a system-wide install; installing under \$HOME instead"
        MODE=portable
    else
        [ -n "$SUDO" ] && [ "$(id -u)" -ne 0 ] && say "Installing system-wide; $SUDO may ask for your password."
        if apt_install; then
            MODE=done
            INSTALLED=apt
        else
            warn "the APT installation did not finish; falling back to a local install."
            MODE=portable
        fi
    fi
fi

if [ "$MODE" = portable ]; then
    portable_install
    INSTALLED=portable
fi

if $DRY_RUN; then
    say "Dry run finished; nothing was changed."
    exit 0
fi

# Check the copy that was just installed, by path. Asking PATH can find an
# older crt-music from a previous install, which does not understand --check
# and would start the player instead of reporting on it.
if [ "$INSTALLED" = portable ] && [ -x "$BIN_DIR/crt-music" ]; then
    CRT="$BIN_DIR/crt-music"
elif command -v crt-music >/dev/null 2>&1; then
    CRT=$(command -v crt-music)
elif [ -x "$BIN_DIR/crt-music" ]; then
    CRT="$BIN_DIR/crt-music"
else
    die "the install finished but crt-music was not found"
fi

"$CRT" --check </dev/null || warn "FSpotify is installed but something above is missing."

# Another copy earlier on PATH would be the one that actually runs.
other=$(command -v crt-music 2>/dev/null || true)
if [ -n "$other" ] && [ "$other" != "$CRT" ]; then
    warn "another crt-music is first on your PATH: $other
Typing 'crt-music' will run that one, not the copy just installed.
Remove the old one (on Debian/Ubuntu: $SUDO apt remove $PACKAGE), or run
$CRT directly."
fi

say "Done. Start it with:  $CRT"
