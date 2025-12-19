# Tauri dev quickstart (libVLC)

Prereqs:
- VLC installed at `/Applications/VLC.app` (macOS) so libvlc is available.
- Rust toolchain updated (Rust 1.88+ recommended).

Env (macOS example):
```
export LIBVLC_LIB_DIR=/Applications/VLC.app/Contents/MacOS/lib
export LIBVLC_INCLUDE_DIR=/Applications/VLC.app/Contents/MacOS/include
export DYLD_LIBRARY_PATH=$LIBVLC_LIB_DIR:$DYLD_LIBRARY_PATH
export LIBRARY_PATH=$LIBVLC_LIB_DIR:$LIBRARY_PATH
export PKG_CONFIG_PATH=$LIBVLC_LIB_DIR/pkgconfig:$PKG_CONFIG_PATH
source ./scripts/env_vlc.sh     # optional shortcut
```

Windows (PowerShell, adjust VLC path):
```
$env:LIBVLC_LIB_DIR="C:\Program Files\VideoLAN\VLC"
$env:LIBVLC_INCLUDE_DIR="$env:LIBVLC_LIB_DIR\sdk\include"
$env:PATH="$env:LIBVLC_LIB_DIR;$env:PATH"
```

Linux (Debian/Ubuntu example):
```
sudo apt-get install vlc libvlc-dev
export LIBVLC_LIB_DIR=/usr/lib
export LIBVLC_INCLUDE_DIR=/usr/include
export LD_LIBRARY_PATH=$LIBVLC_LIB_DIR:$LD_LIBRARY_PATH
export PKG_CONFIG_PATH=/usr/lib/pkgconfig:$PKG_CONFIG_PATH
```

Run dev/build:
```
cd elixir-client/src-tauri
ln -sf ../tauri.conf.json tauri.conf.json   # already present, ensure link exists
cargo build                                 # embed VLC/HLS code path
```

Tauri dev helpers:
- macOS with VLC env: `npm run tauri:dev:vlc` (from `elixir-client`)
- Generic: set the env above for your OS, then `npm run tauri` (from `elixir-client`)

Smoke test:
- Start the Elixir server with media available.
- In the React client, select a server, log in, pick a media item, enable “Embed libVLC” (or external VLC), and start playback.
- Use the seek slider; server should receive `/api/v1/sessions/{id}/seek` and playback resumes with cache-busted URL.
