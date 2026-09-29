# openwrt-device-template

Template for a repo that adds OpenWrt support for one device the release does
not cover, and publishes an ImageBuilder with it. One repo per device: the
repo is named `openwrt-<model>`, e.g. `openwrt-rak7268cv2`.

`build.sh` and the workflow are the same in every device repo. A device repo
is this template plus:

- `devices/<board>/<name>.dts` and `devices/<board>/openwrt.patch`
- the OpenWrt version, target and subtarget in `.github/workflows/build.yml`
- a README with the device's hardware facts and how to install it

## Adding the device

1. Use this template, name the repo `openwrt-<model>`.
2. Get the facts from the vendor's running firmware, not a datasheet: most
   vendor firmware is OpenWrt underneath. `/sys/firmware/fdt`, `/proc/mtd` and
   `/sys/kernel/debug/gpio` give the flash map and the wiring directly.
3. Write the DTS, and `openwrt.patch` against the release tag: the image
   recipe in `target/linux/<target>/image/`, plus whatever `board.d` network,
   LED and `uboot-envtools` entries the board needs. `build.sh` picks the
   device name out of the patch's `define Device/...`.
4. Keep the flash map identical to the vendor's so the bootloader, calibration
   and unit data are untouched.
5. Set the version, target and subtarget in the workflow, push, and tag
   `<openwrt-version>-<n>` to publish.

A device that works is worth sending upstream to openwrt/openwrt; this repo
exists for the time until a release contains it.

## Using a release

Assets are laid out like a target directory on downloads.openwrt.org, so
anything that fetches an official ImageBuilder and checks `sha256sums` only
needs a different base URL:

```
https://github.com/parkeze/openwrt-<model>/releases/download/<openwrt-version>-<n>/
```

The ImageBuilder is the release's own tree with the device added, built from
the release's `config.buildinfo` and feeds. The build fails unless its vermagic
matches the release's kmods, so every upstream kmod and package still installs.

## Building

```bash
./build.sh <openwrt-version> <target> <subtarget> out
```

Linux, on a case-sensitive filesystem, with
[OpenWrt's build dependencies](https://openwrt.org/docs/guide-developer/toolchain/install-buildsystem).
The first build compiles the toolchain and takes a couple of hours.

## Licence

GPL-2.0, as OpenWrt. Device trees are `GPL-2.0-or-later OR MIT`.
