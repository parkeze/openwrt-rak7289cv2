# openwrt-rak7289cv2

OpenWrt device support for the RAKwireless RAK7289CV2 (WisGate Edge Pro V2),
and the ImageBuilders built with it. OpenWrt 25.12.6, `ramips/mt76x8`, profile
`rakwireless_rak7289cv2`.

The device tree and recipe are the ones prepared for upstream OpenWrt (the
shared `mt7628an_rakwireless_rak636.dtsi` is common to the RAK7268CV2). Once a
release carries them, this repo is no longer needed.

Built from [openwrt-device-template](https://github.com/parkeze/openwrt-device-template).

## Using a release

Assets are laid out like a target directory on downloads.openwrt.org, so
anything that fetches an official ImageBuilder and checks it against
`sha256sums` only needs a different base URL:

```
https://github.com/parkeze/openwrt-rak7289cv2/releases/download/25.12.6-1/
```

The ImageBuilder is the release's own tree with this device added, built from
the release's `config.buildinfo` and feeds; the build fails unless its vermagic
matches the release's kmods, so every upstream kmod and package still installs.

## Building

```bash
./build.sh 25.12.6 ramips mt76x8 out
```

Linux, on a case-sensitive filesystem, with
[OpenWrt's build dependencies](https://openwrt.org/docs/guide-developer/toolchain/install-buildsystem).

## RAK7289CV2

A RAK636 module, as in the RAK7268CV2: MT7628AN, 128MB RAM, 32MB W25Q256 SPI
NOR, Quectel EG95 LTE on USB, one 10/100 ethernet port (PoE in), a microSD slot
on the ethernet PHY's P1-P4 pads, and a 2.4GHz Wi-Fi radio. The flash map, the
four GPIO LEDs, the reset button and the modem's power line are the module's,
in the shared dtsi.

The rest differs between RAK636 gateways, and RAK records it per unit: a
hardware descriptor in the factory partition at 0x2000 (`RAK`, an md5, a
compression byte, a 4-hex-digit length, then JSON) names the modem, LoRa and
GNSS pins and the unit's capabilities. This unit's says, and the bench agreed:

| Line | GPIO | Exported as |
|---|---|---|
| Modem reset (pulse high) | 2 | `/sys/class/gpio/modem-reset` |
| LoRa card in slot 1, reset (active low) | 17 | `/sys/class/gpio/lora-reset` |
| GNSS reset (active low) | 16 | `/sys/class/gpio/gnss-reset` |
| Modem power (low is on) | 41 | held by the kernel |
| Dying gasp | 18 | `BTN_7` |

Capabilities: `dying_gasp solar_battery hwwdg lbt`. GPIO 42, the modem reset
on the RAK7268CV2, does nothing here.

What differs from the Lite, checked on a unit (2026-10-26):

- **The radios are on USB.** Up to two RAK5146 (SX1303) mPCIe cards, each a
  USB CDC-ACM device (`/dev/ttyACM*`, `kmod-usb-acm`) behind an internal USB
  hub: the modem on hub port 1, the first card on port 2, a CH340 on port 4,
  port 3 presumably the second card. Nothing on SPI CS1, and no reset GPIO for
  the host: the card's own STM32 owns it.
- **GNSS on UART1** (`/dev/ttyS1`), NMEA at 9600.
- **No I2C devices**, so no RGB light.
- **A CH340 USB-serial** on the hub (`kmod-usb-serial-ch341`), which ChirpStack
  uses for Modbus to the power board (hardware watchdog, solar battery). On the
  unit checked, nothing answered on it over PoE.
- **The panel has six lights**, mapped by eye: LoRa 1 is GPIO 15
  (`green:lora-1`), LoRa 2 is GPIO 14 (`green:lora-2`), ETH is GPIO 43 (`green:lan`,
  which also lights the RJ45 jack's green LED and follows the link), WLAN is
  GPIO 44 (`orange:wlan`). PWR is always on, LTE is the EG95's own status
  light, and the jack's orange LED is not driven by the SoC.

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

- **Which `/dev/ttyACM*` is LoRa1 or LoRa2.** The hub port (`1-1.2`, `1-1.3`) is stable where enumeration order is
  not.
- **Whether this revision has RAK's power-board watchdog**, which reboots a
  newer unit on DC power every ~10 minutes unless fed over the CH340
  (chirpstack/chirpstack-gateway-os#155).

### Installing

The stock Ralink U-Boot has a TFTP menu on the serial console (57600 8N1,
`bootdelay` 5s). **Back up the whole flash from the stock firmware first.**

- **1: Load system code to SDRAM via TFTP** boots the `initramfs-kernel.bin`
  without writing anything. Use it to try an image.
- **2: Load system code then write to Flash via TFTP** writes a
  `squashfs-sysupgrade.bin` to the firmware partition.
- Never 7 or 9: those rewrite the bootloader.

U-Boot's network needs a host that accepts its MAC. On the RAK7268CV2 the stock
environment has `ethaddr=03:17:73:AB:CD:EF`, a multicast address that switches,
Wi-Fi and macOS all drop, and it cannot be changed from the prompt; check this
unit's with `fw_printenv ethaddr`. A Linux or Windows machine on a direct cable
works. Installing from the running stock firmware over the network needs no
U-Boot:

```sh
wget -O /tmp/fw.bin http://<host>/openwrt-...-squashfs-sysupgrade.bin
sha256sum /tmp/fw.bin
mtd -r write /tmp/fw.bin firmware
```

From a running OpenWrt, `sysupgrade` takes the same `squashfs-sysupgrade.bin`.

## Licence

GPL-2.0, as OpenWrt. The device trees are `GPL-2.0-or-later OR MIT`.
