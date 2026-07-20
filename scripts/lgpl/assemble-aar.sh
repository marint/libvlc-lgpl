#!/bin/bash
# Package the LGPL AAR. The libvlcjni Java layer has androidx deps that only gradle
# resolves cleanly, so instead we take the OFFICIAL libvlc-all-<ver> AAR from Maven
# (matched classes.jar + manifest + assets), REMOVE its GPL jni/x86 ABI, and swap
# its jni/<abi>/{libvlc,libvlcjni}.so for OUR LGPL-built ones. Java+JNI stay matched
# (same version). Usage: LVROOT=<dir> VER=3.7.5 assemble-aar.sh  → libvlc-lgpl.aar
set -e
LVROOT="${LVROOT:-/home/agent/lgpl-build/libvlcjni}"
VER="${VER:-3.7.5}"
OUT="${OUT:-$(pwd)/libvlc-lgpl.aar}"
WORK="$(mktemp -d)"
MYLIBS="$LVROOT/libvlc/jni/libs"
OFFICIAL="$WORK/libvlc-all-$VER.aar"

echo "== fetch official libvlc-all-$VER.aar =="
curl -fsSL -o "$OFFICIAL" \
  "https://repo1.maven.org/maven2/org/videolan/android/libvlc-all/$VER/libvlc-all-$VER.aar"
echo "== unzip =="
unzip -q "$OFFICIAL" -d "$WORK/aar"
echo "== remove GPL x86 ABI (we don't build it) =="
rm -rf "$WORK/aar/jni/x86"
echo "== swap in our LGPL .so (arm64-v8a, armeabi-v7a, x86_64) =="
for abi in arm64-v8a armeabi-v7a x86_64; do
  for so in libvlc.so libvlcjni.so libc++_shared.so; do
    [ -f "$MYLIBS/$abi/$so" ] && cp -f "$MYLIBS/$abi/$so" "$WORK/aar/jni/$abi/$so"
  done
done
echo "== re-zip =="
rm -f "$OUT"
( cd "$WORK/aar" && zip -qr "$OUT" . )
rm -rf "$WORK"
echo "== DONE: $OUT =="
unzip -l "$OUT" | grep -oE "jni/[^/]+/" | sort -u
