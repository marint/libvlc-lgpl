#!/bin/bash
# ============================================================================
# Reproduce the LGPL libVLC engine (all 3 ABIs) + package the AAR, from scratch.
#   clone libvlcjni@pinned -> get VLC@pinned -> apply the LGPL module-drop patches
#   -> build arm64/armv7/x86_64 -> AUTHORITATIVE module-list verify -> package AAR.
# Full recipe + rationale + version-bump playbook: docs/lgpl-android-build.md.
#
# The scan (scripts/lgpl/scan-abi.sh) is the SAFETY GATE: if any drop is missed,
# the module-list check FAILS and the build aborts — a silently-GPL .so can't ship.
#
# Prereqs (host apt): patch xz-utils bzip2 build-essential gperf ant zip unzip
#   git curl; NDK r27 (27.1.12297006); Android SDK build-tools; JDK 17.
# Usage: WORK=/path/to/build ./scripts/build-lgpl-libvlc.sh
# ============================================================================
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${WORK:-/home/agent/lgpl-build}"
NDK="${NDK:-/opt/android-sdk/ndk/27.1.12297006}"
LIBVLCJNI_TAG="${LIBVLCJNI_TAG:-3.7.5}"   # PINNED — matches the vendored AAR's Java layer
export LVROOT="$WORK/libvlcjni"
export NDK

mkdir -p "$WORK"; cd "$WORK"
if [ ! -d "$LVROOT/.git" ]; then
  echo "== clone libvlcjni@$LIBVLCJNI_TAG =="
  git clone --depth 1 --branch "$LIBVLCJNI_TAG" https://code.videolan.org/videolan/libvlcjni.git "$LVROOT"
  ( cd "$LVROOT" && git config user.email lgpl@build.local && git config user.name lgpl )
  echo "== get-vlc (fetch VLC@pinned + apply libvlcjni's own patches) =="
  ( cd "$LVROOT" && ./buildsystem/get-vlc.sh )
fi

# --- Apply the LGPL module-drop patches (idempotent). Exact set + rationale is the
#     drop table in docs/lgpl-android-build.md. Configure flags for lua/realrtsp/mpc;
#     Makefile.am LTLIBRARIES comment-outs for the no-flag GPL modules. ---
CL="$LVROOT/buildsystem/compile-libvlc.sh"
echo "== patch compile-libvlc.sh: disable lua/realrtsp/mpc + NDK-32bit r27/API24 =="
sed -i 's/--enable-lua \\/--disable-lua \\/g' "$CL"
grep -q -- '--disable-realrtsp' "$CL" || sed -i 's/--enable-realrtsp \\/--disable-realrtsp --disable-mpc \\/' "$CL"
# 32-bit: reuse r27 at ANDROID_API=24 (FLAC fseeko/ftello need 24+; = app minSdk).
python3 - "$CL" <<'PY'
import sys,re
f=sys.argv[1]; s=open(f).read()
if 'v21 or v27-29 needed for 32-bit' not in s:
    s=s.replace(
'''    if [ "$REL" != 21 ]; then
        echo "NDK v21 needed for 32-bit, got $REL cf. https://developer.android.com/ndk/downloads/"
        exit 1
    fi
    ANDROID_API=17''',
'''    if [ "$REL" = 21 ]; then
        ANDROID_API=17
    elif [ "$REL" = 27 ] || [ "$REL" = 28 ] || [ "$REL" = 29 ]; then
        ANDROID_API=24
    else
        echo "NDK v21 or v27-29 needed for 32-bit, got $REL cf. https://developer.android.com/ndk/downloads/"
        exit 1
    fi''')
    open(f,'w').write(s)
PY

echo "== patch VLC Makefile.am: comment the GPL modules' LTLIBRARIES entries =="
V="$LVROOT/vlc/modules"
# helper: comment "<pfx>_LTLIBRARIES += lib<mod>_plugin.la" and tag it.
drop_add() { # <makefile> <plugin-basename>
  local mf="$1" p="$2"
  grep -q "# LGPL: $p dropped" "$mf" 2>/dev/null && return 0
  sed -i "s|^\([a-z_]*_LTLIBRARIES += lib${p}_plugin.la\)|# LGPL: $p dropped (GPL) \1|" "$mf"
}
drop_add "$V/misc/Makefile.am"          audioscrobbler
drop_add "$V/logger/Makefile.am"        file_logger
drop_add "$V/logger/Makefile.am"        syslog
drop_add "$V/visualization/Makefile.am" glspectrum
drop_add "$V/visualization/Makefile.am" visual
drop_add "$V/visualization/Makefile.am" goom
drop_add "$V/stream_out/Makefile.am"    t140      2>/dev/null || true
drop_add "$V/codec/Makefile.am"         t140      2>/dev/null || true
# headphone: remove the single continuation line from the audio_filter list.
sed -i '/^[[:space:]]*libheadphone_channel_mixer_plugin\.la[[:space:]]*\\$/d' "$V/audio_filter/Makefile.am"
# force a re-bootstrap so the Makefile.am edits regenerate Makefile.in
rm -f "$LVROOT/vlc/configure"

echo "== build + verify each ABI (scan gates: any GPL module -> abort) =="
for abi in arm64-v8a armeabi-v7a x86_64; do
  LVROOT="$LVROOT" NDK="$NDK" bash "$REPO/scripts/lgpl/build-abi.sh" "$abi"
  LVROOT="$LVROOT" NDK="$NDK" bash "$REPO/scripts/lgpl/scan-abi.sh" "$abi" \
    || { echo "FATAL: $abi FAILED the LGPL module-list verify — a GPL drop is missing."; exit 4; }
done

echo "== package AAR =="
LVROOT="$LVROOT" VER="$LIBVLCJNI_TAG" OUT="$REPO/dist/libvlc-lgpl.aar" \
  bash "$REPO/scripts/lgpl/assemble-aar.sh"
echo "== DONE — AAR at dist/libvlc-lgpl.aar =="
