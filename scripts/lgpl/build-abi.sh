#!/bin/bash
# Build LGPL-only libVLC for ONE ABI from an ALREADY-PATCHED libvlcjni tree.
# CRITICAL: does NOT run get-vlc.sh — that does `git reset --hard` and would wipe
# the module-drop Makefile.am edits. For ABIs after the first, call this directly;
# the shared source is re-bootstrapped once (rm vlc/configure) by the driver.
# Usage: LVROOT=<dir> NDK=<dir> build-abi.sh <abi>
set -o pipefail
ABI="$1"; [ -z "$ABI" ] && { echo "usage: build-abi.sh <abi>"; exit 1; }
LVROOT="${LVROOT:-/home/agent/lgpl-build/libvlcjni}"
export ANDROID_NDK="${NDK:-/opt/android-sdk/ndk/27.1.12297006}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-/opt/android-sdk}"
export ANDROID_HOME="$ANDROID_SDK_ROOT"
export MAKEFLAGS="-j$(nproc)"
cd "$LVROOT" || exit 1

echo "==== $(date -u) SANITY: FINAL GPL drop set applied before build ===="
grep -q "LGPL: audioscrobbler dropped" vlc/modules/misc/Makefile.am || { echo "FATAL: audioscrobbler drop missing"; exit 3; }
grep -q "# LGPL: syslog" vlc/modules/logger/Makefile.am || { echo "FATAL: syslog drop missing"; exit 3; }
grep -qE "^[[:space:]]+libheadphone_channel_mixer_plugin\.la" vlc/modules/audio_filter/Makefile.am && { echo "FATAL: headphone still listed"; exit 3; }
grep -q "disable-lua" buildsystem/compile-libvlc.sh || { echo "FATAL: lua not disabled"; exit 3; }
grep -q "disable-realrtsp" buildsystem/compile-libvlc.sh || { echo "FATAL: realrtsp not disabled"; exit 3; }
echo "OK: final drop set present."

echo "==== $(date -u) compile-libvlc.sh -a $ABI --release --license a ===="
./buildsystem/compile-libvlc.sh -a "$ABI" --release --license a
rc=$?
echo "==== $(date -u) compile rc=$rc ===="
exit $rc
