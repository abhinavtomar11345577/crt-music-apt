# FSpotify 1.1.0

A terminal music and internet radio player: a single Python file driving mpv,
so it runs on Linux, macOS and Windows alike.

## Linux and macOS

    curl -fsSL https://abhinavtomar11345577.github.io/crt-music-apt/setup.sh | sh

On Debian, Ubuntu and derivatives this adds the signed APT repository and
installs the `crt-music` package, so it updates with the system. Everywhere
else - Arch, Fedora, openSUSE, Alpine, Void, Gentoo, Solus, FreeBSD, Termux,
macOS - it installs the player under `~/.local` with whatever package manager
is present. Options:

    curl -fsSL https://abhinavtomar11345577.github.io/crt-music-apt/setup.sh | sh -s -- --dry-run     # change nothing
    curl -fsSL https://abhinavtomar11345577.github.io/crt-music-apt/setup.sh | sh -s -- --portable    # skip APT
    curl -fsSL https://abhinavtomar11345577.github.io/crt-music-apt/setup.sh | sh -s -- --uninstall   # remove it again

## Windows

In PowerShell, without administrator rights:

    irm https://abhinavtomar11345577.github.io/crt-music-apt/install.ps1 | iex

It installs windows-curses, mpv, yt-dlp and the player into
`%LOCALAPPDATA%\crt-music`, adds that to your PATH and makes a Start menu
entry. `-DryRun` and `-Uninstall` work as above:

    & ([scriptblock]::Create((irm https://abhinavtomar11345577.github.io/crt-music-apt/install.ps1))) -Uninstall

## By hand

With Python 3.9+, mpv and yt-dlp already installed, the player is one file:

    curl -fsSL https://abhinavtomar11345577.github.io/crt-music-apt/crt-music -o crt-music && chmod +x crt-music && ./crt-music

## APT repository by hand

    sudo install -d -m 0755 /usr/share/keyrings
    curl -fsSL https://abhinavtomar11345577.github.io/crt-music-apt/apt-key.asc \
      | sudo gpg --dearmor --yes -o /usr/share/keyrings/crt-music.gpg
    echo "deb [signed-by=/usr/share/keyrings/crt-music.gpg] https://abhinavtomar11345577.github.io/crt-music-apt stable main" \
      | sudo tee /etc/apt/sources.list.d/crt-music.list
    sudo apt update
    sudo apt install crt-music

## If YouTube will not play

YouTube only serves streams to a current yt-dlp, and most distributions
package one that is a year or more old: search still works, but nothing
plays. The installers take care of it; later on, fix it with

    crt-music --update-ytdlp

and check the whole setup with `crt-music --check`.
