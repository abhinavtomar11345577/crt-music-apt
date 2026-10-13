# FSpotify APT repository

Install FSpotify on Debian or Ubuntu:

    curl -fsSL https://abhinavtomar11345577.github.io/crt-music-apt/apt-key.asc \
      | sudo gpg --dearmor -o /usr/share/keyrings/crt-music.gpg
    echo "deb [signed-by=/usr/share/keyrings/crt-music.gpg] https://abhinavtomar11345577.github.io/crt-music-apt stable main" \
      | sudo tee /etc/apt/sources.list.d/crt-music.list
    sudo apt update
    sudo apt install crt-music

The package installs the crt-music command and a desktop entry. It depends
on Python 3, mpv, and yt-dlp. Remove it with: sudo apt remove crt-music.
