# openwrt-rak7289cv2

OpenWrt device support for the RAKwireless RAK7289CV2 (WisGate Edge Pro V2),
and the ImageBuilders built with it. OpenWrt 24.10.0, `ramips/mt76x8`, profile
`rakwireless_rak7289cv2`.

Built from [openwrt-device-template](https://github.com/parkeze/openwrt-device-template).

## Using a release

Assets are laid out like a target directory on downloads.openwrt.org, so
anything that fetches an official ImageBuilder and checks it against
`sha256sums` only needs a different base URL:

```
https://github.com/parkeze/openwrt-rak7289cv2/releases/download/24.10.0-1/
```

The ImageBuilder is the release's own tree with this device added, built from
the release's `config.buildinfo` and feeds; the build fails unless its vermagic
matches the release's kmods, so every upstream kmod and package still installs.

## Building

```bash
./build.sh 24.10.0 ramips mt76x8 out
```

Linux, on a case-sensitive filesystem, with
[OpenWrt's build dependencies](https://openwrt.org/docs/guide-developer/toolchain/install-buildsystem).

## RAK7289CV2

A RAK636 module — the same board as the RAK7268CV2. MT7628AN, 128MB RAM, 32MB
W25Q256 SPI NOR, Quectel EG95 LTE on USB, one 10/100 ethernet port, a microSD
slot on the ethernet PHY's P1-P4 pads, and a 2.4GHz Wi-Fi radio. RAK ships one
firmware image ("RAK636") for the whole WisGate Edge line, so the device tree,
flash map and GPIOs here are read directly from that image and are identical to
the RAK7268CV2's.

**The one difference is the radio.** The Pro is 16 channels: two RAK5146
(SX1303) concentrators on mPCIe, each presenting as a USB CDC-ACM device
(`/dev/ttyACM0`, `/dev/ttyACM1`). Where the Lite has a single SX1302 on SPI
CS1, this board has nothing on SPI CS1 — the concentrators are on USB. So the
device tree here carries no concentrator SPI node, and the image pulls
`kmod-usb-acm`. The SX1303's own STM32 owns its reset line over USB; there is
no reset GPIO for the host to drive.

The slot 1 concentrator's GNSS is presented on `/dev/ttyS1` (via gpsd in the
stock firmware).

Flash map, identical to the vendor's so the bootloader, calibration and RAK's
unit data are untouched:

| Offset | Size | Partition |
|---|---|---|
| 0x000000 | 0x30000 | u-boot (read-only) |
| 0x030000 | 0x10000 | u-boot-env |
| 0x040000 | 0xe000 | factory: WiFi calibration and MACs (read-only) |
| 0x04e000 | 0x2000 | pst-data: RAK's unit identity (read-only) |
| 0x050000 | 0x1fb0000 | firmware |

### Not yet verified on hardware

The device tree, flash map, LEDs and modem GPIOs come from RAK's shipping
firmware and match the RAK7268CV2, which has been on the bench. Two things want
a unit to confirm:

- **Which `/dev/ttyACM*` is which slot.** USB enumeration order is not
  guaranteed to match the panel's LoRa1/LoRa2. Confirm before trusting the
  slot-to-radio mapping.
- **That `/dev/ttyS1` GNSS is populated** and answers.

### Installing

The stock Ralink U-Boot has a TFTP menu on the serial console (57600 8N1,
`bootdelay` 5s). **Back up the whole flash from the stock firmware first.**

- **1: Load system code to SDRAM via TFTP** boots the `initramfs-kernel.bin`
  without writing anything. Use it to try an image.
- **2: Load system code then write to Flash via TFTP** writes a
  `squashfs-sysupgrade.bin` to the firmware partition.
- Never 7 or 9: those rewrite the bootloader.

Installing from the running stock firmware over the network needs no U-Boot:

```sh
wget -O /tmp/fw.bin http://<host>/openwrt-...-squashfs-sysupgrade.bin
sha256sum /tmp/fw.bin
mtd -r write /tmp/fw.bin firmware
```

From a running OpenWrt, `sysupgrade` takes the same `squashfs-sysupgrade.bin`.

## Licence

GPL-2.0, as OpenWrt. The device trees are `GPL-2.0-or-later OR MIT`.
