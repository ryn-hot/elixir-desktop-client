#!/usr/bin/env bash
#
# Source this to expose libVLC for Tauri builds/run on macOS.
#
# usage: source scripts/env_vlc.sh

export LIBVLC_LIB_DIR="/Applications/VLC.app/Contents/MacOS/lib"
export LIBVLC_INCLUDE_DIR="/Applications/VLC.app/Contents/MacOS/include"
export DYLD_LIBRARY_PATH="${LIBVLC_LIB_DIR}:${DYLD_LIBRARY_PATH}"
export DYLD_FALLBACK_LIBRARY_PATH="${LIBVLC_LIB_DIR}:${DYLD_FALLBACK_LIBRARY_PATH}"
export LIBRARY_PATH="${LIBVLC_LIB_DIR}:${LIBRARY_PATH}"
export PKG_CONFIG_PATH="${LIBVLC_LIB_DIR}/pkgconfig:${PKG_CONFIG_PATH}"
# Force an rpath so the app can locate libvlc.dylib at runtime.
export RUSTFLAGS="${RUSTFLAGS} -C link-arg=-Wl,-rpath,${LIBVLC_LIB_DIR}"

echo "libVLC env configured for macOS (path: ${LIBVLC_LIB_DIR})"
echo "If the app still cannot load libvlc, try: export DYLD_FALLBACK_LIBRARY_PATH=${LIBVLC_LIB_DIR}"
