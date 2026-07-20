# LGPL-only libVLC for Android — build recipe

This produces an **LGPLv2.1** libVLC for Android (not the GPL
`org.videolan.android:libvlc-all`), so it can be linked under LGPL terms. **One
command reproduces everything:** `./scripts/build-lgpl-libvlc.sh`.

## Why

The published `libvlc-all` AAR statically links GPL contribs (x264 encoder, dvdcss,
…) and compiles in GPL **modules** (`realrtsp`, `lua`, …). libVLC 3.0's `configure`
has no blanket `--disable-gpl` for modules, so they are dropped explicitly and the
result is verified against the authoritative module list. The target module set
matches VideoLAN's own LGPL **MobileVLCKit** (confirmed via its dSYM source paths).

## Prerequisites

- **NDK r27** (`27.1.12297006`). 64-bit builds at `ANDROID_API=21`; **32-bit at
  `ANDROID_API=24`** — r27 dropped API < 21, and the FLAC contrib calls
  `fseeko`/`ftello` which Android only declares at API 24+ (newer clang errors on
  the implicit decl).
- Android SDK build-tools (aapt2) + JDK 17.
- Host apt packages: `patch xz-utils bzip2 build-essential gperf ant zip unzip git curl`.
- Network reachable: `code.videolan.org`, `downloads.videolan.org`, `repo1.maven.org`,
  `dl.google.com`.

## Source (pinned)

- **libvlcjni @ tag `3.7.5`** — its Java JNI layer must match the AAR's `classes.jar`
  (see AAR packaging). `get-vlc.sh` fetches the matching libVLC 3.0.x source + applies
  libvlcjni's own patches.
- Build with `compile-libvlc.sh --license a` (LGPLv2.1 + ad-clauses;
  `--disable-gpl --disable-gnuv3`) — this strips GPL **contribs** (x264/x265/dvd/…).

## The FINAL drop set (matches MobileVLCKit)

DROP (via `compile-libvlc.sh` configure flags): **lua** (`--disable-lua`), **realrtsp**
(`--disable-realrtsp`), **mpc** (`--disable-mpc`).

DROP (comment the plugin's `*_LTLIBRARIES += lib<mod>_plugin.la` line in its Makefile.am;
requires a re-bootstrap = `rm vlc/configure`):

| Module | Makefile.am | LTLIBRARIES entry |
| --- | --- | --- |
| `misc/audioscrobbler` | `modules/misc/` | `misc_LTLIBRARIES += libaudioscrobbler_plugin.la` |
| `logger/file` | `modules/logger/` | `logger_LTLIBRARIES = … libfile_logger_plugin.la` |
| `logger/syslog` | `modules/logger/` | `logger_LTLIBRARIES += libsyslog_plugin.la` |
| `visualization/glspectrum` | `modules/visualization/` | `visu_LTLIBRARIES += libglspectrum_plugin.la` |
| `visualization/visual` | `modules/visualization/` | `visu_LTLIBRARIES += libvisual_plugin.la` |
| `visualization/goom` | `modules/visualization/` | `visu_LTLIBRARIES += libgoom_plugin.la` |
| `codec/t140` | `modules/codec/` | `codec_LTLIBRARIES += libt140_plugin.la` |
| `audio_filter/channel_mixer/headphone` | `modules/audio_filter/` | remove `libheadphone_channel_mixer_plugin.la \` from the list |

**KEEP** (LGPL-relicensed in VLCKit despite stale GPL file headers): `mono`, `dolby`
(`dolby_surround_decoder`), `rotate`, `rtp` (+rtpfmt/access), `dummy`, `freetype`.
SMB is **libdsm/libsmb2** (LGPL), never GPLv3 `libsmbclient`.

## Build

```
./scripts/build-lgpl-libvlc.sh          # clone → patch → build 3 ABIs → verify → AAR
```

It builds `arm64-v8a`, `armeabi-v7a`, `x86_64` from the SAME patched tree. **Never
re-run `get-vlc.sh` between ABIs** — its `git reset --hard` wipes the Makefile.am
edits; `scripts/lgpl/build-abi.sh` calls `compile-libvlc.sh` directly and its sanity
check refuses to build if a drop is missing. First build ~30–40 min/ABI (contrib +
libvlc). Disk: a full contrib is ~2.8 GB/ABI — build sequentially, cleaning each
ABI's `contrib/<triplet>` after harvesting its `.so`.

## Verify (AUTHORITATIVE — module list, not .so greps)

`scripts/lgpl/scan-abi.sh <abi>` checks the generated
`vlc/build-android-<triplet>/ndk/libvlcjni-modules.c` — the exact list of modules
compiled into the `.so`. **Do NOT rely on `nm`/`strings` of the `.so` for module
presence**: the static Android build has no `vlc_entry__*` dynamic symbols, so those
greps FALSE-PASS. The driver runs this per ABI and ABORTS if any GPL module survives.
Each ABI must show: drop set absent, `dsm`/`smb2` present, and (via `.so` symbols)
no `x264`/`x265` encoder, no `dvdcss`/`dvdnav`, no `libsmbclient`; libdsm present.

## AAR packaging (`scripts/lgpl/assemble-aar.sh`)

The libvlcjni Java layer has androidx deps that only gradle resolves cleanly, so it is
NOT hand-compiled. Instead take the OFFICIAL `libvlc-all-3.7.5.aar` from Maven (matched
`classes.jar` + manifest + assets), **remove its GPL `jni/x86`** ABI, and swap its
`jni/<abi>/{libvlc,libvlcjni}.so` for the LGPL-built ones. Java + JNI stay matched
(same 3.7.5). Output → `dist/libvlc-lgpl.aar`.

## Consuming the AAR

Drop `dist/libvlc-lgpl.aar` into a Gradle `flatDir` repo and depend on it in place of
`libvlc-all`, e.g.:

```gradle
repositories { flatDir { dirs 'libs' } }
dependencies { implementation(name: 'libvlc-lgpl', ext: 'aar') }
```

Build the consuming APK with all device ABIs you need (`arm64-v8a`, `armeabi-v7a`,
`x86_64`) — a build restricted to `arm64-v8a` won't install on a 32-bit device.

## Version-bump playbook (libVLC 3.x security/patch update)

1. Bump `LIBVLCJNI_TAG` in `scripts/build-lgpl-libvlc.sh` to the new tag; update the
   AAR version in `scripts/lgpl/assemble-aar.sh` (`VER`) to match (the official
   `libvlc-all-<VER>.aar` must exist on Maven).
2. Re-run `./scripts/build-lgpl-libvlc.sh`. If a Makefile.am moved a plugin entry, the
   `drop_add` sed becomes a no-op → **the scan will FAIL and abort** (safety gate);
   fix the anchor against the new source and re-run.
3. Confirm all 3 ABIs pass the module-list verify (the driver does this).
4. Rebuild the consuming APK with all ABIs; install to a real device and verify
   playback on the LGPL engine.
5. `git add` the new `dist/libvlc-lgpl.aar` + commit.

So future updates are a checklist, not archaeology.
