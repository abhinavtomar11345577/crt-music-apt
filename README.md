# FSpotify APT repository

Install FSpotify on Debian, Ubuntu or a derivative:

    curl -fsSL https://abhinavtomar11345577.github.io/crt-music-apt/setup.sh | sh

That adds this signed repository and installs the `crt-music` package, so it
updates with the rest of the system. Pass `--dry-run` to print the changes it
would make without making them:

    curl -fsSL https://abhinavtomar11345577.github.io/crt-music-apt/setup.sh | sh -s -- --dry-run

Or add the repository by hand:

    sudo install -d -m 0755 /usr/share/keyrings
    curl -fsSL https://abhinavtomar11345577.github.io/crt-music-apt/apt-key.asc \
      | sudo gpg --dearmor --yes -o /usr/share/keyrings/crt-music.gpg
    echo "deb [signed-by=/usr/share/keyrings/crt-music.gpg] https://abhinavtomar11345577.github.io/crt-music-apt stable main" \
      | sudo tee /etc/apt/sources.list.d/crt-music.list
    sudo apt update
    sudo apt install crt-music

The package installs the crt-music command and a desktop entry. It needs
Python 3 and mpv, and uses yt-dlp for YouTube search and playback. Remove it
with: sudo apt remove crt-music.
