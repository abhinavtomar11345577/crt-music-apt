#!/usr/bin/env bash
set -euo pipefail

REPOSITORY=https://abhinavtomar11345577.github.io/crt-music-apt
KEYRING=/usr/share/keyrings/crt-music.gpg
SOURCES=/etc/apt/sources.list.d/crt-music.list

if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    SUDO=sudo
fi

key_file=$(mktemp)
trap 'rm -f "$key_file"' EXIT
curl -fsSL "$REPOSITORY/apt-key.asc" -o "$key_file"
$SUDO gpg --dearmor --yes -o "$KEYRING" "$key_file"
printf 'deb [signed-by=%s] %s stable main\n' "$KEYRING" "$REPOSITORY" \
    | $SUDO tee "$SOURCES" >/dev/null
$SUDO apt-get update
$SUDO apt-get install -y crt-music
