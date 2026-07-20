# libvlc-lgpl

Build tooling for an **LGPLv2.1-clean libVLC for Android**.

VideoLAN's prebuilt `org.videolan.android:libvlc-all` AAR is compiled with GPL-only
modules (`realrtsp`, `lua`, `mpc`, …), so anything that links it inherits GPL
obligations. This repo reproduces libVLC for Android with those GPL modules **dropped** —
the resulting module set matches VideoLAN's own official **LGPL** MobileVLCKit/TVVLCKit
(the iOS/tvOS builds already ship that) — so the library can be linked under **LGPL-2.1**
terms (e.g. dynamically from a non-GPL application).

## What's here

- `scripts/build-lgpl-libvlc.sh` — top-level build: clone `libvlcjni` at a pinned tag →
  fetch libVLC at the same pin → apply the module-drop configure flags → build
  `arm64-v8a` + `armeabi-v7a` + `x86_64` → verify the generated static-module list →
  package the AAR.
- `scripts/lgpl/{build-abi,scan-abi,assemble-aar}.sh` — per-ABI build, the authoritative
  module-list scan (it checks the generated module registry, not fragile `.so` string
  greps), and AAR assembly.
- `docs/lgpl-android-build.md` — the full recipe: prerequisites (NDK r27, `ANDROID_API=24`),
  the exact DROP set (`lua` / `realrtsp` / `mpc` …) and KEEP set, SMB via `libdsm`/`libsmb2`
  (LGPL) rather than `libsmbclient` (GPLv3), verification, packaging, and the version-bump
  playbook.
- `dist/libvlc-lgpl.aar` — a prebuilt AAR (`arm64-v8a` + `armeabi-v7a` + `x86_64`) so you can
  relink without rebuilding.

## Upstream source

libVLC is © VideoLAN and contributors, licensed LGPL-2.1 (a few LGPL-3.0 modules exist and
are excluded here). The source is upstream:

- **libvlcjni** (Android build system + Java layer):
  <https://code.videolan.org/videolan/libvlcjni> — tag **3.7.5**
- **libVLC core** — fetched by libvlcjni's `compile-libvlc.sh` at the matching pin.

This repo carries only the **modifications** (the module-drop configuration + build recipe)
needed to produce the LGPL subset. Together with the pinned upstream above, they are the
complete corresponding source for the modified library.

## Build

Linux + Android NDK r27, `ANDROID_API=24`:

```sh
scripts/build-lgpl-libvlc.sh      # builds all 3 ABIs → verify → dist/libvlc-lgpl.aar
```

Rebuild on any libVLC security / point update — see the version-bump playbook in the doc.

## License

The build scripts and docs here are provided under **LGPL-2.1** (see `LICENSE`), matching the
library they build. libVLC itself is © VideoLAN and contributors.
