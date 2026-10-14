#!/bin/sh
# FSpotify (crt-music) installer for Debian, Ubuntu and derivatives.
#
#     curl -fsSL https://abhinavtomar11345577.github.io/crt-music-apt/setup.sh | sh
#
# Adds the signed APT repository and installs crt-music, so the app updates
# with the rest of the system. --dry-run prints every change it would make
# and touches nothing.
set -eu

PAGES_URL=https://abhinavtomar11345577.github.io/crt-music-apt
PACKAGE=crt-music
VERSION=1.0.1
SUITE=stable
COMPONENT=main
KEYRING=/usr/share/keyrings/crt-music.gpg
SOURCES_LIST=/etc/apt/sources.list.d/crt-music.list
# Architectures this repository publishes an index for. The package itself is
# Architecture: all, but APT only looks at the index for its own architecture.
REPO_ARCHES="amd64 arm64 armhf i386"

DRY_RUN=false
case "${1:-}" in
    --dry-run) DRY_RUN=true ;;
    "") ;;
    *) echo "usage: setup.sh [--dry-run]" >&2; exit 2 ;;
esac

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

command -v apt-get >/dev/null 2>&1 || die "this installer needs APT (Debian, Ubuntu, Mint, Pop!_OS, Raspberry Pi OS, ...).
On other distributions install python3, mpv and yt-dlp, then run install.sh
from the FSpotify source tree."

if [ "$(id -u)" -eq 0 ]; then
    SUDO=
elif command -v sudo >/dev/null 2>&1; then
    SUDO=sudo
    say "Installing system-wide; sudo may ask for your password."
else
    die "no root privileges: run this as root, or install sudo first."
fi

# Minimal and container images often lack these, and APT cannot verify a
# signed repository without gnupg and CA certificates.
need=
command -v curl >/dev/null 2>&1 || need="$need curl"
command -v gpg  >/dev/null 2>&1 || need="$need gnupg"
[ -e /etc/ssl/certs/ca-certificates.crt ] || need="$need ca-certificates"
if [ -n "$need" ]; then
    say "Installing prerequisites:$need"
    run $SUDO apt-get update || warn "apt-get update reported errors; continuing"
    run $SUDO apt-get install -y $need || die "could not install:$need"
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT INT TERM

say "Fetching the FSpotify signing key"
fetch "$PAGES_URL/apt-key.asc" "$tmpdir/apt-key.asc" \
    || die "could not download $PAGES_URL/apt-key.asc"
# A captive portal or proxy answers with an HTML page and a 200, which would
# otherwise end up installed as the repository key.
grep -q 'BEGIN PGP PUBLIC KEY BLOCK' "$tmpdir/apt-key.asc" \
    || die "what came back from $PAGES_URL/apt-key.asc is not an OpenPGP key;
check the network (a proxy or captive portal may have replaced it)."
gpg --dearmor --batch --yes --output "$tmpdir/crt-music.gpg" "$tmpdir/apt-key.asc" \
    || die "could not convert the signing key"

# /usr/share/keyrings only exists once some package has shipped a keyring into
# it, so on a clean system gpg -o /usr/share/keyrings/... fails with
# "can't create". Create the directory, and write the key with install(1) so a
# failed run cannot leave a truncated keyring behind.
say "Installing the signing key to $KEYRING"
run $SUDO install -d -m 0755 "$(dirname "$KEYRING")"
run $SUDO install -m 0644 "$tmpdir/crt-music.gpg" "$KEYRING"

arch=$(dpkg --print-architecture 2>/dev/null || echo unknown)
arch_published=false
for a in $REPO_ARCHES; do
    if [ "$a" = "$arch" ]; then
        arch_published=true
    fi
done

if $arch_published; then
    say "Writing $SOURCES_LIST"
    line="deb [arch=$arch signed-by=$KEYRING] $PAGES_URL $SUITE $COMPONENT"
    if $DRY_RUN; then
        printf '    would write: %s\n' "$line"
    else
        printf '%s\n' "$line" | $SUDO tee "$SOURCES_LIST" >/dev/null
    fi

    # Read only this list file. On a machine with some other third-party
    # repository already broken, a plain apt-get update fails and would take
    # this install down with it.
    say "Reading the FSpotify repository"
    run $SUDO apt-get update \
        -o Dir::Etc::sourcelist="$SOURCES_LIST" \
        -o Dir::Etc::sourceparts=- \
        -o APT::Get::List-Cleanup=0 \
        || die "could not read $PAGES_URL"

    say "Installing $PACKAGE"
    if ! run $SUDO apt-get install -y "$PACKAGE"; then
        # The dependencies come from the distribution's own sources, and a
        # stale index there is the usual reason the first attempt fails.
        say "Retrying after a full apt-get update"
        run $SUDO apt-get update || true
        run $SUDO apt-get install -y "$PACKAGE" || die "apt could not install $PACKAGE"
    fi
else
    # Rare architecture with no published index. The package is Architecture:
    # all, so the .deb itself still installs.
    warn "no package index is published for this architecture ($arch)"
    warn "installing the .deb directly; it will not update automatically."
    deb="${PACKAGE}_${VERSION}_all.deb"
    fetch "$PAGES_URL/pool/main/c/$PACKAGE/$deb" "$tmpdir/$deb" || die "could not download $deb"
    run $SUDO apt-get install -y "$tmpdir/$deb" || die "could not install $deb"
fi

# yt-dlp is a Recommends, so APT skips it silently on releases that do not
# package it. Without it, search and YouTube playback do not work.
if ! $DRY_RUN && ! command -v yt-dlp >/dev/null 2>&1; then
    say "Installing yt-dlp"
    $SUDO apt-get install -y yt-dlp >/dev/null 2>&1 || true
    if ! command -v yt-dlp >/dev/null 2>&1; then
        say "yt-dlp is not packaged for this release; fetching the official build"
        if fetch https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp "$tmpdir/yt-dlp"; then
            $SUDO install -m 0755 "$tmpdir/yt-dlp" /usr/local/bin/yt-dlp
        else
            warn "could not install yt-dlp: radio will work, YouTube search will not.
Install it yourself from https://github.com/yt-dlp/yt-dlp"
        fi
    fi
fi

if $DRY_RUN; then
    say "Dry run finished; nothing was changed."
    exit 0
fi

command -v crt-music >/dev/null 2>&1 \
    || die "the package installed but crt-music is not on PATH"
say "Done. Start it with:  crt-music"
