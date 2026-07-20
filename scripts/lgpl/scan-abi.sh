#!/bin/bash
# LGPL-compliance scan for one ABI. AUTHORITATIVE check = the generated static
# module list (libvlcjni-modules.c) — it lists EXACTLY which VLC modules compile in.
# This is what caught GPL access_realrtsp; the static .so has no vlc_entry dynamic
# symbols to grep, so .so string/symbol greps FALSE-PASS for module presence.
# Plus tightened .so symbol checks for the GPL contribs (encoders/dvd/smbclient).
# Usage: LVROOT=<libvlcjni dir> NDK=<ndk dir> scan-abi.sh <abi>
set -o pipefail
ABI="$1"; [ -z "$ABI" ] && { echo "usage: scan-abi.sh <abi>"; exit 1; }
LVROOT="${LVROOT:-/home/agent/lgpl-build/libvlcjni}"
NDK="${NDK:-/opt/android-sdk/ndk/27.1.12297006}"
case "$ABI" in
  arm64-v8a)   TRIPLET=aarch64-linux-android ;;
  armeabi-v7a) TRIPLET=arm-linux-androideabi ;;
  x86_64)      TRIPLET=x86_64-linux-android ;;
  *) echo "unknown abi $ABI"; exit 1 ;;
esac
SO="$LVROOT/libvlc/jni/libs/$ABI/libvlc.so"
MODC="$LVROOT/vlc/build-android-$TRIPLET/ndk/libvlcjni-modules.c"
NM="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-nm"
command -v "$NM" >/dev/null || NM=nm
echo "==================== ABI: $ABI ($TRIPLET) ===================="
[ -f "$MODC" ] || { echo "MISSING module list $MODC"; exit 2; }
echo "  static modules: $(grep -c 'vlc_entry__' "$MODC")"
fail=0
echo "-- GPL VLC modules in the static list (expect NONE) --"
for m in access_realrtsp audioscrobbler glspectrum goom_ visual _mpc mpc_ x264 x265 dvdnav dvdread dvdcss t140 logger_file syslog headphone_channel_mixer; do
  grep -qE "vlc_entry__$m" "$MODC" && { echo "  FAIL present: $m"; fail=1; }
done
[ $fail -eq 0 ] && echo "  PASS  no GPL modules in the list"
echo "-- KEPT modules sanity (expect present) --"
for m in dsm smb2 mono rotate dolby_surround_decoder rtp; do
  grep -qE "vlc_entry__$m\b" "$MODC" && echo "  ok: $m" || echo "  WARN missing: $m"
done
if [ -f "$SO" ]; then
  syms=$("$NM" -D --defined-only "$SO" 2>/dev/null; "$NM" "$SO" 2>/dev/null)
  echo "-- .so GPL contrib symbols (expect absent) --"
  for pat in 'x264_[0-9]*_encoder_open|x264_encoder_open' 'x265_encoder_open|x265_api_get' 'dvdcss_open|dvdnav_open|DVDOpen' 'smbc_init|smbc_new_context'; do
    h=$(printf '%s\n' "$syms" | grep -E "$pat" | head -1)
    [ -n "$h" ] && { echo "  FAIL symbol: $pat"; fail=1; } || echo "  PASS absent: $pat"
  done
  printf '%s\n' "$syms" | grep -Eiq 'smb2_|bdsm_|dcerpc' && echo "  PASS libdsm/smb2 present" || echo "  WARN no libdsm"
fi
echo "==== ABI $ABI RESULT: $([ $fail -eq 0 ] && echo PASS || echo FAIL) ===="
exit $fail
